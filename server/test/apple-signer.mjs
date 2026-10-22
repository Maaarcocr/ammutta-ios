// Signs fake App Store data with the test-only chain in test/apple-test-ca, in Apple's JWS format.
// The server accepts it only under `cf dev --mode test`.
import { createPrivateKey, randomUUID, sign } from "node:crypto";
import { readFileSync } from "node:fs";

const dir = new URL("./apple-test-ca/", import.meta.url);
const pemToDer = (name) =>
  readFileSync(new URL(name, dir), "utf8").replace(/-----[^-]+-----|\s/g, "");
const chain = [pemToDer("leaf.pem"), pemToDer("intermediate.pem"), pemToDer("root.pem")];
const key = createPrivateKey(readFileSync(new URL("leaf.pkcs8.pem", dir)));
const b64url = (value) => Buffer.from(typeof value === "string" ? value : JSON.stringify(value)).toString("base64url");

export function signJWS(payload, signingKey = key) {
  const input = `${b64url({ alg: "ES256", x5c: chain })}.${b64url(payload)}`;
  const signature = sign("sha256", Buffer.from(input), { key: signingKey, dsaEncoding: "ieee-p1363" });
  return `${input}.${signature.toString("base64url")}`;
}

/** A signed subscription transaction; override any field. */
export function transaction(fields = {}) {
  const now = Date.now();
  return signJWS({
    transactionId: randomUUID(),
    originalTransactionId: "1000000000000001",
    bundleId: "com.rudilosso.ammutta",
    productId: "com.rudilosso.ammutta.agents.monthly",
    purchaseDate: now - 60_000,
    originalPurchaseDate: now - 60_000,
    expiresDate: now + 30 * 86_400_000,
    quantity: 1,
    type: "Auto-Renewable Subscription",
    inAppOwnershipType: "PURCHASED",
    signedDate: now,
    environment: "Sandbox",
    ...fields,
  });
}

/** A signed App Store Server Notification V2 carrying `signedTransactionInfo`. */
export function notification(notificationType, signedTransactionInfo, subtype) {
  return signJWS({
    notificationType,
    ...(subtype ? { subtype } : {}),
    notificationUUID: randomUUID(),
    version: "2.0",
    signedDate: Date.now(),
    data: { bundleId: "com.rudilosso.ammutta", environment: "Sandbox", signedTransactionInfo },
  });
}
