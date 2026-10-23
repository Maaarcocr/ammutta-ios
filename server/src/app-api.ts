import { handleSubscriptionUpload, subscriptionStatus } from "./billing";
import { account, type Env, PAIRING_SECONDS, pairingKey, revokeAgents } from "./env";

// The Ammutta app's API. Each phone makes up a random account ID and a long random secret;
// the first request claims the account, and every later one must carry the same secret.
// Sending data and connecting agents need an active subscription (402 otherwise).
//
//   PUT    /v1/accounts/:id/snapshot     the app's latest data (JSON)
//   GET    /v1/accounts/:id/subscription whether the AI Agents subscription is active
//   POST   /v1/accounts/:id/subscription an Apple-signed transaction from StoreKit
//   GET    /v1/accounts/:id/inbox        plans agents wrote, waiting to be imported
//   DELETE /v1/accounts/:id/inbox/:item  imported (or unusable): remove it
//   POST   /v1/accounts/:id/pairing      a one-time code for connecting an agent
//   GET    /v1/accounts/:id/pairing/:code whether that code was used yet, and by which agent
//   GET    /v1/accounts/:id/agents       the agents connected to this account
//   DELETE /v1/accounts/:id/agents       disconnect every agent
//   DELETE /v1/accounts/:id              turn off: disconnect agents and delete everything

const MAX_SNAPSHOT_BYTES = 10_000_000;
// No 0/O or 1/I, so codes are easy to read and type.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function pairingCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return [...bytes].map((byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

const error = (status: number, message: string) => Response.json({ error: message }, { status });

export async function handleAppRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const match = /^\/v1\/accounts\/([0-9a-f-]{36})(\/[a-z]+)?(?:\/([0-9a-z-]{8,36}))?$/i.exec(url.pathname);
  if (!match) return error(404, "not found");
  const [, accountId, resource = "", itemId] = match;

  const secret = request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  if (secret.length < 32) return error(401, "missing secret");
  const store = account(env, accountId.toLowerCase());
  if (!(await store.claim(await sha256(secret)))) return error(401, "wrong secret");

  const route = `${request.method} ${resource}${itemId ? "/:item" : ""}`;
  const subscribed = async () => (await subscriptionStatus(env, accountId.toLowerCase())).active;
  switch (route) {
    case "GET /subscription":
      return Response.json(await subscriptionStatus(env, accountId.toLowerCase()));
    case "POST /subscription":
      return handleSubscriptionUpload(request, env, accountId.toLowerCase());
    case "PUT /snapshot": {
      if (!(await subscribed())) return error(402, "subscription inactive");
      const body = await request.text();
      if (body.length > MAX_SNAPSHOT_BYTES) return error(413, "snapshot too large");
      try {
        JSON.parse(body);
      } catch {
        return error(400, "snapshot is not JSON");
      }
      await store.putSnapshot(body);
      return new Response(null, { status: 204 });
    }
    case "GET /inbox":
      return Response.json(await store.listInbox());
    case "DELETE /inbox/:item":
      await store.removeFromInbox(itemId);
      return new Response(null, { status: 204 });
    case "POST /pairing": {
      if (!(await subscribed())) return error(402, "subscription inactive");
      const code = pairingCode();
      await env.OAUTH_KV.put(pairingKey(code), accountId.toLowerCase(), { expirationTtl: PAIRING_SECONDS });
      await store.issuePairingCode(code, Date.now() + PAIRING_SECONDS * 1000);
      return Response.json({ code, expiresInSeconds: PAIRING_SECONDS });
    }
    case "GET /pairing/:item":
      return Response.json(await store.pairingStatus(itemId.toUpperCase()));
    case "GET /agents":
      return Response.json(await store.agents());
    case "DELETE /agents":
      await store.rotateAgentsKey();
      await revokeAgents(env, accountId.toLowerCase());
      return new Response(null, { status: 204 });
    case "DELETE ":
      await revokeAgents(env, accountId.toLowerCase());
      await store.destroy();
      return new Response(null, { status: 204 });
    default:
      return error(404, "not found");
  }
}
