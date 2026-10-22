import type { JWSTransactionDecodedPayload } from "@apple/app-store-server-library";
import { account, type Env, subscriptionKey } from "./env";
import { entitlementFrom, isActive, notificationTransaction, verifyNotification, verifyTransaction } from "./subscription";

/** The subscription status the app shows. */
export async function subscriptionStatus(env: Env, accountId: string) {
  const entitlement = await account(env, accountId).entitlement();
  return { active: isActive(entitlement, Date.now()), expiresAt: entitlement ? new Date(entitlement.expiresAt).toISOString() : null };
}

/**
 * Records a verified transaction on an account. A subscription belongs to one account at a time:
 * the newest account to present it takes it over, so one purchase can't unlock many accounts.
 */
async function apply(env: Env, accountId: string, transaction: JWSTransactionDecodedPayload): Promise<string | null> {
  const entitlement = entitlementFrom(transaction);
  if (typeof entitlement === "string") return entitlement;
  const key = subscriptionKey(entitlement.originalTransactionId);
  const previous = await env.OAUTH_KV.get(key);
  if (previous && previous !== accountId) await account(env, previous).setEntitlement(undefined);
  await env.OAUTH_KV.put(key, accountId);
  await account(env, accountId).setEntitlement(entitlement);
  return null;
}

/** POST /v1/accounts/:id/subscription from the app, with the signed transaction StoreKit gave it. */
export async function handleSubscriptionUpload(request: Request, env: Env, accountId: string): Promise<Response> {
  const body = (await request.json().catch(() => null)) as { transaction?: unknown } | null;
  const jws = typeof body?.transaction === "string" ? body.transaction : "";
  const transaction = jws ? await verifyTransaction(env, jws) : null;
  if (!transaction) return Response.json({ error: "transaction not signed by Apple for this app" }, { status: 400 });
  // Purchases made in the app name their account; codes redeemed elsewhere name none.
  if (transaction.appAccountToken && transaction.appAccountToken.toLowerCase() !== accountId) {
    return Response.json({ error: "transaction belongs to another account" }, { status: 403 });
  }
  const problem = await apply(env, accountId, transaction);
  if (problem) return Response.json({ error: problem }, { status: 400 });
  return Response.json(await subscriptionStatus(env, accountId));
}

/**
 * POST /apple/notifications: App Store Server Notifications V2 (renewals, expiries, refunds,
 * revocations). Apple signs them, so the endpoint needs no other authentication.
 */
export async function handleAppleNotification(request: Request, env: Env): Promise<Response> {
  const body = (await request.json().catch(() => null)) as { signedPayload?: unknown } | null;
  const payload = typeof body?.signedPayload === "string" ? body.signedPayload : "";
  const notification = payload ? await verifyNotification(env, payload) : null;
  if (!notification) return new Response("Not signed by Apple for this app\n", { status: 400 });

  const signedTransaction = notificationTransaction(notification);
  const transaction = signedTransaction ? await verifyTransaction(env, signedTransaction) : null;
  if (!transaction?.originalTransactionId) return new Response(null, { status: 200 });
  const accountId =
    transaction.appAccountToken?.toLowerCase() ?? (await env.OAUTH_KV.get(subscriptionKey(transaction.originalTransactionId)));
  if (accountId) await apply(env, accountId, transaction);
  // Unknown subscriptions are acknowledged too, or Apple keeps retrying.
  return new Response(null, { status: 200 });
}
