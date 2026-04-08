import Database from "better-sqlite3";
import path from "path";
import fs from "fs";

// Store database in .data/ directory, outside the web-servable root
const DATA_DIR = path.join(process.cwd(), ".data");
const DB_PATH = path.join(DATA_DIR, "workouts.db");

let db: Database.Database | null = null;

export function getDb(): Database.Database {
  if (!db) {
    // Ensure .data directory exists
    if (!fs.existsSync(DATA_DIR)) {
      fs.mkdirSync(DATA_DIR, { recursive: true });
    }
    db = new Database(DB_PATH);
    db.pragma("journal_mode = WAL");
    db.pragma("foreign_keys = ON");
    initializeDb(db);
  }
  return db;
}

function initializeDb(db: Database.Database) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS exercises (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL CHECK(category IN ('kettlebell', 'dumbbell', 'bodyweight', 'band', 'barbell', 'machine', 'cardio', 'other')),
      muscle_groups TEXT NOT NULL, -- JSON array
      description TEXT,
      is_bilateral INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS workouts (
      id TEXT PRIMARY KEY,
      mode TEXT NOT NULL CHECK(mode IN ('gym', 'home')),
      name TEXT,
      date TEXT NOT NULL DEFAULT (date('now')),
      notes TEXT,
      image_url TEXT,
      raw_transcription TEXT,
      structured_plan TEXT, -- JSON of the parsed workout plan
      status TEXT DEFAULT 'planned' CHECK(status IN ('planned', 'in_progress', 'completed')),
      duration_minutes INTEGER,
      created_at TEXT DEFAULT (datetime('now')),
      completed_at TEXT
    );

    CREATE TABLE IF NOT EXISTS workout_sections (
      id TEXT PRIMARY KEY,
      workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      section_type TEXT NOT NULL CHECK(section_type IN ('warmup', 'station', 'circuit', 'tabata', 'amrap', 'emom', 'cooldown', 'choice')),
      work_seconds INTEGER,
      rest_seconds INTEGER,
      rounds INTEGER,
      sort_order INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS workout_exercises (
      id TEXT PRIMARY KEY,
      section_id TEXT NOT NULL REFERENCES workout_sections(id) ON DELETE CASCADE,
      exercise_id TEXT REFERENCES exercises(id),
      exercise_name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      notes TEXT
    );

    CREATE TABLE IF NOT EXISTS exercise_sets (
      id TEXT PRIMARY KEY,
      workout_exercise_id TEXT NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
      set_number INTEGER NOT NULL,
      reps INTEGER,
      weight_lbs REAL,
      duration_seconds INTEGER,
      completed INTEGER DEFAULT 0,
      rpe INTEGER CHECK(rpe BETWEEN 1 AND 10),
      notes TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS hiit_templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      style TEXT NOT NULL CHECK(style IN ('tabata', 'emom', 'amrap', 'circuit', 'ladder', 'pyramid')),
      work_seconds INTEGER NOT NULL,
      rest_seconds INTEGER NOT NULL,
      rounds INTEGER NOT NULL,
      target_muscle_groups TEXT NOT NULL, -- JSON array
      equipment TEXT NOT NULL, -- JSON array
      difficulty TEXT NOT NULL CHECK(difficulty IN ('beginner', 'intermediate', 'advanced')),
      exercises TEXT NOT NULL, -- JSON array of exercise IDs
      source TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts(date);
    CREATE INDEX IF NOT EXISTS idx_workouts_mode ON workouts(mode);
    CREATE INDEX IF NOT EXISTS idx_exercises_category ON exercises(category);
    CREATE INDEX IF NOT EXISTS idx_workout_sections_workout ON workout_sections(workout_id);
    CREATE INDEX IF NOT EXISTS idx_workout_exercises_section ON workout_exercises(section_id);
    CREATE INDEX IF NOT EXISTS idx_exercise_sets_exercise ON exercise_sets(workout_exercise_id);
  `);
}
