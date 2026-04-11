import { NextResponse } from "next/server";
import { v4 as uuid } from "uuid";
import { getDb } from "@/lib/db";
import {
  createSensorSession,
  getRecentSensorWorkouts,
} from "@/lib/sensor-sessions";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const limit = parseInt(searchParams.get("limit") || "20", 10);

  const sessions = getRecentSensorWorkouts(Math.min(Math.max(limit, 1), 100));
  return NextResponse.json(sessions);
}

export async function POST(request: Request) {
  const body = await request.json();
  const { sensorConfig, notes } = body;

  if (!sensorConfig) {
    return NextResponse.json(
      { error: "sensorConfig is required" },
      { status: 400 }
    );
  }

  // Create the parent workout record
  const db = getDb();
  const workoutId = uuid();
  const now = new Date().toISOString();
  const dateStr = now.split("T")[0];

  db.prepare(
    `INSERT INTO workouts (id, mode, name, date, status, created_at)
     VALUES (?, 'sensor', ?, ?, 'in_progress', ?)`
  ).run(workoutId, "Auto-Detected Workout", dateStr, now);

  // Create the sensor session
  const session = createSensorSession({
    workoutId,
    sensorConfig,
    notes,
  });

  return NextResponse.json(session, { status: 201 });
}
