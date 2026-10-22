import { bindings, defineConfig, exports } from "cf/config";
import { TEST_ROOT_CA } from "./test/apple-test-ca/root.ts";

// The AI agents connector (docs/agents.md). Deploy with `npx cf deploy`.
// `cf dev --mode test` also trusts a test certificate authority, so the end-to-end test can sign
// fake App Store transactions; deployed Workers trust Apple Root CA G3 only.
export default defineConfig(({ mode }) => ({
  worker: {
    name: "ammutta-agents",
    compatibilityDate: "2026-10-01",
    // global_fetch_strictly_public: required by the OAuth library for Client ID Metadata Documents.
    compatibilityFlags: ["nodejs_compat", "global_fetch_strictly_public"],
    entrypoint: "src/index.ts",
    // Our own domain: workers.dev runs a browser check we can't turn off, which blocked agents
    // using script User-Agents (403 / error 1010). The ammutta.com zone has it off. workers.dev
    // stays on for builds that still use that address.
    // Not in local test mode: the dev server would rewrite requests to http://agents.ammutta.com.
    domains: mode === "test" ? [] : ["agents.ammutta.com"],
    workersDev: true,
    previewUrls: false,
    observability: {
      enabled: true,
    },
    env: {
      // OAuth clients, grants and tokens (hashed), pairing codes, and subscription → account.
      OAUTH_KV: bindings.kv({ id: "6927e6804d2b442daf000a1750d8a6c4" }),
      // One Durable Object per account: snapshot, inbox, subscription and the hashed app secret.
      ACCOUNTS: bindings.durableObject({ worker: "ammutta-agents", exportName: "Account" }),
      APPLE_TEST_ROOT_CA: mode === "test" && bindings.text(TEST_ROOT_CA),
    },
    exports: {
      Account: exports.durableObject({ storage: "sqlite" }),
    },
  },
}));
