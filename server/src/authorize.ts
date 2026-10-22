import type { ConsentDescription } from "@cloudflare/workers-oauth-provider";
import { type Env, pairingKey } from "./env";

// The sign-in page an agent opens when it connects: it shows who is asking and asks for the
// pairing code from Ammutta's Settings. The code proves the person connecting owns the account.

const escape = (value: string) => value.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<style>
  body { font: 17px -apple-system, system-ui, sans-serif; max-width: 30rem; margin: 3rem auto; padding: 0 1rem; color: #111; }
  input { font: 24px ui-monospace, monospace; letter-spacing: .2em; text-transform: uppercase; width: 100%; padding: .5rem; box-sizing: border-box; }
  button { font: inherit; padding: .6rem 1.2rem; margin: 1rem .5rem 0 0; }
  .muted { color: #666; }
  @media (prefers-color-scheme: dark) { body { background: #000; color: #eee; } .muted { color: #999; } }
</style></head><body>${body}</body></html>`;
}

function consentPage(details: ConsentDescription, handle: string, retry: string, message = ""): string {
  const name = escape(details.clientName);
  const origin = details.clientDomain
    ? `Published by <strong>${escape(details.clientDomain)}</strong>.`
    : "This app registered itself; its name is not verified.";
  return page(
    `Connect ${details.clientName} to Ammutta`,
    `<h1>Connect ${name} to Ammutta?</h1>
<p>${origin} It will be able to read your plans and workout history and add plans.
Access goes to <strong>${escape(details.redirectHost)}</strong>.</p>
${details.redirectIsLoopback ? "<p><strong>This sends access to an app on your computer.</strong> Continue only if you just started connecting from it.</p>" : ""}
${message ? `<p><strong>${escape(message)}</strong></p>` : ""}
<form method="post">
  <input type="hidden" name="handle" value="${escape(handle)}">
  <input type="hidden" name="retry" value="${escape(retry)}">
  <label for="code">Pairing code from Ammutta → Settings → AI Agents</label>
  <input id="code" name="code" autocomplete="one-time-code" autocapitalize="characters" required>
  <button name="decision" value="approve">Connect</button>
  <button name="decision" value="deny" formnovalidate>Cancel</button>
</form>
<p class="muted">You can disconnect every agent at any time from Ammutta's Settings.</p>`,
  );
}

export async function handleAuthorize(request: Request, env: Env): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER;
  if (request.method === "GET") {
    let authRequest: Awaited<ReturnType<typeof oauth.parseAuthRequest>>;
    try {
      authRequest = await oauth.parseAuthRequest(request);
    } catch (error) {
      // Never redirect a request whose client or redirect address didn't check out.
      const message = error instanceof Error ? error.message : "Invalid request";
      return new Response(page("Can't connect", `<h1>Can't connect</h1><p>${escape(message)}</p>`), {
        status: 400,
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }
    const details = await oauth.describeConsent(authRequest);
    const consent = await oauth.beginConsent(authRequest);
    consent.headers.set("Content-Type", "text/html; charset=utf-8");
    return new Response(consentPage(details, consent.handle, request.url), { headers: consent.headers });
  }

  const form = await request.formData();
  const handle = String(form.get("handle") ?? "");
  if (form.get("decision") !== "approve") {
    const denied = await oauth.denyConsent(request, handle);
    return new Response(null, { status: 302, headers: denied.headers });
  }

  const code = String(form.get("code") ?? "");
  const accountId = code ? await env.OAUTH_KV.get(pairingKey(code)) : null;
  if (!accountId) {
    // Only offer to start over on this server's own sign-in URL.
    const retry = String(form.get("retry") ?? "");
    const sameOrigin = retry.startsWith(`${new URL(request.url).origin}/authorize?`);
    return new Response(
      page(
        "Code didn't work",
        `<h1>That code didn't work</h1>
<p>Codes work once and expire after 10 minutes. Get a new one in Ammutta → Settings → AI Agents.</p>
${sameOrigin ? `<p><a href="${escape(retry)}">Try again</a></p>` : ""}`,
      ),
      { status: 400, headers: { "Content-Type": "text/html; charset=utf-8" } },
    );
  }
  await env.OAUTH_KV.delete(pairingKey(code));

  const approved = await oauth.approveConsent(request, handle, {});
  const { redirectTo } = await oauth.completeAuthorization({
    request: approved.request,
    userId: accountId,
    metadata: {},
    scope: approved.request.scope,
    props: { accountId },
  });
  approved.headers.set("Location", redirectTo);
  return new Response(null, { status: 302, headers: approved.headers });
}
