import { McpServer, WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/server";
import * as z from "zod";
import type { InboxItem } from "./account";
import { account, type Env, type Props } from "./env";
import { type Catalog, type PlanInput, planLink, validatePlan } from "./plans";

// The tools agents see. Data comes from the app's last sync; plans agents write wait in the
// account's inbox until the app next opens and imports them.

interface Snapshot {
  generatedAt: string;
  unit: "kg" | "lb";
  plans: { id: string; name: string }[];
  workouts: { startedAt: string }[];
  customExercises: unknown[];
  builtInExercises: { key: string; kind: "reps" | "timed" }[];
}

const INSTRUCTIONS = `Ammutta is the user's strength-training app. Read their plans and workout history, and write plans they will find in the app.
Weights are in the snapshot's "unit". Plan sets use the plan-link syntax: "8" (8 reps, bodyweight), "8@60" (8 reps at 60), "3x8@60" (three identical sets), "8,6,4@80" (different sets), "45s" / "2m" / "1m30s" (timed sets), "3x45s". One exercise uses only reps sets or only timed sets.
Use built-in exercise keys from list_exercises when one fits; any other name creates a custom exercise. Plans you write appear in the app the next time the user opens it.`;

const exerciseSchema = z.object({
  exercise: z.string().describe('A built-in key such as "barbell-bench-press", or any exercise name (no ":")'),
  sets: z.string().describe('Sets in plan-link syntax, for example "3x8@60", "8,6,4@80" or "3x45s"'),
  rest_seconds: z.number().int().min(0).max(600).optional().describe("Rest between sets, 0–600 seconds"),
});

const planSchema = {
  name: z.string().describe("Plan name, 1–80 characters"),
  unit: z.enum(["kg", "lb"]).optional().describe("Unit for the weights in sets; defaults to the user's unit"),
  exercises: z.array(exerciseSchema).min(1).max(30),
};

const text = (value: unknown) => ({
  content: [{ type: "text" as const, text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
});

const NOT_SYNCED = "Ammutta hasn't shared any data yet. Ask the user to open the Ammutta app with AI Agents turned on in Settings.";

export async function handleMcp(request: Request, env: Env, props: Props): Promise<Response> {
  const store = account(env, props.accountId);
  const loadSnapshot = async (): Promise<Snapshot | null> => {
    const json = await store.getSnapshot();
    return json ? (JSON.parse(json) as Snapshot) : null;
  };

  const server = new McpServer({ name: "ammutta", version: "1.0.0" }, { instructions: INSTRUCTIONS });

  server.registerTool(
    "list_workouts",
    {
      description: "The user's finished workouts, newest first: exercises, every set (reps, weight, seconds, done or skipped), duration and heart rate.",
      inputSchema: z.object({
        limit: z.number().int().min(1).max(200).optional().describe("How many workouts, newest first (default 20)"),
        since: z.string().optional().describe("Only workouts started on or after this ISO 8601 date"),
      }),
      annotations: { readOnlyHint: true },
    },
    async ({ limit, since }) => {
      const snapshot = await loadSnapshot();
      if (!snapshot) return text(NOT_SYNCED);
      const from = since ? Date.parse(since) : Number.NaN;
      const workouts = snapshot.workouts
        .filter((workout) => Number.isNaN(from) || Date.parse(workout.startedAt) >= from)
        .slice(0, limit ?? 20);
      return text({ unit: snapshot.unit, syncedAt: snapshot.generatedAt, workouts });
    },
  );

  server.registerTool(
    "list_plans",
    {
      description: "The user's workout plans, plus plans written by agents that the app hasn't imported yet.",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: true },
    },
    async () => {
      const snapshot = await loadSnapshot();
      if (!snapshot) return text(NOT_SYNCED);
      const pending = (await store.listInbox()).map(({ id, planId, name, createdAt }) => ({ id, planId, name, createdAt }));
      return text({ unit: snapshot.unit, syncedAt: snapshot.generatedAt, plans: snapshot.plans, pendingFromAgents: pending });
    },
  );

  server.registerTool(
    "list_exercises",
    {
      description: "Built-in exercise keys (with name, reps or timed, equipment and muscle) and the user's own exercises.",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: true },
    },
    async () => {
      const snapshot = await loadSnapshot();
      if (!snapshot) return text(NOT_SYNCED);
      return text({ builtIn: snapshot.builtInExercises, custom: snapshot.customExercises });
    },
  );

  const savePlan = async (input: PlanInput, planId?: string) => {
    const snapshot = await loadSnapshot();
    if (!snapshot) return text(NOT_SYNCED);
    if (planId && !snapshot.plans.some((plan) => plan.id === planId)) {
      return text(`No plan with id ${planId}. Use list_plans to find it.`);
    }
    const plan = { ...input, unit: input.unit ?? snapshot.unit };
    const catalog: Catalog = new Map(snapshot.builtInExercises.map((exercise) => [exercise.key, exercise.kind]));
    const problems = validatePlan(plan, catalog);
    if (problems.length > 0) return text(`The plan wasn't saved:\n- ${problems.join("\n- ")}`);
    const item: InboxItem = {
      id: crypto.randomUUID(),
      planId,
      name: plan.name.trim(),
      link: planLink(plan),
      createdAt: new Date().toISOString(),
    };
    if (!(await store.addToInbox(item))) {
      return text("Too many plans are waiting. Ask the user to open Ammutta so it can import them.");
    }
    return text(`Saved "${item.name}". It appears in Ammutta's Plans the next time the user opens the app.`);
  };

  server.registerTool(
    "create_plan",
    {
      description: "Add a new workout plan to the user's Ammutta app.",
      inputSchema: z.object(planSchema),
    },
    async (input) => savePlan(input),
  );

  server.registerTool(
    "update_plan",
    {
      description: "Replace an existing plan's name and exercises (get plan_id from list_plans).",
      inputSchema: z.object({ plan_id: z.string(), ...planSchema }),
    },
    async ({ plan_id, ...input }) => savePlan(input, plan_id),
  );

  const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  await server.connect(transport);
  return transport.handleRequest(request);
}
