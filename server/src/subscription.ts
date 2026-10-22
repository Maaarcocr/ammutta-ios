import type {
  JWSTransactionDecodedPayload,
  ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
} from "@apple/app-store-server-library";

// The AI Agents add-on is a monthly App Store subscription. The server never trusts the app's
// word: it accepts only transactions and notifications signed by Apple (verified against Apple
// Root CA G3 with Apple's own library), for this app and this product.

export const BUNDLE_ID = "com.rudilosso.ammutta";
export const PRODUCT_ID = "com.rudilosso.ammutta.agents.monthly";
/** The app's Apple ID in App Store Connect; Apple requires it to verify production data. */
export const APP_APPLE_ID: number | undefined = undefined;

// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
// SHA-256 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
const APPLE_ROOT_CA_G3 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

/** Set only by `cf dev --mode test` (cloudflare.config.ts), for the end-to-end test. */
export interface SubscriptionEnv {
  APPLE_TEST_ROOT_CA?: string;
}

const der = (base64: string) => Buffer.from(base64, "base64");

// Loaded on first use: the library generates random values when it loads, which Workers allow
// only inside a request, not at startup.
async function verifiers(env: SubscriptionEnv): Promise<SignedDataVerifier[]> {
  const { Environment, SignedDataVerifier } = await import("@apple/app-store-server-library");
  // Online revocation checks call Apple's OCSP servers; signatures and dates are still checked.
  const list = [
    new SignedDataVerifier([der(APPLE_ROOT_CA_G3)], false, Environment.SANDBOX, BUNDLE_ID),
  ];
  if (APP_APPLE_ID !== undefined) {
    list.unshift(new SignedDataVerifier([der(APPLE_ROOT_CA_G3)], false, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID));
  }
  if (env.APPLE_TEST_ROOT_CA) {
    list.push(new SignedDataVerifier([der(env.APPLE_TEST_ROOT_CA)], false, Environment.SANDBOX, BUNDLE_ID));
  }
  return list;
}

async function firstVerified<T>(env: SubscriptionEnv, verify: (verifier: SignedDataVerifier) => Promise<T>): Promise<T | null> {
  for (const verifier of await verifiers(env)) {
    try {
      return await verify(verifier);
    } catch {
      // Try the next environment.
    }
  }
  return null;
}

export const verifyTransaction = (env: SubscriptionEnv, jws: string) =>
  firstVerified(env, (verifier) => verifier.verifyAndDecodeTransaction(jws));

export const verifyNotification = (env: SubscriptionEnv, signedPayload: string) =>
  firstVerified(env, (verifier) => verifier.verifyAndDecodeNotification(signedPayload));

/** What the server keeps per account. Times are milliseconds since 1970. */
export interface Entitlement {
  originalTransactionId: string;
  expiresAt: number;
  revoked: boolean;
}

/** The entitlement a verified transaction grants, or why it grants none. */
export function entitlementFrom(transaction: JWSTransactionDecodedPayload): Entitlement | string {
  if (transaction.productId !== PRODUCT_ID) return "not the AI Agents subscription";
  if (!transaction.originalTransactionId || transaction.expiresDate === undefined) return "not a subscription";
  return {
    originalTransactionId: transaction.originalTransactionId,
    expiresAt: transaction.expiresDate,
    revoked: transaction.revocationDate !== undefined,
  };
}

export function isActive(entitlement: Entitlement | undefined, now: number): boolean {
  return entitlement !== undefined && !entitlement.revoked && entitlement.expiresAt > now;
}

/** The signed transaction inside a verified notification, if any. */
export const notificationTransaction = (notification: ResponseBodyV2DecodedPayload) => notification.data?.signedTransactionInfo;
