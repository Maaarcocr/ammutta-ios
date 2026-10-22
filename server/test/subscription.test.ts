import { generateKeyPairSync } from "node:crypto";
import { describe, expect, it } from "vitest";
import { entitlementFrom, isActive, PRODUCT_ID, verifyTransaction } from "../src/subscription";
// @ts-expect-error plain JavaScript test helper
import { signJWS, transaction } from "./apple-signer.mjs";
import { TEST_ROOT_CA } from "./apple-test-ca/root";

const testEnv = { APPLE_TEST_ROOT_CA: TEST_ROOT_CA };

describe("verifyTransaction", () => {
  it("accepts data signed through the trusted chain", async () => {
    const verified = await verifyTransaction(testEnv, transaction({ originalTransactionId: "42" }));
    expect(verified?.originalTransactionId).toBe("42");
    expect(verified?.productId).toBe(PRODUCT_ID);
  });

  it("refuses the test chain unless it is configured", async () => {
    expect(await verifyTransaction({}, transaction())).toBeNull();
  });

  it("refuses a forged signature and another app's data", async () => {
    const forgedKey = generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey;
    expect(await verifyTransaction(testEnv, signJWS({ productId: PRODUCT_ID }, forgedKey))).toBeNull();
    expect(await verifyTransaction(testEnv, transaction({ bundleId: "com.example.other" }))).toBeNull();
  });
});

describe("entitlements", () => {
  const base = { originalTransactionId: "1", productId: PRODUCT_ID, expiresDate: 2_000 };

  it("comes only from the AI Agents subscription", () => {
    expect(entitlementFrom({ ...base })).toEqual({ originalTransactionId: "1", expiresAt: 2_000, revoked: false });
    expect(entitlementFrom({ ...base, productId: "other" })).toMatch(/not the AI Agents/);
    expect(entitlementFrom({ ...base, expiresDate: undefined })).toMatch(/not a subscription/);
    expect(entitlementFrom({ ...base, revocationDate: 1_500 })).toMatchObject({ revoked: true });
  });

  it("is active until it expires or is refunded", () => {
    const entitlement = { originalTransactionId: "1", expiresAt: 2_000, revoked: false };
    expect(isActive(entitlement, 1_999)).toBe(true);
    expect(isActive(entitlement, 2_000)).toBe(false);
    expect(isActive({ ...entitlement, revoked: true }, 1_000)).toBe(false);
    expect(isActive(undefined, 0)).toBe(false);
  });
});
