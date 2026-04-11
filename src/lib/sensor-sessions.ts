import { v4 as uuid } from "uuid";
import { getDb } from "./db";
import type {
  SensorSession,
  DetectedSet,
  RepEvent,
  ExerciseSummary,
  TrendAggregate,
  SensorConfig,
  SetQualityMetrics,
  ExerciseType,
  TrendPeriod,
} from "./sensor-types";

// --- Sensor Session CRUD ---

export function createSensorSession(opts: {
  workoutId: string;
  sensorConfig: SensorConfig;
  notes?: string;
}): SensorSession {
  const db = getDb();
  const id = uuid();
  const now = new Date().toISOString();

  db.prepare(
    `INSERT INTO sensor_sessions (id, workout_id, start_time, sensor_config, notes, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(id, opts.workoutId, now, JSON.stringify(opts.sensorConfig), opts.notes ?? null, now, now);

  return {
    id,
    workoutId: opts.workoutId,
    startTime: now,
    sensorConfig: opts.sensorConfig,
    notes: opts.notes,
    sets: [],
    createdAt: now,
  };
}

export function endSensorSession(sessionId: string, overallConfidence?: number): void {
  const db = getDb();
  const now = new Date().toISOString();
  db.prepare(
    `UPDATE sensor_sessions SET end_time = ?, overall_confidence = ?, updated_at = ? WHERE id = ?`
  ).run(now, overallConfidence ?? null, now, sessionId);
}

export function getSensorSession(sessionId: string): SensorSession | null {
  const db = getDb();
  const row = db.prepare("SELECT * FROM sensor_sessions WHERE id = ?").get(sessionId) as Record<string, unknown> | undefined;
  if (!row) return null;

  const sets = getDetectedSets(sessionId);

  return {
    id: row.id as string,
    workoutId: row.workout_id as string,
    startTime: row.start_time as string,
    endTime: (row.end_time as string) || undefined,
    sensorConfig: JSON.parse(row.sensor_config as string),
    overallConfidence: row.overall_confidence as number | undefined,
    notes: (row.notes as string) || undefined,
    sets,
    createdAt: row.created_at as string,
  };
}

export function getSensorSessionByWorkout(workoutId: string): SensorSession | null {
  const db = getDb();
  const row = db.prepare("SELECT * FROM sensor_sessions WHERE workout_id = ?").get(workoutId) as Record<string, unknown> | undefined;
  if (!row) return null;

  const sets = getDetectedSets(row.id as string);

  return {
    id: row.id as string,
    workoutId: row.workout_id as string,
    startTime: row.start_time as string,
    endTime: (row.end_time as string) || undefined,
    sensorConfig: JSON.parse(row.sensor_config as string),
    overallConfidence: row.overall_confidence as number | undefined,
    notes: (row.notes as string) || undefined,
    sets,
    createdAt: row.created_at as string,
  };
}

// --- Detected Sets ---

export function addDetectedSet(opts: {
  sessionId: string;
  exerciseType: ExerciseType;
  detectedType?: ExerciseType;
  classifierConfidence: number;
  startTime: string;
  endTime: string;
  repCountDetected: number;
  qualityMetrics?: SetQualityMetrics;
  sortOrder: number;
}): DetectedSet {
  const db = getDb();
  const id = uuid();
  const duration = (new Date(opts.endTime).getTime() - new Date(opts.startTime).getTime()) / 1000;

  db.prepare(
    `INSERT INTO detected_sets (id, session_id, exercise_type, detected_type, classifier_confidence,
     start_time, end_time, duration_seconds, rep_count_detected, quality_metrics, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    id, opts.sessionId, opts.exerciseType, opts.detectedType ?? null,
    opts.classifierConfidence, opts.startTime, opts.endTime, duration,
    opts.repCountDetected, opts.qualityMetrics ? JSON.stringify(opts.qualityMetrics) : null,
    opts.sortOrder
  );

  return {
    id,
    sessionId: opts.sessionId,
    exerciseType: opts.exerciseType,
    detectedType: opts.detectedType,
    classifierConfidence: opts.classifierConfidence,
    startTime: opts.startTime,
    endTime: opts.endTime,
    durationSeconds: duration,
    repCountDetected: opts.repCountDetected,
    wasUserCorrected: false,
    sourceMode: "wearables_only",
    qualityMetrics: opts.qualityMetrics,
    sortOrder: opts.sortOrder,
  };
}

export function getDetectedSets(sessionId: string): DetectedSet[] {
  const db = getDb();
  const rows = db.prepare(
    "SELECT * FROM detected_sets WHERE session_id = ? ORDER BY sort_order"
  ).all(sessionId) as Array<Record<string, unknown>>;

  return rows.map((r) => ({
    id: r.id as string,
    sessionId: r.session_id as string,
    exerciseType: r.exercise_type as ExerciseType,
    detectedType: (r.detected_type as ExerciseType) || undefined,
    classifierConfidence: r.classifier_confidence as number,
    startTime: r.start_time as string,
    endTime: r.end_time as string,
    durationSeconds: r.duration_seconds as number,
    repCountDetected: r.rep_count_detected as number,
    repCountCorrected: (r.rep_count_corrected as number) ?? undefined,
    wasUserCorrected: r.was_user_corrected === 1,
    userCorrectedType: (r.user_corrected_type as string) || undefined,
    sourceMode: (r.source_mode as "wearables_only" | "wearables_plus_camera"),
    qualityMetrics: r.quality_metrics ? JSON.parse(r.quality_metrics as string) : undefined,
    sortOrder: r.sort_order as number,
    reps: getRepEvents(r.id as string),
  }));
}

export function updateDetectedSet(
  setId: string,
  updates: {
    exerciseType?: ExerciseType;
    repCountCorrected?: number;
    userCorrectedType?: string;
  }
): void {
  const db = getDb();
  const parts: string[] = [];
  const values: unknown[] = [];

  if (updates.exerciseType !== undefined) {
    parts.push("exercise_type = ?");
    values.push(updates.exerciseType);
  }
  if (updates.repCountCorrected !== undefined) {
    parts.push("rep_count_corrected = ?");
    values.push(updates.repCountCorrected);
  }
  if (updates.userCorrectedType !== undefined) {
    parts.push("user_corrected_type = ?");
    values.push(updates.userCorrectedType);
  }

  if (parts.length > 0) {
    parts.push("was_user_corrected = 1");
    values.push(setId);
    db.prepare(`UPDATE detected_sets SET ${parts.join(", ")} WHERE id = ?`).run(...values);
  }
}

export function deleteDetectedSet(setId: string): void {
  const db = getDb();
  db.prepare("DELETE FROM detected_sets WHERE id = ?").run(setId);
}

export function mergeSets(setIds: string[]): string | null {
  if (setIds.length < 2) return null;
  const db = getDb();
  const sets = setIds.map((id) =>
    db.prepare("SELECT * FROM detected_sets WHERE id = ?").get(id) as Record<string, unknown>
  ).filter(Boolean);

  if (sets.length < 2) return null;

  const sorted = sets.sort((a, b) =>
    new Date(a.start_time as string).getTime() - new Date(b.start_time as string).getTime()
  );

  const mergedId = uuid();
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  const totalReps = sorted.reduce((sum, s) => sum + ((s.rep_count_corrected ?? s.rep_count_detected) as number), 0);
  const startTime = first.start_time as string;
  const endTime = last.end_time as string;
  const duration = (new Date(endTime).getTime() - new Date(startTime).getTime()) / 1000;

  db.prepare(
    `INSERT INTO detected_sets (id, session_id, exercise_type, detected_type, classifier_confidence,
     start_time, end_time, duration_seconds, rep_count_detected, rep_count_corrected, was_user_corrected, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)`
  ).run(
    mergedId, first.session_id, first.exercise_type, first.detected_type,
    first.classifier_confidence, startTime, endTime, duration,
    totalReps, totalReps, first.sort_order
  );

  // Re-parent rep events
  for (const s of sorted) {
    db.prepare("UPDATE rep_events SET set_id = ? WHERE set_id = ?").run(mergedId, s.id);
  }

  // Delete old sets
  for (const id of setIds) {
    db.prepare("DELETE FROM detected_sets WHERE id = ?").run(id);
  }

  return mergedId;
}

// --- Rep Events ---

export function addRepEvent(opts: {
  setId: string;
  repIndex: number;
  timestamp: string;
  durationMs?: number;
  repConfidence?: number;
  leftRightPattern?: "left" | "right" | "both";
  tempoMs?: number;
  qualityScore?: number;
  symmetryScore?: number;
  depthScore?: number;
  stabilityScore?: number;
}): RepEvent {
  const db = getDb();
  const id = uuid();

  db.prepare(
    `INSERT INTO rep_events (id, set_id, rep_index, timestamp, duration_ms, rep_confidence,
     left_right_pattern, tempo_ms, quality_score, symmetry_score, depth_score, stability_score)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    id, opts.setId, opts.repIndex, opts.timestamp,
    opts.durationMs ?? null, opts.repConfidence ?? 1.0,
    opts.leftRightPattern ?? null, opts.tempoMs ?? null,
    opts.qualityScore ?? null, opts.symmetryScore ?? null,
    opts.depthScore ?? null, opts.stabilityScore ?? null
  );

  return {
    id,
    setId: opts.setId,
    repIndex: opts.repIndex,
    timestamp: opts.timestamp,
    durationMs: opts.durationMs,
    repConfidence: opts.repConfidence ?? 1.0,
    leftRightPattern: opts.leftRightPattern,
    tempoMs: opts.tempoMs,
    qualityScore: opts.qualityScore,
    symmetryScore: opts.symmetryScore,
    depthScore: opts.depthScore,
    stabilityScore: opts.stabilityScore,
  };
}

export function getRepEvents(setId: string): RepEvent[] {
  const db = getDb();
  const rows = db.prepare(
    "SELECT * FROM rep_events WHERE set_id = ? ORDER BY rep_index"
  ).all(setId) as Array<Record<string, unknown>>;

  return rows.map((r) => ({
    id: r.id as string,
    setId: r.set_id as string,
    repIndex: r.rep_index as number,
    timestamp: r.timestamp as string,
    durationMs: r.duration_ms as number | undefined,
    repConfidence: r.rep_confidence as number,
    leftRightPattern: (r.left_right_pattern as "left" | "right" | "both") || undefined,
    tempoMs: r.tempo_ms as number | undefined,
    qualityScore: r.quality_score as number | undefined,
    symmetryScore: r.symmetry_score as number | undefined,
    depthScore: r.depth_score as number | undefined,
    stabilityScore: r.stability_score as number | undefined,
  }));
}

// --- Exercise Summaries ---

export function generateExerciseSummaries(sessionId: string): ExerciseSummary[] {
  const db = getDb();
  const sets = getDetectedSets(sessionId);

  const byType = new Map<ExerciseType, DetectedSet[]>();
  for (const s of sets) {
    const type = s.exerciseType;
    if (!byType.has(type)) byType.set(type, []);
    byType.get(type)!.push(s);
  }

  const summaries: ExerciseSummary[] = [];
  for (const [exerciseType, typeSets] of byType) {
    const id = uuid();
    const totalSets = typeSets.length;
    const totalReps = typeSets.reduce((s, t) => s + (t.repCountCorrected ?? t.repCountDetected), 0);
    const qualities = typeSets.filter((s) => s.qualityMetrics).map((s) => s.qualityMetrics!);
    const avgTempo = qualities.length > 0
      ? qualities.reduce((s, q) => s + q.avgTempo, 0) / qualities.length
      : undefined;
    const avgSymmetry = qualities.length > 0
      ? qualities.reduce((s, q) => s + q.symmetryScore, 0) / qualities.length
      : undefined;
    const avgQuality = qualities.length > 0
      ? qualities.reduce((s, q) => s + q.overallQuality, 0) / qualities.length
      : undefined;

    db.prepare(
      `INSERT OR REPLACE INTO exercise_summaries (id, session_id, exercise_type, total_sets, total_reps,
       avg_tempo, avg_symmetry, avg_quality)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(id, sessionId, exerciseType, totalSets, totalReps, avgTempo ?? null, avgSymmetry ?? null, avgQuality ?? null);

    summaries.push({
      id,
      sessionId,
      exerciseType,
      totalSets,
      totalReps,
      avgTempo,
      avgSymmetry,
      avgQuality,
    });
  }

  return summaries;
}

// --- Trend Aggregates ---

export function updateTrendAggregates(sessionId: string): void {
  const db = getDb();
  const session = getSensorSession(sessionId);
  if (!session) return;

  const dateBucket = session.startTime.split("T")[0];
  const summaries = db.prepare(
    "SELECT * FROM exercise_summaries WHERE session_id = ?"
  ).all(sessionId) as Array<Record<string, unknown>>;

  for (const summary of summaries) {
    const exerciseType = summary.exercise_type as string;
    const existing = db.prepare(
      "SELECT * FROM trend_aggregates WHERE exercise_type = ? AND date_bucket = ?"
    ).get(exerciseType, dateBucket) as Record<string, unknown> | undefined;

    if (existing) {
      const newSessions = (existing.total_sessions as number) + 1;
      const newSets = (existing.total_sets as number) + (summary.total_sets as number);
      const newReps = (existing.total_reps as number) + (summary.total_reps as number);

      db.prepare(
        `UPDATE trend_aggregates SET total_sessions = ?, total_sets = ?, total_reps = ?,
         avg_reps_per_set = ?, updated_at = datetime('now')
         WHERE id = ?`
      ).run(newSessions, newSets, newReps, newSets > 0 ? newReps / newSets : 0, existing.id);
    } else {
      const id = uuid();
      const totalSets = summary.total_sets as number;
      const totalReps = summary.total_reps as number;

      db.prepare(
        `INSERT INTO trend_aggregates (id, exercise_type, date_bucket, total_sessions, total_sets,
         total_reps, avg_reps_per_set, avg_tempo, avg_symmetry, avg_quality)
         VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?)`
      ).run(
        id, exerciseType, dateBucket, totalSets, totalReps,
        totalSets > 0 ? totalReps / totalSets : 0,
        summary.avg_tempo ?? null, summary.avg_symmetry ?? null, summary.avg_quality ?? null
      );
    }
  }
}

export function getTrends(exerciseType: ExerciseType, period: TrendPeriod): TrendAggregate[] {
  const db = getDb();
  const days = period === "7d" ? 7 : period === "30d" ? 30 : 90;
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString().split("T")[0];

  const rows = db.prepare(
    `SELECT * FROM trend_aggregates
     WHERE exercise_type = ? AND date_bucket >= ?
     ORDER BY date_bucket`
  ).all(exerciseType, cutoffStr) as Array<Record<string, unknown>>;

  return rows.map((r) => ({
    id: r.id as string,
    exerciseType: r.exercise_type as ExerciseType,
    dateBucket: r.date_bucket as string,
    totalSessions: r.total_sessions as number,
    totalSets: r.total_sets as number,
    totalReps: r.total_reps as number,
    avgRepsPerSet: r.avg_reps_per_set as number | undefined,
    avgTempo: r.avg_tempo as number | undefined,
    avgSymmetry: r.avg_symmetry as number | undefined,
    avgQuality: r.avg_quality as number | undefined,
    avgFatigueDropoff: r.avg_fatigue_dropoff as number | undefined,
  }));
}

export function getAllExerciseTrends(period: TrendPeriod): Map<ExerciseType, TrendAggregate[]> {
  const db = getDb();
  const days = period === "7d" ? 7 : period === "30d" ? 30 : 90;
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString().split("T")[0];

  const rows = db.prepare(
    `SELECT * FROM trend_aggregates WHERE date_bucket >= ? ORDER BY exercise_type, date_bucket`
  ).all(cutoffStr) as Array<Record<string, unknown>>;

  const result = new Map<ExerciseType, TrendAggregate[]>();
  for (const r of rows) {
    const type = r.exercise_type as ExerciseType;
    if (!result.has(type)) result.set(type, []);
    result.get(type)!.push({
      id: r.id as string,
      exerciseType: type,
      dateBucket: r.date_bucket as string,
      totalSessions: r.total_sessions as number,
      totalSets: r.total_sets as number,
      totalReps: r.total_reps as number,
      avgRepsPerSet: r.avg_reps_per_set as number | undefined,
      avgTempo: r.avg_tempo as number | undefined,
      avgSymmetry: r.avg_symmetry as number | undefined,
      avgQuality: r.avg_quality as number | undefined,
      avgFatigueDropoff: r.avg_fatigue_dropoff as number | undefined,
    });
  }

  return result;
}

// --- Recent Sensor Workouts ---

export function getRecentSensorWorkouts(limit: number = 20): SensorSession[] {
  const db = getDb();
  const rows = db.prepare(
    `SELECT ss.* FROM sensor_sessions ss
     JOIN workouts w ON ss.workout_id = w.id
     ORDER BY ss.start_time DESC LIMIT ?`
  ).all(limit) as Array<Record<string, unknown>>;

  return rows.map((r) => ({
    id: r.id as string,
    workoutId: r.workout_id as string,
    startTime: r.start_time as string,
    endTime: (r.end_time as string) || undefined,
    sensorConfig: JSON.parse(r.sensor_config as string),
    overallConfidence: r.overall_confidence as number | undefined,
    notes: (r.notes as string) || undefined,
    sets: getDetectedSets(r.id as string),
    createdAt: r.created_at as string,
  }));
}
