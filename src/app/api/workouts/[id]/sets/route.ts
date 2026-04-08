import { NextRequest, NextResponse } from "next/server";
import { addSet } from "@/lib/workouts";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const { workout_exercise_id } = body;

  if (!workout_exercise_id) {
    return NextResponse.json({ error: "workout_exercise_id is required" }, { status: 400 });
  }

  const setId = addSet(workout_exercise_id);
  return NextResponse.json({ id: setId }, { status: 201 });
}
