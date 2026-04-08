import { NextRequest, NextResponse } from "next/server";
import { getExercises } from "@/lib/exercises";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const category = searchParams.get("category") || undefined;
  const muscleGroup = searchParams.get("muscleGroup") || undefined;

  const exercises = getExercises(category, muscleGroup);
  return NextResponse.json(exercises);
}
