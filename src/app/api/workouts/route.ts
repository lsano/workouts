import { NextRequest, NextResponse } from "next/server";
import { createWorkout, listWorkouts } from "@/lib/workouts";

const VALID_MODES = ["gym", "home"];
const VALID_SECTION_TYPES = ["warmup", "station", "circuit", "tabata", "amrap", "emom", "cooldown", "choice"];

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const modeParam = searchParams.get("mode");
  const mode = modeParam && VALID_MODES.includes(modeParam) ? modeParam : undefined;
  const limit = Math.min(Math.max(parseInt(searchParams.get("limit") || "50") || 50, 1), 200);
  const offset = Math.max(parseInt(searchParams.get("offset") || "0") || 0, 0);

  const workouts = listWorkouts({ mode, limit, offset });
  return NextResponse.json(workouts);
}

export async function POST(request: NextRequest) {
  const body = await request.json();

  // Validate mode
  if (!body.mode || !VALID_MODES.includes(body.mode)) {
    return NextResponse.json({ error: "Invalid mode. Must be 'gym' or 'home'." }, { status: 400 });
  }

  // Validate sections if provided
  if (body.sections && Array.isArray(body.sections)) {
    for (const section of body.sections) {
      if (!section.section_type || !VALID_SECTION_TYPES.includes(section.section_type)) {
        return NextResponse.json(
          { error: `Invalid section type: ${section.section_type}` },
          { status: 400 }
        );
      }
    }
  }

  const workoutId = createWorkout(body);
  return NextResponse.json({ id: workoutId }, { status: 201 });
}
