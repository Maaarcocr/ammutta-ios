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

## Subscription

The connector is a paid add-on that covers the server's cost: one auto-renewable App Store subscription, `com.rudilosso.ammutta.agents.monthly` (about $0.99/month). The rest of the app never needs it.

- **The app** (`AgentStore`, Settings → AI Agents):
  - **Subscribe** opens StoreKit's standard subscription screen, with Restore. Purchases carry `appAccountToken` = the connector account ID.
  - **Redeem Code** opens Apple's offer-code sheet.
  - **Manage Subscription** opens the system sheet.
  - The app sends every signed transaction StoreKit gives it (current entitlement on refresh, plus `Transaction.updates`) to `POST /v1/accounts/:id/subscription`.
  - It sends no data and can't pair agents until the server says the subscription is active.
- **The server never trusts the app's word** (`server/src/subscription.ts`, `billing.ts`):
  - It accepts only JWS signed by Apple, checked with Apple's own `@apple/app-store-server-library` against Apple Root CA G3: signature, chain, bundle ID, environment, and our product ID. The `appAccountToken` may name an older account: turning AI Agents off and on makes a new account, and the subscription moves to it.
  - It stores "paid until" (and refunds) in the account's Durable Object.
  - **One subscription unlocks one account**: the newest account to present it takes it over.
- **App Store Server Notifications V2** at `POST /apple/notifications` keep it current without the app: renewals, expiries, refunds and revocations, matched to the account that holds the subscription now (by original transaction ID), or by `appAccountToken` if no account holds it yet.
- **Without an active subscription:** snapshot uploads and pairing codes return 402, and every agent tool answers that the subscription isn't active.
- **Free months: Apple offer codes.** Create them in App Store Connect (subscription → Offer Codes): a free or discounted period of up to a year, as one-time codes or a custom code. App Review doesn't allow unlocking paid features with our own codes. Testers on TestFlight subscribe in the sandbox for free.
- `APP_APPLE_ID` in `subscription.ts` is the app's Apple ID in App Store Connect (6825521505). Apple requires it to verify production purchases.
- **Testing:** `cf dev --mode test` additionally trusts the test-only chain in `server/test/apple-test-ca`, and `test/apple-signer.mjs` signs fake transactions and notifications with it. Deployed Workers trust Apple only. Verification of Apple's real certificate chain was also checked inside the Workers runtime.

## Server API for the app

| Method and path | Purpose |
| --- | --- |
| `PUT /v1/accounts/:id/snapshot` | Latest data (JSON, ≤ 10 MB; 402 without a subscription) |
| `GET /v1/accounts/:id/inbox` | Plans waiting to be imported |
| `DELETE /v1/accounts/:id/inbox/:item` | Imported or unusable |
| `GET /v1/accounts/:id/subscription` | `{ active, expiresAt }` |
| `POST /v1/accounts/:id/subscription` | `{ transaction: <JWS> }` from StoreKit; returns the status |
| `POST /v1/accounts/:id/pairing` | New pairing code (402 without a subscription) |
| `GET /v1/accounts/:id/pairing/:code` | `waiting`, `connected` (with the agent's name) or `expired`, for the connect sheet |
| `GET /v1/accounts/:id/agents` | Connected agents: name and when |
| `DELETE /v1/accounts/:id/agents` | Disconnect all agents |
| `DELETE /v1/accounts/:id` | Delete everything |

All requests carry `Authorization: Bearer <secret>`.

## Deploying

Live at **https://agents.ammutta.com** (connector: `https://agents.ammutta.com/mcp`). The old `https://ammutta-agents.marcocr.workers.dev` still works for builds that use it, but it sits behind a Cloudflare browser check that blocks agents with script User-Agents (error 1010). The `ammutta.com` zone has that check turned off (Security → Settings → Browser Integrity Check). The Worker is configured in `server/cloudflare.config.ts` for Cloudflare's [`cf` CLI](https://developers.cloudflare.com/cf/), which needs Node 22.18 or newer. The KV namespace `ammutta-agents-oauth` already exists, and its ID is in the config.

**From a computer:**

```sh
cd server
npx cf auth login   # approve in the browser, once
npx cf deploy
```

**From GitHub:** `.github/workflows/server.yml` deploys on every change to `server/` on main once the repository has the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` (`a2047fb96c8e91b553464cd17db67b97`). Create the token in the Cloudflare dashboard with **Workers Scripts: Edit** and **Workers KV Storage: Edit**: `cf`'s own login can't create API tokens. Without the secrets, the job skips with a notice.

The app reads the host from `AMMUTTA_AGENT_SERVER_HOST` in `ios/Config/Ammutta.xcconfig`. While it is empty, the AI Agents setting is hidden.

## Connecting an agent

Settings → Connections → **AI agents** opens the add-on.

- **Not subscribed:** StoreKit's subscription screen with Subscribe, Restore and Redeem code.
- **Subscribed:** the connected agents (by name), **Connect an agent**, when data last synced, the subscription, **Disconnect all agents**, and **Turn off and delete data** (asks first).

**Connect an agent** opens one sheet with two steps:

1. **The connector address** (`https://agents.ammutta.com/mcp`), with Copy and Share, plus where to paste it in Claude.
2. **A fresh pairing code**, made when the sheet opens, shown large, with a countdown and Copy, and **New code** once it expires.

The sheet checks the code's status every two seconds (`GET /pairing/:code`). When the agent signs in, it shows "Claude is connected", and the agent appears in the list. The server records the agent's self-reported name at sign-in (`completePairing` in the account's Durable Object). Disconnecting clears the list.

## Local development

```sh
cd server
npm ci
npm run check && npm test
npx cf dev --mode test --port 8787       # trusts the test App Store chain
node test/e2e.mjs http://127.0.0.1:8787  # subscription, sync, pairing, OAuth, every tool, refunds
```

The end-to-end script needs test mode: it subscribes with fake App Store data that only `--mode test` accepts. CI runs all of it (`Agent connector tests` in `.github/workflows/ci.yml`).

## Not done yet

- The privacy manifest still declares no collected data. Before an App Store release, declare fitness data sent to the connector, update `scripts/verify-ios-bundle.py`, and publish a privacy policy.
- Agent plans appear when the app next opens. There is no push notification.
- Restoring a phone's data from the server is not built.
