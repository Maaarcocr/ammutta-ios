# Ammutta plan links

An Ammutta plan link carries a whole workout plan inside the link itself. It needs no server, no account and no internet connection: tapping it on an iPhone with Ammutta opens a preview of the plan, and **Add Plan** saves it.

The format is plain text on purpose, so people and AI assistants can write links by hand. Plans are not limited to the built-in library: any exercise name works, and exercises that don't exist yet are created on the phone when the plan is added. This document is the specification (implemented in `ios/Packages/AmmuttaKit/Sources/AmmuttaCore/PlanLink.swift`) and a guide for generating links.

## Quick example

```
ammutta://plan?v=1&name=Push%20Day&e=barbell-bench-press:3x8@60:150&e=dumbbell-shoulder-press:3x10@20:90&e=Face%20Pull:3x15@12.5:60&e=plank:3x45s:60
```

This is a plan called "Push Day" with:

- Bench Press: 3 sets of 8 reps at 60 kg, 150 s rest;
- Dumbbell Shoulder Press: 3 × 10 at 20 kg, 90 s rest;
- Face Pull, a custom exercise: 3 × 15 at 12.5 kg, 60 s rest;
- Plank: 3 × 45 seconds, 60 s rest.

## Format (version 1)

```
ammutta://plan?v=1&name=<plan name>[&unit=kg|lb]&e=<exercise>&e=<exercise>…
```

| Parameter | Required | Meaning |
| --- | --- | --- |
| `v` | yes | Format version. Always `1`. |
| `name` | yes | Plan name, 1–80 characters, percent-encoded (spaces as `%20`). |
| `unit` | no | Unit for every weight in the link: `kg` (default) or `lb`. |
| `e` | yes, 1–30 times | One exercise each, in plan order. The same exercise may appear more than once. |

### Exercise: `e=<exercise>:<sets>[:<rest>]`

Three fields separated by `:`.

**1. `<exercise>`** is either:

- a **built-in key** from the [table below](#built-in-exercises), for example `barbell-bench-press`. This is the most reliable choice;
- or **any exercise name**, including exercises that are not in the library, for example `Face%20Pull` or `Bulgarian%20Split%20Squat`. A name that matches a built-in exercise in English or Italian (ignoring case and accents) uses that exercise. Otherwise it matches the user's own exercise with the same name and type, or a new custom exercise is created; its type (reps or timed) comes from its sets. Names must not contain `:`.

**2. `<sets>`** is a comma-separated list of sets. All sets of one exercise must be the same type.

| Set | Meaning |
| --- | --- |
| `8` | 8 reps, no added weight (bodyweight) |
| `8@60` | 8 reps with 60 kg (or 60 lb with `unit=lb`). Decimals use a dot: `8@62.5` |
| `45s` | timed set of 45 seconds |
| `2m` | timed set of 2 minutes |
| `1m30s` | timed set of 1 minute 30 seconds |
| `3x8@60` | shorthand for three identical sets: `8@60,8@60,8@60` |

Mix them to vary sets, for example a pyramid: `2x5@100,3@110,1@120`.

**3. `<rest>`** (optional) is the rest after each set: seconds (`90`) or a duration (`90s`, `2m`, `1m30s`). Leave it out (`e=plank:3x45s`) to use the rest time from the user's settings.

### Limits

| Item | Allowed |
| --- | --- |
| Link length | 8,000 characters |
| Exercises per plan | 1–30 |
| Sets per exercise | 1–20 |
| Reps | 1–999 |
| Weight | 0–999.75 kg (`@0` means bodyweight) |
| Timed set | 5 seconds – 60 minutes |
| Rest | 0 – 10 minutes |

A link that breaks any rule is rejected as a whole with a message naming the problem (for example "Exercise 2 in this link isn't written correctly"); nothing is partially imported.

### Encoding rules

- Percent-encode spaces as `%20`, and `&` `=` `+` `#` `?` `/` inside names. Leave `:`, `,` and `@` as they are.
- Use straight ASCII characters. Accented letters in names may be written directly or percent-encoded.
- Keys and units are case-insensitive. Ammutta also tolerates unencoded spaces and surrounding whitespace in pasted links, but encoded links are safer to tap.

## Built-in exercises

Use the key; reps exercises take `8`/`8@60` sets, timed exercises take `45s`/`2m` sets.

| Key | English name | Type |
| --- | --- | --- |
| `barbell-bench-press` | Bench Press | reps |
| `barbell-back-squat` | Back Squat | reps |
| `barbell-deadlift` | Deadlift | reps |
| `barbell-overhead-press` | Overhead Press | reps |
| `barbell-row` | Barbell Row | reps |
| `barbell-romanian-deadlift` | Romanian Deadlift | reps |
| `barbell-hip-thrust` | Hip Thrust | reps |
| `dumbbell-bench-press` | Dumbbell Bench Press | reps |
| `dumbbell-shoulder-press` | Dumbbell Shoulder Press | reps |
| `dumbbell-row` | One-Arm Dumbbell Row | reps |
| `dumbbell-curl` | Dumbbell Curl | reps |
| `dumbbell-lateral-raise` | Lateral Raise | reps |
| `dumbbell-lunge` | Dumbbell Lunge | reps |
| `kettlebell-goblet-squat` | Goblet Squat | reps |
| `kettlebell-swing` | Kettlebell Swing | reps |
| `pull-up` | Pull-Up | reps |
| `chin-up` | Chin-Up | reps |
| `push-up` | Push-Up | reps |
| `dip` | Dip | reps |
| `bodyweight-squat` | Bodyweight Squat | reps |
| `lat-pulldown` | Lat Pulldown | reps |
| `seated-cable-row` | Seated Cable Row | reps |
| `triceps-pushdown` | Triceps Pushdown | reps |
| `leg-press` | Leg Press | reps |
| `leg-curl` | Leg Curl | reps |
| `crunch` | Crunch | reps |
| `hanging-leg-raise` | Hanging Leg Raise | reps |
| `plank` | Plank | timed |
| `side-plank` | Side Plank | timed |
| `wall-sit` | Wall Sit | timed |
| `dead-hang` | Dead Hang | timed |
| `jump-rope` | Jump Rope | timed |

## More examples

Bodyweight full body, default rest:

```
ammutta://plan?v=1&name=Full%20Body&e=push-up:3x12&e=bodyweight-squat:3x15&e=pull-up:3x6&e=plank:3x45s
```

Strength in pounds with a top set:

```
ammutta://plan?v=1&unit=lb&name=Squat%20Day&e=barbell-back-squat:3x5@225,1@245:3m&e=barbell-romanian-deadlift:3x8@185:2m&e=leg-curl:3x12@70:90
```

Custom exercises and timed sets:

```
ammutta://plan?v=1&name=Mobility&e=Cat%20Cow:2x10:30&e=Couch%20Stretch:2x1m:30&e=dead-hang:3x30s:60
```

## Using a link

- **Tap it** in Notes, Messages, Mail, Safari or a chat app that makes links tappable. iOS opens Ammutta (it may ask to confirm "Open in Ammutta?").
- **Paste it**: in Ammutta, go to Plans → **⋯** → **Import Plan Link**, paste, then **Preview**.
- **Share one**: open a plan → **⋯** → **Share Link** produces a link in this format.
- **Ask an AI for one**: Plans → **⋯** → **Share AI Prompt** (see below).

Nothing is saved until **Add Plan** is tapped in the preview. Links contain plan structure only, never history or personal data.

## Prompt for AI assistants

**In the app:** Plans → **⋯** → **Share AI Prompt** generates this prompt for you. It lists every built-in key *and the exercises you added yourself*, and uses your weight unit. Send it to an AI app or copy it, then describe the plan you want.

Without the app at hand, paste this into an AI chat, followed by what you want:

> Create an Ammutta workout plan link. Format: `ammutta://plan?v=1&name=<name, spaces as %20>&e=<exercise>:<sets>:<rest>` with one `&e=` per exercise in order. `<exercise>` is a built-in key (barbell-bench-press, barbell-back-squat, barbell-deadlift, barbell-overhead-press, barbell-row, barbell-romanian-deadlift, barbell-hip-thrust, dumbbell-bench-press, dumbbell-shoulder-press, dumbbell-row, dumbbell-curl, dumbbell-lateral-raise, dumbbell-lunge, kettlebell-goblet-squat, kettlebell-swing, pull-up, chin-up, push-up, dip, bodyweight-squat, lat-pulldown, seated-cable-row, triceps-pushdown, leg-press, leg-curl, crunch, hanging-leg-raise; timed: plank, side-plank, wall-sit, dead-hang, jump-rope) or any other exercise name (exercises outside this list are fine and get created on the phone), with spaces as %20 and no colons. `<sets>` is comma-separated: `8` = 8 reps bodyweight, `8@60` = 8 reps at 60 kg, `45s`/`2m`/`1m30s` = timed set, `3x8@60` = three identical sets; one exercise uses only reps or only timed sets. `<rest>` is seconds between sets (0–600) and may be omitted. Add `&unit=lb` for pounds. Limits: 1–30 exercises, 1–20 sets each, reps 1–999, timed sets 5 s–60 min. Reply with the link on its own line, then the same plan as a short list.
