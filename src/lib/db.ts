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
      mode TEXT NOT NULL CHECK(mode IN ('gym', 'home', 'sensor')),
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

    -- Sensor-based auto-detection tables

    CREATE TABLE IF NOT EXISTS sensor_devices (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL CHECK(type IN ('foot_sensor', 'watch', 'camera')),
      side TEXT CHECK(side IN ('left', 'right', NULL)),
      name TEXT NOT NULL,
      firmware TEXT,
      last_seen_at TEXT
    );

    CREATE TABLE IF NOT EXISTS sensor_sessions (
      id TEXT PRIMARY KEY,
      workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
      start_time TEXT NOT NULL,
      end_time TEXT,
      sensor_config TEXT NOT NULL, -- JSON: which sensors were connected
      overall_confidence REAL,
      notes TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS detected_sets (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sensor_sessions(id) ON DELETE CASCADE,
      exercise_type TEXT NOT NULL,
      detected_type TEXT,
      classifier_confidence REAL DEFAULT 0,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      duration_seconds REAL,
      rep_count_detected INTEGER NOT NULL DEFAULT 0,
      rep_count_corrected INTEGER,
      was_user_corrected INTEGER DEFAULT 0,
      user_corrected_type TEXT,
      source_mode TEXT DEFAULT 'wearables_only' CHECK(source_mode IN ('wearables_only', 'wearables_plus_camera')),
      quality_metrics TEXT, -- JSON: avg_tempo, tempo_consistency, symmetry, depth, etc.
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS rep_events (
      id TEXT PRIMARY KEY,
      set_id TEXT NOT NULL REFERENCES detected_sets(id) ON DELETE CASCADE,
      rep_index INTEGER NOT NULL,
      timestamp TEXT NOT NULL,
      duration_ms INTEGER,
      rep_confidence REAL DEFAULT 1.0,
      left_right_pattern TEXT, -- 'left', 'right', 'both', or NULL
      tempo_ms INTEGER,
      quality_score REAL,
      symmetry_score REAL,
      depth_score REAL,
      stability_score REAL
    );

    CREATE TABLE IF NOT EXISTS sensor_recordings (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sensor_sessions(id) ON DELETE CASCADE,
      source TEXT NOT NULL CHECK(source IN ('left_foot', 'right_foot', 'watch')),
      start_time TEXT NOT NULL,
      sample_rate_hz INTEGER NOT NULL,
      sample_count INTEGER NOT NULL DEFAULT 0,
      data BLOB, -- compressed binary sensor data
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS exercise_summaries (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sensor_sessions(id) ON DELETE CASCADE,
      exercise_type TEXT NOT NULL,
      total_sets INTEGER NOT NULL DEFAULT 0,
      total_reps INTEGER NOT NULL DEFAULT 0,
      avg_tempo REAL,
      avg_symmetry REAL,
      avg_quality REAL,
      avg_depth REAL,
      fatigue_dropoff REAL
    );

    CREATE TABLE IF NOT EXISTS trend_aggregates (
      id TEXT PRIMARY KEY,
      exercise_type TEXT NOT NULL,
      date_bucket TEXT NOT NULL, -- ISO date
      total_sessions INTEGER NOT NULL DEFAULT 0,
      total_sets INTEGER NOT NULL DEFAULT 0,
      total_reps INTEGER NOT NULL DEFAULT 0,
      avg_reps_per_set REAL,
      avg_tempo REAL,
      avg_symmetry REAL,
      avg_quality REAL,
      avg_fatigue_dropoff REAL,
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_sensor_sessions_workout ON sensor_sessions(workout_id);
    CREATE INDEX IF NOT EXISTS idx_detected_sets_session ON detected_sets(session_id);
    CREATE INDEX IF NOT EXISTS idx_rep_events_set ON rep_events(set_id);
    CREATE INDEX IF NOT EXISTS idx_sensor_recordings_session ON sensor_recordings(session_id);
    CREATE INDEX IF NOT EXISTS idx_exercise_summaries_session ON exercise_summaries(session_id);
    CREATE INDEX IF NOT EXISTS idx_trend_aggregates_exercise ON trend_aggregates(exercise_type);
    CREATE INDEX IF NOT EXISTS idx_trend_aggregates_date ON trend_aggregates(date_bucket);
  `);
}
