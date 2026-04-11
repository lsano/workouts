import { NextResponse } from "next/server";
import { getTrends, getAllExerciseTrends } from "@/lib/sensor-sessions";
import type { ExerciseType, TrendPeriod } from "@/lib/sensor-types";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const exerciseType = searchParams.get("exerciseType") as ExerciseType | null;
  const period = (searchParams.get("period") || "30d") as TrendPeriod;

  if (exerciseType) {
    const trends = getTrends(exerciseType, period);
    return NextResponse.json(trends);
  }

  // Return all exercise trends
  const allTrends = getAllExerciseTrends(period);
  const result: Record<string, unknown[]> = {};
  for (const [type, trends] of allTrends) {
    result[type] = trends;
  }
  return NextResponse.json(result);
}
