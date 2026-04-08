import { NextRequest, NextResponse } from "next/server";
import { createWorkout, listWorkouts } from "@/lib/workouts";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const mode = searchParams.get("mode") || undefined;
  const limit = searchParams.get("limit") ? parseInt(searchParams.get("limit")!) : 50;
  const offset = searchParams.get("offset") ? parseInt(searchParams.get("offset")!) : 0;

  const workouts = listWorkouts({ mode, limit, offset });
  return NextResponse.json(workouts);
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const workoutId = createWorkout(body);
  return NextResponse.json({ id: workoutId }, { status: 201 });
}
