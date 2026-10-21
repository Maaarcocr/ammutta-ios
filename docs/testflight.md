# TestFlight from GitHub-hosted macOS

The release pipeline is manual and runs on GitHub's Mac runners, so no Mac is required. It is the same hardened pipeline used by the owner's other iOS project, adapted for a local-only app: there is no API endpoint configuration, and Ammutta-specific bundle rules apply.

Nothing in this repository creates Apple credentials, sets secrets or uploads a build on its own.

## What runs where

| File | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | On every push and PR. Runs the offline pipeline safety tests on Linux. Once `ios/project.yml` exists, also builds an unsigned Release for a device, checks bundle rules and runs unit and UI tests in English and Italian on `macos-26` |
| `.github/workflows/testflight.yml` | **Manual dispatch from `main` only.** `archive` (the default) signs, verifies and then deletes the IPA. `upload` additionally sends it to App Store Connect |
| `scripts/testflight-ci.sh` | Orchestration: temporary keychain, manual signing, archive, export, verification, optional upload and guaranteed cleanup |
| `scripts/testflight-signing.py` | Offline validation of profile, identity and export options, plus cleanup. Never prints secret material |
| `scripts/validate-archive-config.py` | Team ID, bundle ID and build-number checks before any secret is touched |
| `scripts/archive-diagnostics.py` | On an archive failure, prints fixed diagnostic codes (for example `ARCHIVE_PROVISIONING_NOT_SUPPORTED`), never log text |
| `ios/Config/Ammutta.xcconfig` | App-target signing variables. The workflow writes `Signing.local.xcconfig` next to it before archiving and always deletes it, so signing applies to the app target only and never to the Swift package targets |
| `scripts/verify-ios-bundle.py` | Checks the *built* app: no ATS exceptions, no declared data collection or tracking, `en` and `it` localizations present, compiled icon, iPhone-only, export-compliance flag |
| `scripts/check-testflight-tools.sh` | Confirms the pinned Xcode still exposes the CLI options the pipeline needs |
| `scripts/archive-ios.sh` | Optional local Mac route: archive only, then upload manually from Xcode Organizer |
| `scripts/test-ios.sh` | Simulator unit and UI tests, once per shipped language |
| `scripts/test_testflight_ci.py` | Offline tests of all of the above using fake Apple tools and synthetic credentials |

The signing job refuses to start until `ios/project.yml` exists, so nothing is signed before there is an app.

## 1. Apple setup (owner)

Several existing team-level assets can be **reused** from the owner's other app on the same team:

- the Apple Developer Program membership and team ID;
- the **Apple Distribution** certificate and private key (`.p12`). It belongs to the team, not to an app;
- the **App Store Connect team API key** (`.p8`, key ID, issuer ID). Team keys cover all apps in the account within their role.

What Ammutta needs **new**:

1. **An explicit App ID** for the app's bundle identifier, with these capabilities enabled:
   - **HealthKit**;
   - **Time Sensitive Notifications**;
   - **App Groups**, once the widget extension exists.

   No other capabilities are needed. Ammutta has no push, iCloud or Sign in with Apple.
2. **An App Store Connect app record** for that bundle ID: free price tier, primary language English, plus an Italian localization.
3. **An App Store distribution provisioning profile** for that App ID, signed with the distribution certificate above. Create it **after** enabling the capabilities, otherwise the profile's entitlements will not match the app's.
4. **A privacy policy URL.** HealthKit apps require one. It can be a page in this repository or on GitHub Pages; the app only opens it in the system browser.

## 2. Repository configuration

**Settings → Secrets and variables → Actions.** GitHub secrets cannot be copied between repositories, so upload them again from your securely stored files, for example with `gh secret set NAME < file`. Never paste them into issues or chat.

Secrets:

| Name | Value | Needed for |
| --- | --- | --- |
| `APPLE_DISTRIBUTION_P12_BASE64` | Base64 of the distribution `.p12` | archive, upload |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | Its export password | archive, upload |
| `APPLE_APP_STORE_PROFILE_BASE64` | Base64 of **Ammutta's** `.mobileprovision` | archive, upload |
| `ASC_PRIVATE_KEY_BASE64` | Base64 of the team API key `.p8` | upload |
| `ASC_KEY_ID` | API key ID | upload |
| `ASC_ISSUER_ID` | Issuer UUID | upload |

Variables (not secret):

| Name | Value |
| --- | --- |
| `AMMUTTA_TEAM_ID` | Ten-character team ID |
| `AMMUTTA_BUNDLE_ID` | The registered bundle ID. The placeholder `dev.ammutta.*` is rejected |
| `TESTFLIGHT_SIGNING_ENABLED` | `true` once the above is in place |
| `TESTFLIGHT_REQUIRE_ENVIRONMENT_APPROVAL` | Optional. `true` only after creating a `testflight` environment with real required reviewers |

This repository is **public**. Anyone with write access can change workflows and therefore reach repository secrets. Keep write access to trusted people, protect `main`, and note that pull requests from forks never receive secrets. The signing workflow only runs by manual dispatch from `main`.

## 3. Run it

1. Make sure `main` is green in **Verify**.
2. **Actions → Manual TestFlight → Run workflow**, on branch `main`:
   - choose **archive** and a new build number (1–9999) for a first dry run;
   - when that passes, run again with **upload** and a fresh build number.
3. In App Store Connect, wait for processing. Then:
   - answer the export-compliance prompt (the build declares no non-exempt encryption);
   - fill in the App Privacy section as **Data Not Collected**;
   - add the build to an internal TestFlight group.

   External groups need Beta App Review, plus test notes in both languages.

## 4. Known pipeline gap: the widget extension

The pipeline currently signs **one** bundle with **one** profile. The Live Activity and AlarmKit presentation live in a widget extension (see [`architecture.md`](architecture.md#7-live-activity-ammuttaliveactivity--widgets)), which has its own bundle ID and needs its own App Store profile.

Before adding that target, extend the pipeline:

- accept a second profile secret, for example `APPLE_APP_STORE_WIDGETS_PROFILE_BASE64`, and a `AMMUTTA_WIDGETS_BUNDLE_ID` variable;
- validate both profiles in `testflight-signing.py`;
- map both bundle IDs in `provisioningProfiles` in the export options;
- verify the embedded extension's signature and profile as well as the app's;
- extend `test_testflight_ci.py` with a two-bundle fixture.

## Verification boundary

The offline tests prove the orchestration, input validation, redaction and cleanup logic using fakes. They do **not** prove that your certificate, profile or API key work, nor anything about Apple processing or device behavior. Only a successful `archive` run, followed by an `upload` run and TestFlight installs on real iPhones, establishes that.
