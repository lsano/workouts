import { NextResponse } from "next/server";
import {
  updateDetectedSet,
  deleteDetectedSet,
  getDetectedSets,
} from "@/lib/sensor-sessions";
import type { ExerciseType } from "@/lib/sensor-types";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string; setId: string }> }
) {
  const { setId } = await params;
  const body = await request.json();

  const updates: {
    exerciseType?: ExerciseType;
    repCountCorrected?: number;
    userCorrectedType?: string;
  } = {};

  if (body.exerciseType) {
    updates.exerciseType = body.exerciseType as ExerciseType;
    updates.userCorrectedType = body.exerciseType;
  }
  if (body.repCountCorrected !== undefined) {
    updates.repCountCorrected = body.repCountCorrected;
  }

  updateDetectedSet(setId, updates);
  return NextResponse.json({ updated: true });
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string; setId: string }> }
) {
  const { setId } = await params;
  deleteDetectedSet(setId);
  return NextResponse.json({ deleted: true });
}
