import { NextRequest, NextResponse } from "next/server";
import { getWorkout, updateWorkoutStatus, deleteWorkout } from "@/lib/workouts";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const workout = getWorkout(id);
  if (!workout) {
    return NextResponse.json({ error: "Workout not found" }, { status: 404 });
  }
  return NextResponse.json(workout);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = await request.json();

  if (body.status) {
    updateWorkoutStatus(id, body.status);
  }

  const workout = getWorkout(id);
  return NextResponse.json(workout);
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  deleteWorkout(id);
  return NextResponse.json({ success: true });
}
