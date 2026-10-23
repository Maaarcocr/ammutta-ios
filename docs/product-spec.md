# Ammutta for iOS — Product Specification

Status: **specification only**. No app code exists yet. This document is the source of truth for *what* the app does; [`architecture.md`](architecture.md) covers *how* it is built.

Ammutta ("push!" in Sicilian) is a focused strength and conditioning tracker for iPhone. You build workout plans, run them set by set with rest and exercise timers, and review your training history. Nothing else.

## 1. Product principles

These are constraints, not preferences. A feature that conflicts with one of them is out of scope.

### 1.1 Local-first

- All data lives on the user's iPhone, inside the app's own container.
- **There is no sign-up, login, cloud sync, analytics, crash-reporting SDK or remote configuration.** The only networking is the opt-in AI agents connector (§11.1), off by default.
- Data leaves the app only when the user explicitly asks it to:
  - **connecting AI agents**, which sends plans and workout history to Ammutta's own connector server so agents the user connects can read them and write plans;
  - writing completed workouts to **Apple Health**, on device, after opt-in;
  - **sharing a plan** as a link, QR code or file;
  - **exporting** their data to a file they choose where to save.
- Heart rate is read directly from a Bluetooth sensor over the air. Nothing is relayed through any service.
- The App Store privacy label is **"Data Not Collected"**, and the privacy manifest declares no collected data types and no tracking. CI checks the built bundle for this (see `scripts/verify-ios-bundle.py`). Before an App Store release with the AI agents connector, the label and manifest must declare the fitness data it sends (see [agents.md](agents.md)).

### 1.2 Free to use

- Ammutta is free to download, and **everything that runs on the phone is free**: plans, workouts, timers, heart rate, Apple Health, history, exercises and plan links. The app is fully usable without ever paying.
- **Paid add-ons only cover server costs.** A feature that needs Ammutta's servers may be a small subscription through the App Store, priced to pay for the compute (the AI agents connector, §11.1, about $0.99 a month). Nothing on-device is ever locked behind it.
- **Ads, if there are ever any, must never degrade the experience**: nothing during a workout, nothing that blocks or interrupts a screen, no tracking.
- No third-party SDKs of any kind. This keeps the privacy promise auditable and the binary small.

### 1.3 Multilingual by default

- The app ships in **English and Italian** from the first build. More languages must be addable without code changes, by adding translations only.
- No user-facing string is ever hard-coded. See [§10 Localization](#10-localization).

### 1.4 Focused

- The screens are about doing the workout. No feeds, streaks-for-engagement, social features, coaching, onboarding tours or explainer cards.
- Confirmation dialogs are used only for destructive, unrecoverable actions: deleting history, discarding an active workout, or a full data import that replaces existing data.

### 1.5 Works without anything optional

Bluetooth, Apple Health, notifications and alarms each improve the experience, but the app must remain **fully usable** when any of them is denied, unavailable or turned off later.

## 2. Platform targets

| Item | Decision |
| --- | --- |
| Device | iPhone only, portrait-first. No iPad layout, Apple Watch or Mac app in v1 |
| Minimum OS | **iOS 26.0**. Newer-OS capabilities are adopted behind `#available` checks with a working fallback |
| Toolchain | Xcode 26.6+ and the iOS 26 SDK (current App Store upload minimum), Swift 6 language mode |
| Distribution | TestFlight first (internal, then external), then the App Store, free |

iOS 26 as the floor gives us AlarmKit, mature SwiftData and current ActivityKit without compatibility shims. The fallbacks that still matter come from **permission choices**, not OS versions. For example, AlarmKit denied means using time-sensitive notifications instead (see §6.4).

## 3. Core concepts

| Concept | Meaning |
| --- | --- |
| **Exercise** | Something you do: either a **built-in** catalog exercise or a **custom** one the user created. Each has a **tracking kind** |
| **Tracking kind** | **Reps** (repetitions, with optional added weight) or **Duration** (a timed hold or interval) |
| **Plan** | A named, ordered list of plan exercises: a reusable workout template |
| **Plan exercise** | An exercise inside a plan, with a rest time and a list of **set targets** |
| **Set target** | What one set should be: reps and weight, or duration. Every set can differ, which covers pyramids, drop sets and ramping |
| **Workout** | One performance of a plan. It is **active** while in progress, then **completed** |
| **Set log** | What actually happened in a set: reps, weight or duration, plus the exact time it was logged |
| **Heart-rate sample** | A timestamped BPM reading from a connected sensor during a workout |

## 4. Exercise library

### 4.1 Built-in catalog

- The app ships a curated catalog of about 80 common exercises:
  - bodyweight
  - barbell
  - dumbbell
  - kettlebell
  - cable and machine
  - core
  - timed holds and conditioning, such as plank, wall sit, dead hang, jump rope and rowing intervals.
- Each built-in exercise has a **stable key** (for example `barbell-bench-press`), a tracking kind, equipment and a primary muscle group. Its detail screen shows the **muscles worked** and a one-sentence **technique tip**, both localized.
- Exercise search matches the name, the muscles worked and the muscle group (for example "glutes").
- **Names are localized**: the catalog stores keys, and names come from the String Catalog. The same plan therefore reads "Panca piana con bilanciere" on an Italian phone and "Barbell Bench Press" on an English one.
- The catalog is read-only and versioned with the app. Updating the catalog never rewrites user data.
- Users can **hide** built-in exercises they don't use.

### 4.2 Custom exercises

- Create with a name and a tracking kind, optionally with equipment and muscle group. The user's name is stored as typed and never translated.
- Names are unique per tracking kind, case- and diacritic-insensitively, across both custom exercises and the user's visible built-ins in their current language. The app suggests the existing exercise instead of creating a duplicate.
- Rename at any time. History shows the current name.
- **Archive instead of delete** when an exercise appears in any plan or history. Archived exercises disappear from pickers but keep their history. An exercise with no references can be deleted outright.
- The tracking kind cannot change once the exercise has history, because that would corrupt the meaning of past logs.

### 4.3 Browsing

- Search by name, accent-insensitive and in the current language.
- Filter by tracking kind, equipment and muscle group.
- **Exercise detail** shows:
  - the last performance;
  - personal bests: heaviest weight for given reps, most reps, longest duration, and best single-session volume;
  - a chronological list of every session that included the exercise.

## 5. Plans

### 5.1 Creating and editing

- A plan has a name and an ordered list of plan exercises. The same exercise may appear more than once, for example a warm-up block and a working block.
- Add exercises from the library picker, which includes search and creating a new custom exercise inline. Reorder by drag and remove by swipe.
- Each plan exercise has:
  - **Sets**: 1–20 set targets.
  - **Set targets**:
    - For reps exercises: target reps (1–999) and optional weight (0–999.75 kg, or the lb equivalent, in 0.25 steps).
    - For duration exercises: target duration (5 s–60 min).
    - "Apply to all sets" makes uniform sets quick. Editing one set individually makes the targets per set.
  - **Rest**: 0 s–10 min between sets. The default comes from Settings (150 s initially).
- Plans can be **duplicated** and **deleted**. Deleting a plan never deletes history; completed workouts keep their own snapshot of what was planned.
- Editing a plan never changes completed workouts or a workout already in progress.

### 5.2 Plan detail

The plan detail screen shows the exercises with a set and target summary, an estimated duration, and when the plan was last performed. It has two primary actions, **Start workout** and **Share**, plus Edit.

## 6. Running a workout

This is the heart of the app and must be excellent.

### 6.1 Starting

- Start from a plan's detail screen. The plan's exercises and targets are **copied into the workout**, so the workout is independent of later plan edits.
- Only **one active workout** exists at a time. If one is active, starting another offers to **resume** the active one or **discard it and start the new one**. Discard needs confirmation.

### 6.2 The workout screen

- A single scrolling dashboard of all exercises. The current exercise is expanded, and each set shows as a row.
- Each set row shows the target (for example `8 × 60 kg` or `0:45`) and the last time this exercise was performed, when available.
- **Logging a reps set**: one tap logs it at target values. The reps and weight are directly editable inline before or after logging, with fast increment controls.
- **Logging a duration set**: start the countdown. When it reaches zero the set logs at its target duration. The user can stop early, which logs the actual elapsed time, or edit the logged duration.
- **Logged sets stay inline-editable until the workout finishes.** There is no separate edit screen during a workout.
- The user can also:
  - add an extra set to an exercise, copying the previous set's values;
  - skip a set, which is recorded as skipped rather than silently missing;
  - remove an unlogged set.
- An **elapsed workout time** is always visible.

### 6.3 Rest timer

- Logging a set starts the rest timer automatically, using that exercise's rest time. The last set of the final exercise starts no rest.
- Controls: **−15 s**, **+15 s** and **Skip**. The adjustment step is configurable.
- When rest ends the user is alerted (see §6.4) and the next set is highlighted.
- Rest never blocks logging. Logging the next set early simply ends the rest.

### 6.4 Timers that survive the lock screen

Rest timers and duration-set countdowns must alert the user reliably when the phone is locked, in silent mode or in a Focus mode.

- **Primary path: AlarmKit (iOS 26).** Each running countdown is scheduled as an AlarmKit countdown alarm. The system then delivers a prominent alert at the right moment, even if the app was suspended or terminated, and shows the countdown on the Lock Screen, in the Dynamic Island and on StandBy. Alerts use a short, workout-appropriate sound, not a wake-up alarm.
- **Fallback: time-sensitive local notifications.** These are used if the user declines AlarmKit authorization. The app asks for notification permission at that point, and the in-app countdown is unaffected.
- *Built so far:* the local-notification path. Notification permission is requested at the first countdown; each rest and timed-set countdown is scheduled as one notification that is replaced or removed on every change. AlarmKit and time-sensitive delivery (which needs its entitlement) come next.
- **No permission at all:** timers still run correctly in the app. A small, persistent status line on the workout screen explains that alerts are off, with a button that opens Settings. It is shown once per workout, not as a modal.
- **Correctness rules:**
  - Countdowns are stored as **absolute deadlines**, never as decremented counters.
  - The UI derives remaining time from the deadline, so it is correct after backgrounding, app kill or relaunch.
  - Adjusting, skipping or finishing a timer reschedules or cancels its system alarm or notification immediately. Stale alerts must never fire.

### 6.5 Live Activity

- While a workout is active, a **Live Activity** shows on the Lock Screen and Dynamic Island:
  - the current exercise and set;
  - rest or exercise countdown, rendered by the system from the deadline;
  - elapsed workout time;
  - live heart rate when a sensor is connected.
- Interactive buttons (iOS App Intents): **Log set**, **+15 s rest**, **Skip rest**. These work without unlocking the phone.
- The Live Activity ends when the workout finishes or is discarded.
- *Built so far:* the Live Activity with the plan name, current or next exercise and set, the rest or set countdown (or elapsed time when none runs), and the Dynamic Island. Interactive buttons and heart rate come later; buttons need an App Group so the extension can update the workout store.

### 6.6 Finishing

- **Finish** shows a summary:
  - duration;
  - sets completed versus planned;
  - total volume (Σ reps × weight);
  - per-exercise results;
  - heart-rate average and maximum if available.
- The summary also offers a **save to Apple Health** status line when Health is enabled. The workout is saved to history.
- **Discard** deletes the active workout after confirmation.
- An active workout survives app termination, device restart and OS updates. On next launch the app returns straight to it.

## 7. History and progress

- **History list**: completed workouts, newest first, grouped by month. Each shows the plan name, date, duration and a set and volume summary.
- **Workout detail**: every set with its logged values and timestamps, the rest actually taken between sets, and a heart-rate chart when samples exist.
- **Edit after finishing**: logged values, add or remove sets, and start and end times can all be corrected later. Edits propagate to Apple Health (§9).
- **Delete** a workout, with confirmation. This also removes it from Apple Health if Ammutta wrote it there.
- **Progress** is surfaced in the exercise detail (§4.3) and as "last time" hints during workouts. Charts are a candidate for v1.x, not v1.

## 8. Bluetooth heart-rate sensors (including Google Fitbit Air)

### 8.1 Scope

- Ammutta connects to any device implementing the standard Bluetooth Low Energy **Heart Rate Service** (GATT service `0x180D`, Heart Rate Measurement characteristic `0x2A37`). Examples:
  - chest straps from Polar, Garmin or Wahoo;
  - armbands;
  - wrist wearables that broadcast heart rate.
- **Google Fitbit Air is a first-class supported sensor** and needs nothing beyond this standard profile. The user enables **Share heart rate** for the band in the Google Health app, optionally **Always visible**. The band then advertises the standard Heart Rate Service and appears in Ammutta's sensor list like any other strap. There is no Fitbit or Google SDK, account or API involved.
- One sensor is connected at a time.

### 8.2 Experience

- **Pairing UI** (Settings → Heart Rate → Sensor):
  - scans only for devices advertising `0x180D`;
  - lists them by name with signal strength;
  - connects on tap.
  - Bluetooth permission is requested only at this moment, never at launch.
- If the sensor requires an encrypted link, iOS shows its standard pairing prompt. Ammutta does not implement any pairing protocol of its own.
- The connected sensor is **remembered**. When a workout starts, Ammutta reconnects to it automatically if it is nearby, without scanning UI.
- **During a workout**: the live BPM next to the elapsed time, or a crossed-out heart while searching or out of range.
- **Background**: with the `bluetooth-central` background mode, readings keep arriving while the phone is locked or the app is in the background during an active workout. Scanning and connection stop when no workout is active and the pairing screen is closed.
- **Disconnects**: the app reconnects quietly when the sensor is back in range (a pending iOS connection, no polling). No readings are invented for the gap.
- One reading every 5 seconds is stored with the workout and summarized in the summary and history: average, maximum and a chart.

### 8.3 Parsing requirements

- Support both 8-bit and 16-bit heart-rate value formats (flag bit 0).
- Ignore, but tolerate, the sensor-contact, energy-expended and RR-interval fields (flags bits 1–4). RR intervals may be stored later for HRV, but are not used in v1.
- Discard implausible values (0 or above 250 bpm) and readings where the sensor reports contact as "not detected".
- Cover the parser with byte-level unit tests.

## 9. Apple Health

- **Opt-in**: Settings → Apple Health → **Sync to Apple Health**. It is off by default, and the app works fully without it. iOS asks for permission the first time it is turned on.
- **Writes** (no reads):
  - each workout finished while sync is on, as a strength training workout (`traditionalStrengthTraining`) with its start and end times;
  - its heart-rate readings, when a sensor was connected.
- Workouts finished before sync was turned on are not written.
- Every written object carries the Ammutta workout ID as `HKMetadataKeyExternalUUID`, so writes are **idempotent**.
- **Durable sync queue**: each pending write or delete is saved as a job. Jobs are retried on launch, on returning to the app and after each workout, until they succeed. Health being unavailable or denied never blocks finishing a workout or loses the sync intent.
- **Deletes** in Ammutta remove the Health workout and heart-rate samples Ammutta wrote. Ammutta never modifies data written by other apps.
- If Health access is off, pending jobs wait. Settings shows that Ammutta isn't allowed, with a button to open Settings.
- Later: choosing the workout type per plan, and sets as workout segments.

## 10. Localization

- **Languages**: English (development language) and Italian, both complete for every release. A build with a missing translation fails CI: the bundle check requires both `en.lproj` and `it.lproj`, and UI tests run in both languages.
- **Language selection**: follows the system language, with iOS's per-app **Language** setting in the Settings app. Ammutta has no in-app language picker; Settings links to the system page.
- **What is localized**:
  - all UI text, accessibility labels and hints;
  - built-in exercise names, equipment and muscle groups;
  - notification, AlarmKit and Live Activity text;
  - App Intent and Shortcut phrases;
  - permission purpose strings in `InfoPlist.xcstrings`;
  - error messages;
  - the CSV template's header help;
  - App Store and TestFlight metadata.
- **Mechanics**:
  - Xcode **String Catalogs** (`.xcstrings`) with semantic keys;
  - plural variants through the catalog, not string concatenation;
  - Italian gender and plural agreement handled in translations.
- **Formatting** always uses locale-aware `FormatStyle` APIs for:
  - numbers and decimal separators (`62,5 kg` in Italian, `62.5 kg` in English);
  - dates, times and relative dates;
  - durations;
  - measurements.
- **Units**: weight is stored canonically in grams (see architecture). The display unit is a user setting, **kg** or **lb**, defaulting from the locale's measurement system. Italian defaults to kg.
- **Layout**: text must survive Italian strings that are typically 20–30% longer, plus the largest accessibility text sizes, without truncating actions. UI tests run at large Dynamic Type in both languages.
- **Shared data**: plan links and files reference built-in exercises by **key**, so a plan shared from an English phone opens with Italian names on an Italian phone. Custom exercise names travel verbatim.

## 11. Sharing and importing plans

- **Share a plan** as:
  - an `ammutta://plan` **link** in a readable, self-contained text format that people and AI assistants can write by hand. No server is involved. The format is specified in [`plan-links.md`](plan-links.md);
  - a **QR code** of that link, shown full-screen for another phone's camera;
  - a `.ammuttaplan` **file** via the share sheet;
  - a **CSV** export.

  *Built so far:* links (share, tap to open, paste). QR codes, files and CSV are not built yet.
- Shared content contains **plan structure only**: name, exercises (built-in key, or custom name and kind), set targets and rest. **Never history, heart rate, Health data or any personal data.**
- **Import** by:
  - opening a link (scanned with the Camera app or tapped);
  - opening a `.ammuttaplan` or `.csv` file;
  - pasting a link.
- Import shows a **preview** with the plan, the exercises that will be matched, and the custom exercises that will be created (marked "New"). Nothing is saved until the user confirms with **Add Plan**; the plan then appears in Plans and can be edited like any other.
- Exercise matching on import: built-in keys map to the catalog. A name matches a built-in exercise of the same kind by its English or current-language name, then an existing custom exercise by name and kind (case- and diacritic-insensitive); otherwise a custom exercise is created.
- Sets in a link carry no rest when the author leaves it out; the user's default rest is used.
- **Validation**: strict limits on decoded size, set counts and value ranges, with clear localized errors. Malformed input never crashes or partially imports.
- **CSV**: a documented template, available from the import screen to share or save, with one row per set. The parser tolerates `,` and `;` delimiters and both decimal separators, because Italian spreadsheet exports use `;` and `,`.

### 11.1 AI agents

- **A paid add-on** (about $0.99/month, App Store subscription) that covers the connector's server costs. Subscribe, restore, redeem offer codes and manage the subscription from Settings → AI Agents. Without it, nothing is sent and no agent can connect. Everything else in the app works without it.
- **Settings → AI Agents → Connect AI Agents** (off by default) lets cloud agents such as Claude Duet, ChatGPT dots or Meta Muse, or any client with remote MCP connectors, read the user's plans, workout history and exercises, and create or update plans.
- The app sends its data to Ammutta's connector whenever it changes, and imports plans agents wrote whenever it opens, without a preview.
- Settings → Connections → **AI agents**: subscribe there, then **Connect an agent**. A guided sheet gives the connector address (Copy, Share) and a fresh pairing code (works once, for 10 minutes), and confirms by itself when the agent has signed in. The screen lists connected agents by name.
- **Disconnect All Agents** revokes every agent. Turning the setting off deletes everything on the server.
- Details: [agents.md](agents.md).

## 12. Your data

- **Export everything** to a single versioned JSON file, saved through the system share sheet or Files. It contains exercises, plans, history, heart-rate samples and settings.
- **Import a full export** into an empty app, or replace existing data after confirmation. This is the migration path between phones that doesn't depend on any Ammutta service.
- **Delete all data** in Settings, with confirmation. It does not touch Apple Health data unless the user also chooses "Remove Ammutta workouts from Apple Health".

## 13. Settings

- Weight unit (kg / lb)
- Default rest time and rest adjustment step
- Timer alerts: AlarmKit / notification status with a link to system settings, and sound and haptics toggles
- Heart-rate sensor: the paired device, forget it, or pair a new one
- Apple Health: on/off, status, and pending-sync count with a retry action
- Language, which links to the system per-app language setting
- Your data: export, import and delete all
- About: version, privacy policy and source code links, opened in the system browser

## 14. Accessibility

- Full VoiceOver support. Set rows read as a single coherent element ("Set 2 of 4, 8 reps at 60 kilograms, logged"), and timers announce at sensible intervals rather than every second.
- Dynamic Type up to the largest accessibility sizes.
- Sufficient contrast, with Reduce Motion and Reduce Transparency respected.
- All primary workout actions reachable one-handed. Haptics confirm logging and timer completion.

## 15. Permissions summary

Every permission is requested in context, at first use, and the app must handle denial gracefully.

| Permission | Asked when | If denied |
| --- | --- | --- |
| AlarmKit | First countdown in the first workout | Fall back to notifications |
| Notifications | Only if AlarmKit is denied | In-app timers only, with a status line |
| Bluetooth | User opens sensor pairing | No heart rate; everything else works |
| Apple Health (write) | User enables Health | Workouts stay local; sync intent remains queued |

## 16. Explicitly out of scope for v1

Accounts, cloud sync, iCloud/CloudKit, web or desktop clients, social and leaderboards, coaching, AI suggestions, ads and payments, Apple Watch app, iPad layout, reading data from Apple Health, supersets and circuits, distance or cardio tracking, body measurements, charts, and widgets other than the Live Activity.

Several of these (Watch app, supersets, charts) are reasonable v1.x candidates. All must still respect §1.

## 17. Open decisions

1. **Device backups.** By default iOS includes app data in the user's own iCloud or computer device backups. Excluding it (as the Android app does) means history is lost on a phone switch unless the user exported it.
   - *Recommendation:* allow standard device backups, since they are user-controlled and not an Ammutta service, and keep the manual export.
2. **Plan-link compatibility with Ammutta for Android.** Sharing plans between iOS and Android users would need one wire format.
   - *Status:* `plan v1` is defined in [`plan-links.md`](plan-links.md) and implemented on iOS. Android would need to implement the same format.
3. **App icon master.** *Resolved:* `branding/ammutta-logo.svg` is a vector redraw of `ammutta-logo-512.png`; the 1024×1024 opaque app icon is rendered from it.
4. **License** for this public repository. Without one, the code is all rights reserved by default.
