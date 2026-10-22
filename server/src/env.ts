import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import type { Account } from "./account";

export interface Env {
  OAUTH_KV: KVNamespace;
  ACCOUNTS: DurableObjectNamespace<Account>;
  /** Injected by OAuthProvider into the default handler. */
  OAUTH_PROVIDER: OAuthHelpers;
}

/** What an agent's access token carries: the account it may read and write. */
export interface Props extends Record<string, unknown> {
  accountId: string;
  /** The account's agents key when this agent connected; see Account.agentsKey(). */
  agentsKey: string;
}

export function account(env: Env, accountId: string) {
  return env.ACCOUNTS.get(env.ACCOUNTS.idFromName(accountId));
}

/** Pairing codes shown in the app; an agent's sign-in page asks for one. */
export const pairingKey = (code: string) => `pairing:${code.trim().toUpperCase()}`;
export const PAIRING_SECONDS = 600;

/** Best-effort cleanup of OAuth grants. Access ends immediately through the agents key. */
export async function revokeAgents(env: Env, accountId: string): Promise<void> {
  let cursor: string | undefined;
  do {
    const page = await env.OAUTH_PROVIDER.listUserGrants(accountId, { cursor });
    for (const grant of page.items) await env.OAUTH_PROVIDER.revokeGrant(grant.id, accountId);
    cursor = page.cursor;
  } while (cursor);
}
