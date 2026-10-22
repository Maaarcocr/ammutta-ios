// End-to-end check against a running server (`npx wrangler dev`):
//   node test/e2e.mjs [base URL, default http://localhost:8787]
// Walks the app sync, pairing, an agent's OAuth sign-in and every MCP tool.
import assert from "node:assert/strict";
import { createHash, randomBytes, randomUUID } from "node:crypto";

const base = process.argv[2] ?? "http://localhost:8787";
const accountId = randomUUID();
const secret = randomBytes(32).toString("hex");
const app = (path, init = {}) =>
  fetch(`${base}/v1/accounts/${accountId}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${secret}`, ...init.headers },
  });

const snapshot = {
  generatedAt: new Date().toISOString(),
  unit: "kg",
  plans: [{ id: randomUUID(), name: "Push", exercises: [{ exercise: "barbell-bench-press", name: "Bench Press", sets: "3x8@60", restSeconds: 150 }] }],
  workouts: [
    { id: randomUUID(), plan: "Push", startedAt: "2026-10-20T18:00:00Z", endedAt: "2026-10-20T18:45:00Z", durationMinutes: 45, exercises: [] },
    { id: randomUUID(), plan: "Push", startedAt: "2026-10-01T18:00:00Z", endedAt: "2026-10-01T18:40:00Z", durationMinutes: 40, exercises: [] },
  ],
  customExercises: [{ name: "Band Pull-Apart", kind: "reps" }],
  builtInExercises: [
    { key: "barbell-bench-press", name: "Bench Press", kind: "reps", equipment: "barbell", muscle: "chest" },
    { key: "plank", name: "Plank", kind: "timed", equipment: "bodyweight", muscle: "core" },
  ],
};

// 1. The app claims its account and syncs.
assert.equal((await app("/snapshot", { method: "PUT", body: JSON.stringify(snapshot) })).status, 204);
const intruder = await fetch(`${base}/v1/accounts/${accountId}/inbox`, { headers: { Authorization: `Bearer ${"x".repeat(64)}` } });
assert.equal(intruder.status, 401, "another secret is refused");

// 2. The app asks for a pairing code.
const { code } = await (await app("/pairing", { method: "POST" })).json();
assert.match(code, /^[A-Z2-9]{8}$/);

// 3. An agent registers and signs in with the code.
const redirectUri = "https://agent.example/callback";
const client = await (await fetch(`${base}/oauth/register`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ client_name: "Test Agent", redirect_uris: [redirectUri], token_endpoint_auth_method: "none" }),
})).json();
assert.ok(client.client_id, JSON.stringify(client));

const verifier = randomBytes(32).toString("base64url");
const challenge = createHash("sha256").update(verifier).digest("base64url");
const authorizeURL = `${base}/authorize?` + new URLSearchParams({
  response_type: "code", client_id: client.client_id, redirect_uri: redirectUri, state: "s1",
  code_challenge: challenge, code_challenge_method: "S256", scope: "ammutta", resource: `${base}/mcp`,
});
const consent = await fetch(authorizeURL);
assert.equal(consent.status, 200, await consent.clone().text());
const html = await consent.text();
assert.match(html, /Connect Test Agent to Ammutta\?/);
const handle = /name="handle" value="([^"]+)"/.exec(html)[1];
const cookie = consent.headers.getSetCookie().map((value) => value.split(";")[0]).join("; ");

const post = (fields) => fetch(`${base}/authorize`, {
  method: "POST", redirect: "manual",
  headers: { "Content-Type": "application/x-www-form-urlencoded", Cookie: cookie, Origin: base },
  body: new URLSearchParams(fields),
});
const wrong = await post({ handle, code: "WRONGCOD", decision: "approve", retry: authorizeURL });
assert.equal(wrong.status, 400, "a wrong code is refused");
const approved = await post({ handle, code: code.toLowerCase(), decision: "approve", retry: authorizeURL });
assert.equal(approved.status, 302, await approved.text());
const callback = new URL(approved.headers.get("Location"));
assert.equal(callback.searchParams.get("state"), "s1");

const tokens = await (await fetch(`${base}/oauth/token`, {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({
    grant_type: "authorization_code", code: callback.searchParams.get("code"), redirect_uri: redirectUri,
    client_id: client.client_id, code_verifier: verifier, resource: `${base}/mcp`,
  }),
})).json();
assert.ok(tokens.access_token, JSON.stringify(tokens));

// 4. The agent uses the tools.
let id = 0;
async function rpc(method, params = {}) {
  const response = await fetch(`${base}/mcp`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${tokens.access_token}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      "MCP-Protocol-Version": "2025-06-18",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
  });
  const body = await response.text();
  assert.equal(response.status, 200, body);
  const json = body.startsWith("{") ? body : /^data: (.*)$/m.exec(body)[1];
  const message = JSON.parse(json);
  assert.ok(!message.error, JSON.stringify(message.error));
  return message.result;
}
const call = async (name, args = {}) => (await rpc("tools/call", { name, arguments: args })).content[0].text;

const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "e2e", version: "1" } });
assert.match(init.instructions, /strength-training/);
const tools = (await rpc("tools/list")).tools.map((tool) => tool.name).sort();
assert.deepEqual(tools, ["create_plan", "list_exercises", "list_plans", "list_workouts", "update_plan"]);

const recent = JSON.parse(await call("list_workouts", { since: "2026-10-10" }));
assert.equal(recent.workouts.length, 1);
assert.equal(JSON.parse(await call("list_exercises")).builtIn.length, 2);

assert.match(await call("create_plan", { name: "Bad", exercises: [{ exercise: "plank", sets: "3x8" }] }), /takes timed sets/);
assert.match(await call("create_plan", {
  name: "Pull Day", exercises: [{ exercise: "Band Pull-Apart", sets: "3x15", rest_seconds: 60 }, { exercise: "plank", sets: "2x45s" }],
}), /Saved "Pull Day"/);
assert.match(await call("update_plan", { plan_id: "nope", name: "X", exercises: [{ exercise: "plank", sets: "45s" }] }), /No plan with id/);
assert.match(await call("update_plan", {
  plan_id: snapshot.plans[0].id, name: "Push v2", exercises: [{ exercise: "barbell-bench-press", sets: "5x5@70" }],
}), /Saved "Push v2"/);
assert.equal(JSON.parse(await call("list_plans")).pendingFromAgents.length, 2);

// 5. The app imports the inbox.
const inbox = await (await app("/inbox")).json();
assert.deepEqual(inbox.map((item) => item.name), ["Pull Day", "Push v2"]);
assert.equal(inbox[0].link, "ammutta://plan?v=1&name=Pull%20Day&e=Band%20Pull-Apart%3A3x15%3A60&e=plank%3A2x45s");
assert.equal(inbox[1].planId, snapshot.plans[0].id);
for (const item of inbox) assert.equal((await app(`/inbox/${item.id}`, { method: "DELETE" })).status, 204);
assert.deepEqual(await (await app("/inbox")).json(), []);

// 6. Disconnecting agents cuts off their access immediately (the account's agents key changes).
assert.equal((await app("/agents", { method: "DELETE" })).status, 204);
const revoked = await fetch(`${base}/mcp`, { method: "POST", headers: { Authorization: `Bearer ${tokens.access_token}` } });
assert.equal(revoked.status, 401);

// 7. Turning off deletes the account; the next request claims it fresh.
assert.equal((await app("", { method: "DELETE" })).status, 204);
console.log("e2e OK");
