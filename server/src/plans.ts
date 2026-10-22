// Plans written by agents. The server checks them with the same limits as the app and turns
// them into an `ammutta://plan` link (docs/plan-links.md), which the app imports as usual.

export interface PlanExerciseInput {
  /** A built-in key such as "barbell-bench-press", or any exercise name. */
  exercise: string;
  /** Plan-link set syntax: "3x8@60", "8,6,4@80", "3x45s". */
  sets: string;
  rest_seconds?: number;
}

export interface PlanInput {
  name: string;
  unit?: "kg" | "lb";
  exercises: PlanExerciseInput[];
}

/** Built-in exercises and their kinds, from the app's last sync. */
export type Catalog = Map<string, "reps" | "timed">;

const NAME_LENGTH = 80;
const MAX_EXERCISES = 30;
const SETS = { min: 1, max: 20 };
const REPS = { min: 1, max: 999 };
const SECONDS = { min: 5, max: 3600 };
const REST = { min: 0, max: 600 };
const MAX_WEIGHT_KG = 999.75;
const KG_PER_LB = 0.45359237;

type Kind = "reps" | "timed";

/** `45s`, `2m`, `1m30s`; plain numbers are not durations. */
function parseDuration(token: string): number | null {
  const match = /^(?:(\d+)m)?(?:(\d+)s)?$/.exec(token);
  if (!match || (match[1] === undefined && match[2] === undefined)) return null;
  return Number(match[1] ?? 0) * 60 + Number(match[2] ?? 0);
}

/** Returns the kind and number of sets, or an error message. */
export function checkSets(sets: string, unit: "kg" | "lb"): { kind: Kind; count: number } | string {
  let kind: Kind | null = null;
  let count = 0;
  for (const raw of sets.split(",")) {
    let token = raw.trim().toLowerCase();
    let repeat = 1;
    const prefix = /^(\d+)x(.+)$/.exec(token);
    if (prefix) {
      repeat = Number(prefix[1]);
      token = prefix[2];
      if (repeat < SETS.min || repeat > SETS.max) return `"${raw.trim()}": repeat 1–20 times`;
    }
    let tokenKind: Kind;
    const seconds = parseDuration(token);
    if (seconds !== null) {
      if (seconds < SECONDS.min || seconds > SECONDS.max) return `"${raw.trim()}": timed sets are 5 s to 60 min`;
      tokenKind = "timed";
    } else {
      const reps = /^(\d+)(?:@(\d+(?:\.\d+)?))?$/.exec(token);
      if (!reps) return `"${raw.trim()}" is not a set (use 8, 8@60, 3x8@60, 45s or 3x45s)`;
      const count = Number(reps[1]);
      if (count < REPS.min || count > REPS.max) return `"${raw.trim()}": reps are 1–999`;
      if (reps[2] !== undefined) {
        const kg = Number(reps[2]) * (unit === "lb" ? KG_PER_LB : 1);
        if (kg > MAX_WEIGHT_KG) return `"${raw.trim()}": weight is at most 999.75 kg`;
      }
      tokenKind = "reps";
    }
    if (kind !== null && kind !== tokenKind) return "one exercise uses only reps sets or only timed sets";
    kind = tokenKind;
    count += repeat;
  }
  if (kind === null || count < SETS.min || count > SETS.max) return "each exercise has 1–20 sets";
  return { kind, count };
}

/** Checks a plan; returns a list of problems, empty when it is valid. */
export function validatePlan(plan: PlanInput, catalog: Catalog): string[] {
  const problems: string[] = [];
  const name = plan.name.trim();
  if (name.length === 0 || name.length > NAME_LENGTH) problems.push("name: 1–80 characters");
  if (plan.exercises.length === 0 || plan.exercises.length > MAX_EXERCISES) {
    problems.push("exercises: 1–30 per plan");
  }
  plan.exercises.forEach((item, index) => {
    const label = `exercise ${index + 1}`;
    const exercise = item.exercise.trim();
    if (exercise.length === 0 || exercise.length > NAME_LENGTH) problems.push(`${label}: name 1–80 characters`);
    if (exercise.includes(":")) problems.push(`${label}: names cannot contain ":"`);
    const sets = checkSets(item.sets, plan.unit ?? "kg");
    if (typeof sets === "string") {
      problems.push(`${label}: ${sets}`);
    } else {
      const builtIn = catalog.get(exercise.toLowerCase());
      if (builtIn && builtIn !== sets.kind) problems.push(`${label}: ${exercise} takes ${builtIn} sets`);
    }
    const rest = item.rest_seconds;
    if (rest !== undefined && (!Number.isInteger(rest) || rest < REST.min || rest > REST.max)) {
      problems.push(`${label}: rest_seconds is 0–600`);
    }
  });
  return problems;
}

/** The plan as an `ammutta://plan` link. Call only with a valid plan. */
export function planLink(plan: PlanInput): string {
  const query = ["v=1", `name=${encodeURIComponent(plan.name.trim())}`];
  if (plan.unit === "lb") query.push("unit=lb");
  for (const item of plan.exercises) {
    const parts = [item.exercise.trim(), item.sets.replace(/\s+/g, "")];
    if (item.rest_seconds !== undefined) parts.push(String(item.rest_seconds));
    query.push(`e=${encodeURIComponent(parts.join(":"))}`);
  }
  return `ammutta://plan?${query.join("&")}`;
}
