# AI agents connector

Lets cloud AI agents (Claude Duet, ChatGPT dots, Meta Muse, or any client that supports remote MCP connectors) read the user's Ammutta data and write plans. It is the app's only networked feature, off by default: **Settings → AI Agents → Connect AI Agents**.

## How it works

```
Ammutta (iPhone) ──HTTPS, account secret──▶ Cloudflare Worker (server/) ◀──MCP + OAuth── AI agent
   sends its data on every change             stores data + inbox               reads, writes plans
   imports the inbox when it opens            per account (Durable Object)
```

- **Data the agent sees**, the "snapshot" (`AgentSnapshot` in the core):
  - plans: built-in keys or custom names, sets in plan-link syntax, rest;
  - finished workouts: every set's status, reps, weight and seconds, duration, and average and max heart rate;
  - the user's own exercises and the built-in catalog.
  Weights are in the user's unit.
- **Agent tools** (`server/src/mcp.ts`):
  - read: `list_workouts` (limit, since), `list_plans` (including plans waiting to be imported), `list_exercises`;
  - write: `create_plan` and `update_plan`.
  Plans are validated with the app's limits (`server/src/plans.ts`) and stored as `ammutta://plan` links ([plan-links.md](plan-links.md)) in the account's inbox.
- **The app imports the inbox** on launch and on returning to the foreground, without a preview: the user connected the agent to do exactly this. An update keeps the plan's identity. A link that doesn't parse is dropped.

## Auth

- **App ↔ server.** On first use the phone makes a random account ID and a 256-bit secret, kept in the Keychain and synced by iCloud Keychain, so a new phone keeps the account. The first request claims the account: the server stores a SHA-256 of the secret, and every later request must present the same secret. There are no accounts, emails or passwords.
- **Agent ↔ server.** Standard MCP authorization (OAuth 2.1 with PKCE, Dynamic Client Registration and Client ID Metadata Documents), via `@cloudflare/workers-oauth-provider`. The agent's sign-in page (`/authorize`) shows who is asking and asks for a **pairing code** from Settings → AI Agents → Get Pairing Code. Codes are 8 characters, single use, and valid for 10 minutes. The code ties the agent's token to that account.
- **Disconnect All Agents** cuts off every agent at once. Each account has a random "agents key", stored in its Durable Object (strongly consistent). Every agent token carries the key it was issued with, and disconnecting replaces the key. The OAuth grants are then revoked as cleanup. Grants live in Workers KV, whose listing can lag by about a minute, so they don't decide access.
- **Turning the setting off** deletes the account on the server (data, inbox, grants) and the secret on the phone.

## Server API for the app

| Method and path | Purpose |
| --- | --- |
| `PUT /v1/accounts/:id/snapshot` | Latest data (JSON, ≤ 10 MB) |
| `GET /v1/accounts/:id/inbox` | Plans waiting to be imported |
| `DELETE /v1/accounts/:id/inbox/:item` | Imported or unusable |
| `POST /v1/accounts/:id/pairing` | New pairing code |
| `DELETE /v1/accounts/:id/agents` | Disconnect all agents |
| `DELETE /v1/accounts/:id` | Delete everything |

All requests carry `Authorization: Bearer <secret>`.

## Deploying

Live at **https://ammutta-agents.marcocr.workers.dev** (connector: `/mcp`). The Worker is configured in `server/cloudflare.config.ts` for Cloudflare's [`cf` CLI](https://developers.cloudflare.com/cf/), which needs Node 22.18 or newer. The KV namespace `ammutta-agents-oauth` already exists, and its ID is in the config.

**From a computer:**

```sh
cd server
npx cf auth login   # approve in the browser, once
npx cf deploy
```

**From GitHub:** `.github/workflows/server.yml` deploys on every change to `server/` on main once the repository has the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` (`a2047fb96c8e91b553464cd17db67b97`). Create the token in the Cloudflare dashboard with **Workers Scripts: Edit** and **Workers KV Storage: Edit**: `cf`'s own login can't create API tokens. Without the secrets, the job skips with a notice.

The app reads the host from `AMMUTTA_AGENT_SERVER_HOST` in `ios/Config/Ammutta.xcconfig`. While it is empty, the AI Agents setting is hidden.

## Connecting an agent

1. In Ammutta: Settings → AI Agents → Connect AI Agents, then Copy Address.
2. In the agent, add a custom connector with that address (it ends in `/mcp`).
3. When the agent opens the sign-in page, tap Get Pairing Code in Ammutta and type the code.

## Local development

```sh
cd server
npm ci
npm run check && npm test
npx cf dev --port 8787                   # http://127.0.0.1:8787
node test/e2e.mjs http://127.0.0.1:8787  # full flow: sync, pairing, OAuth, every tool
node test/e2e.mjs https://ammutta-agents.marcocr.workers.dev  # same, against production
```

The end-to-end script creates a throwaway account and deletes it at the end. CI runs everything except the production run (`Agent connector tests` in `.github/workflows/ci.yml`).

## Not done yet

- The privacy manifest still declares no collected data. Before an App Store release, declare fitness data sent to the connector, update `scripts/verify-ios-bundle.py`, and publish a privacy policy.
- Agent plans appear when the app next opens. There is no push notification.
- Restoring a phone's data from the server is not built.
