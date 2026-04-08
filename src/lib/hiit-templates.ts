import { v4 as uuid } from "uuid";
import { getDb } from "./db";
import { seedExercises } from "./exercises";

export interface HiitTemplate {
  id: string;
  name: string;
  description: string;
  style: string;
  work_seconds: number;
  rest_seconds: number;
  rounds: number;
  target_muscle_groups: string[];
  equipment: string[];
  difficulty: string;
  exercises: string[];
  source: string;
}

// HIIT templates based on established training principles:
// - Tabata: 20s work / 10s rest x 8 rounds (Dr. Izumi Tabata, 1996)
// - EMOM: Every Minute on the Minute - complete reps within 60s, rest remainder
// - AMRAP: As Many Rounds As Possible in a set time
// - Circuit: Station-based with set work/rest intervals
// Sources: NSCA HIIT guidelines, ACE Fitness protocols, Tabata et al. (1996)
const TEMPLATES: Omit<HiitTemplate, "id">[] = [
  // Tabata-style (20/10 x 8) - proven VO2max and anaerobic capacity builder
  {
    name: "Kettlebell Tabata Blaster",
    description: "Classic Tabata protocol with kettlebell movements. 4 minutes of max effort. Based on Tabata et al. (1996) - shown to improve both aerobic and anaerobic capacity.",
    style: "tabata",
    work_seconds: 20,
    rest_seconds: 10,
    rounds: 8,
    target_muscle_groups: ["glutes", "quads", "shoulders", "core"],
    equipment: ["kettlebell"],
    difficulty: "intermediate",
    exercises: ["Kettlebell Swing", "Kettlebell Goblet Squat"],
    source: "Tabata Protocol (Tabata et al., 1996)",
  },
  {
    name: "Bodyweight Tabata Burn",
    description: "No equipment needed. Alternating between upper and lower body movements for balanced intensity.",
    style: "tabata",
    work_seconds: 20,
    rest_seconds: 10,
    rounds: 8,
    target_muscle_groups: ["chest", "quads", "core", "glutes"],
    equipment: ["bodyweight"],
    difficulty: "beginner",
    exercises: ["Push-Up", "Squat Jump", "Mountain Climber", "Bodyweight Squat"],
    source: "ACE Fitness HIIT Guidelines",
  },
  {
    name: "DB Tabata Strength",
    description: "Dumbbell Tabata targeting major muscle groups. Heavy enough to challenge strength, light enough for speed.",
    style: "tabata",
    work_seconds: 20,
    rest_seconds: 10,
    rounds: 8,
    target_muscle_groups: ["shoulders", "quads", "back", "core"],
    equipment: ["dumbbell"],
    difficulty: "intermediate",
    exercises: ["Dumbbell Thruster", "Dumbbell Renegade Row"],
    source: "NSCA HIIT Protocols",
  },

  // EMOM workouts - great for pacing and building work capacity
  {
    name: "KB EMOM Strength Builder",
    description: "10-minute EMOM alternating kettlebell movements. Complete prescribed reps, rest the remainder of each minute. Builds strength-endurance.",
    style: "emom",
    work_seconds: 60,
    rest_seconds: 0,
    rounds: 10,
    target_muscle_groups: ["glutes", "shoulders", "core", "back"],
    equipment: ["kettlebell"],
    difficulty: "intermediate",
    exercises: ["Kettlebell Clean", "Kettlebell Press", "Kettlebell Swing"],
    source: "StrongFirst Kettlebell Principles",
  },
  {
    name: "Mixed EMOM Power",
    description: "12-minute EMOM cycling through 3 movements. Focus on explosive power with adequate recovery.",
    style: "emom",
    work_seconds: 60,
    rest_seconds: 0,
    rounds: 12,
    target_muscle_groups: ["quads", "glutes", "shoulders", "core"],
    equipment: ["kettlebell", "bodyweight"],
    difficulty: "advanced",
    exercises: ["Kettlebell Snatch", "Burpee", "Kettlebell Goblet Squat"],
    source: "NSCA Periodization Principles",
  },

  // Circuit training - balanced work/rest for sustained effort
  {
    name: "Full Body KB Circuit",
    description: "5 exercises, 40s work / 20s rest, 3 rounds. Targets all major muscle groups with kettlebell movements. 2:1 work-to-rest ratio for metabolic conditioning.",
    style: "circuit",
    work_seconds: 40,
    rest_seconds: 20,
    rounds: 3,
    target_muscle_groups: ["quads", "glutes", "shoulders", "back", "core"],
    equipment: ["kettlebell"],
    difficulty: "intermediate",
    exercises: ["Kettlebell Swing", "Kettlebell Goblet Squat", "Kettlebell Row", "Kettlebell Press", "Kettlebell Halo"],
    source: "ACE Fitness Circuit Training Guidelines",
  },
  {
    name: "DB Metabolic Circuit",
    description: "Dumbbell-only circuit for maximum metabolic effect. 30s work / 15s rest, 4 rounds. Short rest keeps heart rate elevated.",
    style: "circuit",
    work_seconds: 30,
    rest_seconds: 15,
    rounds: 4,
    target_muscle_groups: ["chest", "quads", "back", "shoulders", "core"],
    equipment: ["dumbbell"],
    difficulty: "intermediate",
    exercises: ["Dumbbell Devil Press", "Dumbbell Goblet Squat", "Dumbbell Row", "Dumbbell Shoulder Press", "Dumbbell Romanian Deadlift"],
    source: "ACSM Metabolic Conditioning Protocols",
  },
  {
    name: "Bodyweight Blast Circuit",
    description: "No equipment, anywhere workout. 35s work / 25s rest, 3 rounds. Perfect for travel or home with no equipment.",
    style: "circuit",
    work_seconds: 35,
    rest_seconds: 25,
    rounds: 3,
    target_muscle_groups: ["chest", "quads", "core", "glutes", "shoulders"],
    equipment: ["bodyweight"],
    difficulty: "beginner",
    exercises: ["Push-Up", "Bodyweight Squat", "Mountain Climber", "Walking Lunge", "Plank"],
    source: "ACE Fitness Bodyweight Training",
  },
  {
    name: "KB + BW Hybrid Crusher",
    description: "Alternates kettlebell and bodyweight moves for sustained intensity. 30s work / 15s rest, 4 rounds.",
    style: "circuit",
    work_seconds: 30,
    rest_seconds: 15,
    rounds: 4,
    target_muscle_groups: ["glutes", "core", "shoulders", "quads", "chest"],
    equipment: ["kettlebell", "bodyweight"],
    difficulty: "advanced",
    exercises: ["Kettlebell Thruster", "Burpee", "Kettlebell Swing", "Mountain Climber", "Kettlebell Snatch", "Push-Up"],
    source: "NSCA HIIT Research Guidelines",
  },

  // AMRAP - test your work capacity
  {
    name: "15-Min KB AMRAP",
    description: "As many rounds as possible in 15 minutes. Track your rounds to measure progress over time.",
    style: "amrap",
    work_seconds: 900,
    rest_seconds: 0,
    rounds: 1,
    target_muscle_groups: ["glutes", "shoulders", "core", "quads"],
    equipment: ["kettlebell"],
    difficulty: "intermediate",
    exercises: ["Kettlebell Swing", "Kettlebell Goblet Squat", "Kettlebell Press", "Kettlebell Row"],
    source: "CrossFit-style AMRAP Methodology",
  },
  {
    name: "DB + BW 12-Min AMRAP",
    description: "Mixed equipment AMRAP. Complete the circuit as many times as possible in 12 minutes.",
    style: "amrap",
    work_seconds: 720,
    rest_seconds: 0,
    rounds: 1,
    target_muscle_groups: ["chest", "quads", "back", "core"],
    equipment: ["dumbbell", "bodyweight"],
    difficulty: "intermediate",
    exercises: ["Dumbbell Thruster", "Push-Up", "Dumbbell Row", "Squat Jump", "V-Up"],
    source: "ACSM HIIT Programming",
  },

  // Ladder workouts - progressive challenge
  {
    name: "KB Ascending Ladder",
    description: "Start with 2 reps, add 2 each round up to 10, then back down. Great for building volume with good form.",
    style: "ladder",
    work_seconds: 45,
    rest_seconds: 15,
    rounds: 9,
    target_muscle_groups: ["glutes", "shoulders", "core"],
    equipment: ["kettlebell"],
    difficulty: "intermediate",
    exercises: ["Kettlebell Clean", "Kettlebell Press", "Kettlebell Swing"],
    source: "Pavel Tsatsouline Ladder Protocol",
  },

  // Glute-focused (like the Booty Tabata from the whiteboard)
  {
    name: "Glute Tabata",
    description: "Targeted glute Tabata. 20s work / 10s rest x 4 per exercise. Pair with band for extra activation.",
    style: "tabata",
    work_seconds: 20,
    rest_seconds: 10,
    rounds: 8,
    target_muscle_groups: ["glutes", "hamstrings"],
    equipment: ["band", "bodyweight"],
    difficulty: "beginner",
    exercises: ["Band Glute Bridge", "Donkey Kick", "Fire Hydrant", "Band Walks"],
    source: "Bret Contreras Glute Training Principles",
  },
];

export function seedTemplates() {
  const db = getDb();
  seedExercises();
  const count = db.prepare("SELECT COUNT(*) as count FROM hiit_templates").get() as { count: number };
  if (count.count > 0) return;

  const insert = db.prepare(
    `INSERT INTO hiit_templates (id, name, description, style, work_seconds, rest_seconds, rounds,
     target_muscle_groups, equipment, difficulty, exercises, source)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );

  const tx = db.transaction(() => {
    for (const t of TEMPLATES) {
      insert.run(
        uuid(), t.name, t.description, t.style, t.work_seconds, t.rest_seconds, t.rounds,
        JSON.stringify(t.target_muscle_groups), JSON.stringify(t.equipment), t.difficulty,
        JSON.stringify(t.exercises), t.source
      );
    }
  });
  tx();
}

export function getTemplates(filters?: {
  style?: string;
  equipment?: string;
  difficulty?: string;
  muscleGroup?: string;
}): HiitTemplate[] {
  const db = getDb();
  seedTemplates();

  let sql = "SELECT * FROM hiit_templates WHERE 1=1";
  const params: string[] = [];

  if (filters?.style) {
    sql += " AND style = ?";
    params.push(filters.style);
  }
  if (filters?.equipment) {
    sql += " AND equipment LIKE ?";
    params.push(`%"${filters.equipment}"%`);
  }
  if (filters?.difficulty) {
    sql += " AND difficulty = ?";
    params.push(filters.difficulty);
  }
  if (filters?.muscleGroup) {
    sql += " AND target_muscle_groups LIKE ?";
    params.push(`%"${filters.muscleGroup}"%`);
  }

  sql += " ORDER BY name";
  const rows = db.prepare(sql).all(...params) as Array<Record<string, unknown>>;
  return rows.map((r) => ({
    id: r.id as string,
    name: r.name as string,
    description: r.description as string,
    style: r.style as string,
    work_seconds: r.work_seconds as number,
    rest_seconds: r.rest_seconds as number,
    rounds: r.rounds as number,
    target_muscle_groups: JSON.parse(r.target_muscle_groups as string),
    equipment: JSON.parse(r.equipment as string),
    difficulty: r.difficulty as string,
    exercises: JSON.parse(r.exercises as string),
    source: r.source as string,
  }));
}
