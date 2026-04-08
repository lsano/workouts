import { v4 as uuid } from "uuid";
import { getDb } from "./db";

export interface WorkoutSection {
  id: string;
  name: string;
  section_type: string;
  work_seconds?: number;
  rest_seconds?: number;
  rounds?: number;
  sort_order: number;
  exercises: WorkoutExercise[];
}

export interface WorkoutExercise {
  id: string;
  exercise_id?: string;
  exercise_name: string;
  sort_order: number;
  notes?: string;
  sets: ExerciseSet[];
}

export interface ExerciseSet {
  id: string;
  set_number: number;
  reps?: number;
  weight_lbs?: number;
  duration_seconds?: number;
  completed: boolean;
  rpe?: number;
  notes?: string;
}

export interface Workout {
  id: string;
  mode: string;
  name?: string;
  date: string;
  notes?: string;
  image_url?: string;
  raw_transcription?: string;
  structured_plan?: string;
  status: string;
  duration_minutes?: number;
  created_at: string;
  completed_at?: string;
  sections: WorkoutSection[];
}

export function createWorkout(data: {
  mode: string;
  name?: string;
  date?: string;
  notes?: string;
  raw_transcription?: string;
  structured_plan?: unknown;
  sections?: Array<{
    name: string;
    section_type: string;
    work_seconds?: number;
    rest_seconds?: number;
    rounds?: number;
    exercises: Array<{
      exercise_name: string;
      exercise_id?: string;
      notes?: string;
      sets?: Array<{
        reps?: number;
        weight_lbs?: number;
        duration_seconds?: number;
      }>;
    }>;
  }>;
}): string {
  const db = getDb();
  const workoutId = uuid();

  const insertWorkout = db.prepare(
    `INSERT INTO workouts (id, mode, name, date, notes, raw_transcription, structured_plan, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'planned')`
  );

  const insertSection = db.prepare(
    `INSERT INTO workout_sections (id, workout_id, name, section_type, work_seconds, rest_seconds, rounds, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  );

  const insertExercise = db.prepare(
    `INSERT INTO workout_exercises (id, section_id, exercise_id, exercise_name, sort_order, notes)
     VALUES (?, ?, ?, ?, ?, ?)`
  );

  const insertSet = db.prepare(
    `INSERT INTO exercise_sets (id, workout_exercise_id, set_number, reps, weight_lbs, duration_seconds, completed)
     VALUES (?, ?, ?, ?, ?, ?, 0)`
  );

  const tx = db.transaction(() => {
    insertWorkout.run(
      workoutId,
      data.mode,
      data.name || null,
      data.date || new Date().toISOString().split("T")[0],
      data.notes || null,
      data.raw_transcription || null,
      data.structured_plan ? JSON.stringify(data.structured_plan) : null
    );

    if (data.sections) {
      data.sections.forEach((section, si) => {
        const sectionId = uuid();
        insertSection.run(
          sectionId,
          workoutId,
          section.name,
          section.section_type,
          section.work_seconds || null,
          section.rest_seconds || null,
          section.rounds || null,
          si
        );

        section.exercises.forEach((exercise, ei) => {
          const exerciseId = uuid();
          insertExercise.run(
            exerciseId,
            sectionId,
            exercise.exercise_id || null,
            exercise.exercise_name,
            ei,
            exercise.notes || null
          );

          const sets = exercise.sets || [{ reps: undefined, weight_lbs: undefined }];
          sets.forEach((set, setIdx) => {
            insertSet.run(uuid(), exerciseId, setIdx + 1, set.reps || null, set.weight_lbs || null, set.duration_seconds || null);
          });
        });
      });
    }
  });

  tx();
  return workoutId;
}

export function getWorkout(id: string): Workout | null {
  const db = getDb();
  const workout = db.prepare("SELECT * FROM workouts WHERE id = ?").get(id) as Record<string, unknown> | undefined;
  if (!workout) return null;

  const sections = db
    .prepare("SELECT * FROM workout_sections WHERE workout_id = ? ORDER BY sort_order")
    .all(id) as Array<Record<string, unknown>>;

  const result: Workout = {
    id: workout.id as string,
    mode: workout.mode as string,
    name: workout.name as string | undefined,
    date: workout.date as string,
    notes: workout.notes as string | undefined,
    image_url: workout.image_url as string | undefined,
    raw_transcription: workout.raw_transcription as string | undefined,
    structured_plan: workout.structured_plan as string | undefined,
    status: workout.status as string,
    duration_minutes: workout.duration_minutes as number | undefined,
    created_at: workout.created_at as string,
    completed_at: workout.completed_at as string | undefined,
    sections: [],
  };

  for (const section of sections) {
    const exercises = db
      .prepare("SELECT * FROM workout_exercises WHERE section_id = ? ORDER BY sort_order")
      .all(section.id as string) as Array<Record<string, unknown>>;

    const sectionData: WorkoutSection = {
      id: section.id as string,
      name: section.name as string,
      section_type: section.section_type as string,
      work_seconds: section.work_seconds as number | undefined,
      rest_seconds: section.rest_seconds as number | undefined,
      rounds: section.rounds as number | undefined,
      sort_order: section.sort_order as number,
      exercises: [],
    };

    for (const exercise of exercises) {
      const sets = db
        .prepare("SELECT * FROM exercise_sets WHERE workout_exercise_id = ? ORDER BY set_number")
        .all(exercise.id as string) as Array<Record<string, unknown>>;

      sectionData.exercises.push({
        id: exercise.id as string,
        exercise_id: exercise.exercise_id as string | undefined,
        exercise_name: exercise.exercise_name as string,
        sort_order: exercise.sort_order as number,
        notes: exercise.notes as string | undefined,
        sets: sets.map((s) => ({
          id: s.id as string,
          set_number: s.set_number as number,
          reps: s.reps as number | undefined,
          weight_lbs: s.weight_lbs as number | undefined,
          duration_seconds: s.duration_seconds as number | undefined,
          completed: s.completed === 1,
          rpe: s.rpe as number | undefined,
          notes: s.notes as string | undefined,
        })),
      });
    }

    result.sections.push(sectionData);
  }

  return result;
}

export function listWorkouts(filters?: { mode?: string; limit?: number; offset?: number }): Workout[] {
  const db = getDb();
  let sql = "SELECT * FROM workouts WHERE 1=1";
  const params: (string | number)[] = [];

  if (filters?.mode) {
    sql += " AND mode = ?";
    params.push(filters.mode);
  }

  sql += " ORDER BY date DESC, created_at DESC";

  if (filters?.limit) {
    sql += " LIMIT ?";
    params.push(filters.limit);
  }
  if (filters?.offset) {
    sql += " OFFSET ?";
    params.push(filters.offset);
  }

  const rows = db.prepare(sql).all(...params) as Array<Record<string, unknown>>;
  return rows.map((w) => ({
    id: w.id as string,
    mode: w.mode as string,
    name: w.name as string | undefined,
    date: w.date as string,
    notes: w.notes as string | undefined,
    status: w.status as string,
    duration_minutes: w.duration_minutes as number | undefined,
    created_at: w.created_at as string,
    completed_at: w.completed_at as string | undefined,
    sections: [],
  }));
}

export function updateSet(setId: string, data: {
  reps?: number;
  weight_lbs?: number;
  duration_seconds?: number;
  completed?: boolean;
  rpe?: number;
  notes?: string;
}) {
  const db = getDb();
  const fields: string[] = [];
  const params: (string | number | null)[] = [];

  if (data.reps !== undefined) { fields.push("reps = ?"); params.push(data.reps); }
  if (data.weight_lbs !== undefined) { fields.push("weight_lbs = ?"); params.push(data.weight_lbs); }
  if (data.duration_seconds !== undefined) { fields.push("duration_seconds = ?"); params.push(data.duration_seconds); }
  if (data.completed !== undefined) { fields.push("completed = ?"); params.push(data.completed ? 1 : 0); }
  if (data.rpe !== undefined) { fields.push("rpe = ?"); params.push(data.rpe); }
  if (data.notes !== undefined) { fields.push("notes = ?"); params.push(data.notes); }

  if (fields.length === 0) return;
  params.push(setId);
  db.prepare(`UPDATE exercise_sets SET ${fields.join(", ")} WHERE id = ?`).run(...params);
}

export function addSet(workoutExerciseId: string): string {
  const db = getDb();
  const maxSet = db
    .prepare("SELECT MAX(set_number) as max_set FROM exercise_sets WHERE workout_exercise_id = ?")
    .get(workoutExerciseId) as { max_set: number | null };

  const setId = uuid();
  const setNumber = (maxSet?.max_set || 0) + 1;
  db.prepare(
    "INSERT INTO exercise_sets (id, workout_exercise_id, set_number, completed) VALUES (?, ?, ?, 0)"
  ).run(setId, workoutExerciseId, setNumber);

  return setId;
}

export function updateWorkoutStatus(workoutId: string, status: string) {
  const db = getDb();
  if (status === "completed") {
    db.prepare("UPDATE workouts SET status = ?, completed_at = datetime('now') WHERE id = ?").run(status, workoutId);
  } else {
    db.prepare("UPDATE workouts SET status = ? WHERE id = ?").run(status, workoutId);
  }
}

export function deleteWorkout(workoutId: string) {
  const db = getDb();
  db.prepare("DELETE FROM workouts WHERE id = ?").run(workoutId);
}
