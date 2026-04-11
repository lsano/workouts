import { NextResponse } from "next/server";
import {
  getSensorSession,
  endSensorSession,
  generateExerciseSummaries,
  updateTrendAggregates,
} from "@/lib/sensor-sessions";
import { getDb } from "@/lib/db";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const session = getSensorSession(id);

  if (!session) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }

  return NextResponse.json(session);
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = await request.json();

  const session = getSensorSession(id);
  if (!session) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }

  // End the session
  if (body.action === "end") {
    endSensorSession(id, body.overallConfidence);

    // Generate summaries and update trends
    generateExerciseSummaries(id);
    updateTrendAggregates(id);

    // Mark parent workout as completed
    const db = getDb();
    db.prepare(
      `UPDATE workouts SET status = 'completed', completed_at = datetime('now') WHERE id = ?`
    ).run(session.workoutId);

    const updated = getSensorSession(id);
    return NextResponse.json(updated);
  }

  // Update notes
  if (body.notes !== undefined) {
    const db = getDb();
    db.prepare("UPDATE sensor_sessions SET notes = ?, updated_at = datetime('now') WHERE id = ?").run(
      body.notes,
      id
    );
  }

  const updated = getSensorSession(id);
  return NextResponse.json(updated);
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const session = getSensorSession(id);

  if (!session) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }

  const db = getDb();
  // Cascade delete handles sensor_sessions -> detected_sets -> rep_events
  db.prepare("DELETE FROM workouts WHERE id = ?").run(session.workoutId);

  return NextResponse.json({ deleted: true });
}
