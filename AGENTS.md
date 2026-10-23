# AGENTS.md

## Project summary

Ammutta for iOS is a free workout tracker for iPhone, local-first (Swift 6, SwiftUI, iOS 26+), built from scratch. It shares a name and product idea with Ammutta for Android, but no code, data format or legacy behavior.

Status: first prototype (0.1): plans and plan links, guided workouts (from a plan or empty, changeable on the fly) with timers and a Live Activity, Bluetooth heart-rate sensors, Apple Health sync, an 81-exercise library, history, settings, en + it. See `docs/architecture.md` §15 for what the prototype simplifies.

## Source-of-truth documents

- `docs/product-spec.md`: what the app does. Read it before any product, UX, copy or flow change, and update it in the same change when behavior changes intentionally.
- `docs/architecture.md`: how the app is built. Keep it current when modules, data model, persistence, services or testing strategy change.
- `docs/testflight.md`: release pipeline and Apple/GitHub setup.
- `docs/plan-links.md`: the `ammutta://plan` link format. Keep it in sync with `PlanLink.swift` and the built-in exercise catalog (new built-ins go in its table and AI prompt).
- `docs/agents.md`: the AI agents connector (`server/`, a Cloudflare Worker): data shared, auth, deploy. Keep it in sync with `server/` and `AgentSnapshot.swift`.
- `AGENTS.md` (this file): how agents work here. Keep it current when commands, layout or conventions change.

There is no design system yet. Use stock SwiftUI components and semantic styles. Do not invent a visual language or carry over the Android "Neon" design.

## Keep it simple

The owner's top rule: plain, standard, boring code. A clever construct needs a reason a reviewer would accept.

- Use controls where Apple puts them. Actions are plain `Button`s. `ShareLink` goes directly in a toolbar or a row, **never inside a `Menu` or `.secondaryAction`** (that crashed the app).
- One presentation per piece of state: one `.sheet(item:)` bound to it, attached to the screen it belongs to. Never two presentation modifiers (sheet, cover) on the same view, never two bound to the same state, and no custom `Binding` getters to dodge presentation conflicts (a sheet next to the workout cover on the root stopped the workout from opening).
- No UIKit wrappers (`UIViewControllerRepresentable`) when a SwiftUI control exists.
- "Are you sure?" confirmations use `.alert` with a destructive button and Cancel. Not `confirmationDialog`: on iOS 26 it is a popover pointing at whatever view it is attached to.
- Prefer plain state (`Set`, `Bool`, optional item) over tricks such as XOR-derived expansion state.
- Fire-and-forget `Task`s that change system state (alerts, Live Activities) run in order through one queue.
- New user-facing actions get a UI test that taps them at least once in CI.

## Non-negotiable rules

- **Local-first.** The only networking is the opt-in AI agents connector (`AgentConnector`, talking to our own `server/` over HTTPS), off by default. Never add accounts with sign-up, analytics, crash reporting, remote config, ads or third-party SDKs to the app, and nothing that sends data without the user turning it on. External links open in the system browser via `openURL`.
- **Free to use.** Everything that runs on the phone is free, and the app is fully usable without paying. The only paid thing is an optional add-on that needs our servers (the AI agents subscription, StoreKit), priced to cover compute. Never lock on-device features behind it. Ads, if ever added, must never degrade the experience (nothing during workouts, nothing that interrupts, no tracking).
- **Localized.** Every user-facing string goes through String Catalogs (`.xcstrings`), in **English and Italian**. This covers:
  - UI text and accessibility labels;
  - notification, AlarmKit and Live Activity text;
  - App Intent phrases;
  - permission purpose strings;
  - error messages.

  Use `FormatStyle` for numbers, dates, durations and measurements, never manual formatting. No string concatenation for sentences; use plural variants.
- **Optional capabilities stay optional.** The app must remain fully usable with Bluetooth, Apple Health, notifications or AlarmKit denied or unavailable.
- **Heart-rate sensors** use only the standard BLE Heart Rate Service (`0x180D` / `0x2A37`). Google Fitbit Air works through that profile. Do not add vendor-specific code paths.
- **Privacy manifest** must declare no tracking and no collected data. `scripts/verify-ios-bundle.py` enforces this on the built bundle. Before an App Store release, declare the fitness data the AI agents connector sends (docs/agents.md).
- No explainer, onboarding or justification copy in the UI unless the user asks for it. Confirmations only for destructive, unrecoverable actions.

## Architecture conventions

- `AmmuttaCore` is pure Swift (Foundation only), with value types that are `Sendable`, `Codable` and `Equatable`. Business rules, validation, the workout engine, codecs and parsers live here.
- The workout engine is a pure reducer that takes `now` explicitly. Side effects (alarms, Live Activity) are derived from state diffs and executed by a coordinator.
- SwiftData `@Model` types are persistence DTOs. Map to domain types at the repository boundary, and keep them out of SwiftUI views and feature models.
- Schema changes add a new `VersionedSchema` and a migration stage, with a migration test. Never use destructive migrations.
- Weights are integer grams; durations are integer seconds; deadlines are absolute `Date`s. Never decrement countdown state.
- Services sit behind protocols with fakes: `TimerAlerting`, `HeartRateSource`, `HealthSyncing` and repositories. Dependencies are injected from the composition root via `Environment`; no singletons.
- Apple Health writes go through the durable outbox (`HealthSyncJob`) and are idempotent via `HKMetadataKeyExternalUUID`.

## Commands

```sh
# Any OS with Python 3
python3 scripts/check-strings.py
python3 -m unittest discover -s scripts -p 'test_testflight_ci.py' -v
bash -n scripts/*.sh

# Any OS with Swift 6.2 (Linux runs the core only; macOS also runs persistence tests)
swift test --package-path ios/Packages/AmmuttaKit

# Any OS with Node 22.18+ (the agent connector; deploy with `npx cf deploy`, see docs/agents.md)
(cd server && npm ci && npm run check && npm test)

# macOS, Xcode 26.6+, xcodegen
(cd ios && xcodegen generate)
./scripts/test-ios.sh
xcodebuild build -project ios/Ammutta.xcodeproj -scheme Ammutta -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath ios/DerivedData-Release CODE_SIGNING_ALLOWED=NO
python3 scripts/verify-ios-bundle.py ios/DerivedData-Release/Build/Products/Release-iphoneos/Ammutta.app
```

## Strings

All UI strings go through `ios/App/Sources/Support/L10n.swift` with semantic keys, and every key needs English and Italian in `ios/App/Resources/Localizable.xcstrings`. Built-in exercise, equipment and muscle names live in `Exercises.xcstrings`. `scripts/check-strings.py` enforces this, including no raw string literals in SwiftUI text APIs.

## Testing expectations

- Add or update tests for any change to:
  - domain rules, the workout engine or its effects;
  - codecs, CSV or archives;
  - heart-rate parsing;
  - Health mapping or the sync queue;
  - persistence mapping or migrations;
  - formatting or localization behavior.
- Formatting tests cover both `en` and `it` locales and both kg and lb.
- UI tests must pass in both languages (`scripts/test-ios.sh` runs both).
- When changing release scripts, keep `scripts/test_testflight_ci.py` passing and extend it. It must never call real Apple tools or use real credentials.

## Git

- Never commit signing material (`*.p12`, `*.p8`, `*.mobileprovision`, `*.key.pem`, `*.certSigningRequest`), the workflow-generated `ios/Config/Signing.local.xcconfig`, generated `ios/Ammutta.xcodeproj`, build products or DerivedData.
- Never pass signing settings to `xcodebuild` on the command line: they would also reach the Swift package targets. App signing goes through `ios/Config/Ammutta.xcconfig`.
- Commit source, String Catalogs, `project.yml`, the privacy manifest, docs and tests.
