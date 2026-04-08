import { NextRequest, NextResponse } from "next/server";
import { updateSet } from "@/lib/workouts";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ setId: string }> }
) {
  const { setId } = await params;
  const body = await request.json();

  // Validate and sanitize inputs - only allow known fields with bounded values
  const sanitized: Record<string, number | boolean | string | null> = {};

  if (body.reps !== undefined) {
    const reps = parseInt(body.reps);
    if (isNaN(reps) || reps < 0 || reps > 9999) {
      return NextResponse.json({ error: "Invalid reps value" }, { status: 400 });
    }
    sanitized.reps = reps;
  }

  if (body.weight_lbs !== undefined) {
    const weight = parseFloat(body.weight_lbs);
    if (isNaN(weight) || weight < 0 || weight > 9999) {
      return NextResponse.json({ error: "Invalid weight value" }, { status: 400 });
    }
    sanitized.weight_lbs = weight;
  }

  if (body.duration_seconds !== undefined) {
    const duration = parseInt(body.duration_seconds);
    if (isNaN(duration) || duration < 0 || duration > 36000) {
      return NextResponse.json({ error: "Invalid duration value" }, { status: 400 });
    }
    sanitized.duration_seconds = duration;
  }

  if (body.completed !== undefined) {
    sanitized.completed = Boolean(body.completed);
  }

  if (body.rpe !== undefined) {
    const rpe = parseInt(body.rpe);
    if (isNaN(rpe) || rpe < 1 || rpe > 10) {
      return NextResponse.json({ error: "RPE must be between 1 and 10" }, { status: 400 });
    }
    sanitized.rpe = rpe;
  }

  if (body.notes !== undefined) {
    // Limit notes length
    sanitized.notes = String(body.notes).slice(0, 500);
  }

  updateSet(setId, sanitized);
  return NextResponse.json({ success: true });
}
