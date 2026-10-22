import { bindings, defineConfig, exports } from "cf/config";

// The AI agents connector (docs/agents.md). Deploy with `npx cf deploy`.
export default defineConfig({
  worker: {
    name: "ammutta-agents",
    compatibilityDate: "2026-10-01",
    // global_fetch_strictly_public: required by the OAuth library for Client ID Metadata Documents.
    compatibilityFlags: ["nodejs_compat", "global_fetch_strictly_public"],
    entrypoint: "src/index.ts",
    observability: {
      enabled: true,
    },
    env: {
      // OAuth clients, grants and tokens (hashed), and pairing codes.
      OAUTH_KV: bindings.kv({ id: "6927e6804d2b442daf000a1750d8a6c4" }),
      // One Durable Object per account: snapshot, inbox and the hashed app secret.
      ACCOUNTS: bindings.durableObject({ worker: "ammutta-agents", exportName: "Account" }),
    },
    exports: {
      Account: exports.durableObject({ storage: "sqlite" }),
    },
  },
});
