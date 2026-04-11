import { NextResponse } from "next/server";
import {
  getSensorSession,
  addDetectedSet,
  mergeSets,
} from "@/lib/sensor-sessions";
import type { ExerciseType, SetQualityMetrics } from "@/lib/sensor-types";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const session = getSensorSession(id);
  if (!session) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }
  return NextResponse.json(session.sets);
}

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = await request.json();

  const session = getSensorSession(id);
  if (!session) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }

  // Merge sets
  if (body.action === "merge" && Array.isArray(body.setIds)) {
    const mergedId = mergeSets(body.setIds);
    if (!mergedId) {
      return NextResponse.json({ error: "Could not merge sets" }, { status: 400 });
    }
    return NextResponse.json({ mergedSetId: mergedId });
  }

  // Add a new detected set
  const {
    exerciseType,
    detectedType,
    classifierConfidence,
    startTime,
    endTime,
    repCountDetected,
    qualityMetrics,
  } = body;

  if (!exerciseType || !startTime || !endTime) {
    return NextResponse.json(
      { error: "exerciseType, startTime, and endTime are required" },
      { status: 400 }
    );
  }

  const set = addDetectedSet({
    sessionId: id,
    exerciseType: exerciseType as ExerciseType,
    detectedType: detectedType as ExerciseType | undefined,
    classifierConfidence: classifierConfidence ?? 0,
    startTime,
    endTime,
    repCountDetected: repCountDetected ?? 0,
    qualityMetrics: qualityMetrics as SetQualityMetrics | undefined,
    sortOrder: session.sets.length,
  });

  return NextResponse.json(set, { status: 201 });
}
