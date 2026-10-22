import { OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { handleAppRequest } from "./app-api";
import { handleAuthorize } from "./authorize";
import type { Env, Props } from "./env";
import { handleMcp } from "./mcp";

export { Account } from "./account";

// One Worker: the agent connector at /mcp (OAuth-protected), its sign-in page at /authorize,
// and the Ammutta app's API under /v1.

const defaultHandler = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    if (pathname === "/authorize") return handleAuthorize(request, env);
    if (pathname.startsWith("/v1/")) return handleAppRequest(request, env);
    if (pathname === "/") return new Response("Ammutta agent connector. Add /mcp to your AI agent as a custom connector.\n");
    return new Response("Not found\n", { status: 404 });
  },
};

const apiHandler = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // OAuthProvider puts what completeAuthorization() stored into ctx.props.
    return handleMcp(request, env, ctx.props as Props);
  },
};

// The public address is only known once deployed, so providers are built per address as requests arrive.
const providers = new Map<string, OAuthProvider<Env>>();

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const origin = new URL(request.url).origin;
    let provider = providers.get(origin);
    if (!provider) {
      provider = new OAuthProvider<Env>({
        apiRoute: "/mcp",
        apiHandler,
        defaultHandler,
        authorizeEndpoint: "/authorize",
        tokenEndpoint: "/oauth/token",
        clientRegistrationEndpoint: "/oauth/register",
        scopesSupported: ["ammutta"],
        requiredScopes: ["ammutta"],
        resourceMetadata: { resource: `${origin}/mcp`, authorization_servers: [origin] },
        clientIdMetadataDocumentEnabled: true,
      });
      providers.set(origin, provider);
    }
    return provider.fetch(request, env, ctx);
  },
};
