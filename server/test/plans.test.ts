import { describe, expect, it } from "vitest";
import { type Catalog, checkSets, planLink, validatePlan } from "../src/plans";

const catalog: Catalog = new Map([
  ["barbell-bench-press", "reps"],
  ["plank", "timed"],
]);

describe("checkSets", () => {
  it("accepts the plan-link syntax", () => {
    expect(checkSets("3x8@60", "kg")).toEqual({ kind: "reps", count: 3 });
    expect(checkSets("8, 6@70, 4@80", "kg")).toEqual({ kind: "reps", count: 3 });
    expect(checkSets("12", "kg")).toEqual({ kind: "reps", count: 1 });
    expect(checkSets("3x45s", "kg")).toEqual({ kind: "timed", count: 3 });
    expect(checkSets("1m30s,2m", "kg")).toEqual({ kind: "timed", count: 2 });
  });

  it("rejects bad sets with a reason", () => {
    expect(checkSets("8@60,45s", "kg")).toMatch(/only reps/);
    expect(checkSets("0", "kg")).toMatch(/reps are/);
    expect(checkSets("3s", "kg")).toMatch(/5 s/);
    expect(checkSets("21x5", "kg")).toMatch(/repeat/);
    expect(checkSets("15x5,10x5", "kg")).toMatch(/1–20 sets/);
    expect(checkSets("8@1000", "kg")).toMatch(/999.75/);
    expect(checkSets("8@2000", "lb")).toEqual({ kind: "reps", count: 1 });
    expect(checkSets("eight", "kg")).toMatch(/not a set/);
  });
});

describe("validatePlan", () => {
  it("accepts built-ins and custom names", () => {
    const plan = {
      name: "Push",
      exercises: [
        { exercise: "barbell-bench-press", sets: "3x8@60", rest_seconds: 150 },
        { exercise: "Band Pull-Apart", sets: "3x15" },
        { exercise: "plank", sets: "2x45s", rest_seconds: 60 },
      ],
    };
    expect(validatePlan(plan, catalog)).toEqual([]);
  });

  it("reports every problem", () => {
    const plan = {
      name: " ",
      exercises: [
        { exercise: "plank", sets: "3x8" },
        { exercise: "Odd:Name", sets: "8", rest_seconds: 900 },
      ],
    };
    expect(validatePlan(plan, catalog)).toEqual([
      "name: 1–80 characters",
      "exercise 1: plank takes timed sets",
      'exercise 2: names cannot contain ":"',
      "exercise 2: rest_seconds is 0–600",
    ]);
    expect(validatePlan({ name: "Empty", exercises: [] }, catalog)).toEqual(["exercises: 1–30 per plan"]);
  });
});

describe("planLink", () => {
  it("builds the link the app parses", () => {
    // Keep in sync with AgentLinkContractTests.swift, which parses this exact link.
    const link = planLink({
      name: "Push Day",
      unit: "lb",
      exercises: [
        { exercise: "barbell-bench-press", sets: "3x8@135", rest_seconds: 150 },
        { exercise: "Band Pull-Apart", sets: "3 x 15" },
      ],
    });
    expect(link).toBe(
      "ammutta://plan?v=1&name=Push%20Day&unit=lb&e=barbell-bench-press%3A3x8%40135%3A150&e=Band%20Pull-Apart%3A3x15",
    );
  });
});
