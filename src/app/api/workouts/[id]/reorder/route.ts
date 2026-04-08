import { NextRequest, NextResponse } from "next/server";
import {
  getWorkout,
  reorderSections,
  reorderExercises,
  moveExerciseToSection,
  deleteSection as deleteSectionDb,
  deleteExercise as deleteExerciseDb,
  updateExercise,
  updateSection,
} from "@/lib/workouts";

const VALID_SECTION_TYPES = ["warmup", "station", "circuit", "tabata", "amrap", "emom", "cooldown", "choice"];

/**
 * PATCH /api/workouts/[id]/reorder
 *
 * Accepts various operations for reordering and editing a workout plan:
 *
 * { action: "reorderSections", sectionIds: string[] }
 * { action: "reorderExercises", sectionId: string, exerciseIds: string[] }
 * { action: "moveExercise", exerciseId: string, targetSectionId: string, sortOrder: number }
 * { action: "deleteSection", sectionId: string }
 * { action: "deleteExercise", exerciseId: string }
 * { action: "updateExercise", exerciseId: string, exercise_name?: string, notes?: string }
 * { action: "updateSection", sectionId: string, name?: string, section_type?: string, ... }
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const workout = getWorkout(id);
  if (!workout) {
    return NextResponse.json({ error: "Workout not found" }, { status: 404 });
  }

  const body = await request.json();
  const { action } = body;

  if (!action || typeof action !== "string") {
    return NextResponse.json({ error: "Missing action" }, { status: 400 });
  }

  switch (action) {
    case "reorderSections": {
      const { sectionIds } = body;
      if (!Array.isArray(sectionIds) || sectionIds.some((id: unknown) => typeof id !== "string")) {
        return NextResponse.json({ error: "sectionIds must be an array of strings" }, { status: 400 });
      }
      reorderSections(id, sectionIds);
      break;
    }

    case "reorderExercises": {
      const { sectionId, exerciseIds } = body;
      if (typeof sectionId !== "string") {
        return NextResponse.json({ error: "sectionId required" }, { status: 400 });
      }
      if (!Array.isArray(exerciseIds) || exerciseIds.some((id: unknown) => typeof id !== "string")) {
        return NextResponse.json({ error: "exerciseIds must be an array of strings" }, { status: 400 });
      }
      reorderExercises(sectionId, exerciseIds);
      break;
    }

    case "moveExercise": {
      const { exerciseId, targetSectionId, sortOrder } = body;
      if (typeof exerciseId !== "string" || typeof targetSectionId !== "string") {
        return NextResponse.json({ error: "exerciseId and targetSectionId required" }, { status: 400 });
      }
      moveExerciseToSection(exerciseId, targetSectionId, typeof sortOrder === "number" ? sortOrder : 0);
      break;
    }

    case "deleteSection": {
      const { sectionId } = body;
      if (typeof sectionId !== "string") {
        return NextResponse.json({ error: "sectionId required" }, { status: 400 });
      }
      deleteSectionDb(sectionId);
      break;
    }

    case "deleteExercise": {
      const { exerciseId } = body;
      if (typeof exerciseId !== "string") {
        return NextResponse.json({ error: "exerciseId required" }, { status: 400 });
      }
      deleteExerciseDb(exerciseId);
      break;
    }

    case "updateExercise": {
      const { exerciseId, exercise_name, notes } = body;
      if (typeof exerciseId !== "string") {
        return NextResponse.json({ error: "exerciseId required" }, { status: 400 });
      }
      if (exercise_name !== undefined && (typeof exercise_name !== "string" || exercise_name.length > 200)) {
        return NextResponse.json({ error: "Invalid exercise name" }, { status: 400 });
      }
      if (notes !== undefined && notes !== null && (typeof notes !== "string" || notes.length > 500)) {
        return NextResponse.json({ error: "Invalid notes" }, { status: 400 });
      }
      updateExercise(exerciseId, { exercise_name, notes });
      break;
    }

    case "updateSection": {
      const { sectionId, name, section_type, work_seconds, rest_seconds, rounds } = body;
      if (typeof sectionId !== "string") {
        return NextResponse.json({ error: "sectionId required" }, { status: 400 });
      }
      if (section_type !== undefined && !VALID_SECTION_TYPES.includes(section_type)) {
        return NextResponse.json({ error: "Invalid section type" }, { status: 400 });
      }
      if (name !== undefined && (typeof name !== "string" || name.length > 200)) {
        return NextResponse.json({ error: "Invalid section name" }, { status: 400 });
      }
      updateSection(sectionId, { name, section_type, work_seconds, rest_seconds, rounds });
      break;
    }

    default:
      return NextResponse.json({ error: `Unknown action: ${action}` }, { status: 400 });
  }

  // Return the updated workout
  const updated = getWorkout(id);
  return NextResponse.json(updated);
}
