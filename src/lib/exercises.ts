import { v4 as uuid } from "uuid";
import { getDb } from "./db";

export interface Exercise {
  id: string;
  name: string;
  category: string;
  muscle_groups: string[];
  description: string;
  is_bilateral: boolean;
}

const SEED_EXERCISES: Omit<Exercise, "id">[] = [
  // Kettlebell exercises
  { name: "Kettlebell Goblet Squat", category: "kettlebell", muscle_groups: ["quads", "glutes", "core"], description: "Hold KB at chest, squat to depth", is_bilateral: false },
  { name: "Kettlebell Swing", category: "kettlebell", muscle_groups: ["glutes", "hamstrings", "core", "shoulders"], description: "Hip hinge explosive swing", is_bilateral: false },
  { name: "Kettlebell Clean", category: "kettlebell", muscle_groups: ["shoulders", "core", "glutes"], description: "Clean KB from floor to rack position", is_bilateral: true },
  { name: "Kettlebell Press", category: "kettlebell", muscle_groups: ["shoulders", "triceps", "core"], description: "Press KB overhead from rack position", is_bilateral: true },
  { name: "Kettlebell Snatch", category: "kettlebell", muscle_groups: ["shoulders", "back", "core", "glutes"], description: "Single motion floor to overhead", is_bilateral: true },
  { name: "Kettlebell Turkish Get-Up", category: "kettlebell", muscle_groups: ["shoulders", "core", "glutes", "quads"], description: "Floor to standing with KB overhead", is_bilateral: true },
  { name: "Kettlebell Row", category: "kettlebell", muscle_groups: ["back", "biceps", "core"], description: "Bent over single arm row", is_bilateral: true },
  { name: "Kettlebell Deadlift", category: "kettlebell", muscle_groups: ["glutes", "hamstrings", "back"], description: "Hip hinge deadlift with KB", is_bilateral: false },
  { name: "Kettlebell Thruster", category: "kettlebell", muscle_groups: ["quads", "glutes", "shoulders", "core"], description: "Squat to press in one movement", is_bilateral: false },
  { name: "Kettlebell Halo", category: "kettlebell", muscle_groups: ["shoulders", "core"], description: "Circle KB around head", is_bilateral: false },
  { name: "Kettlebell Windmill", category: "kettlebell", muscle_groups: ["core", "shoulders", "hamstrings"], description: "Overhead hold with lateral bend", is_bilateral: true },
  { name: "Kettlebell Farmer Carry", category: "kettlebell", muscle_groups: ["core", "grip", "shoulders"], description: "Walk holding KBs at sides", is_bilateral: false },
  { name: "Kettlebell Sumo Deadlift", category: "kettlebell", muscle_groups: ["glutes", "quads", "hamstrings", "adductors"], description: "Wide stance deadlift with KB", is_bilateral: false },
  { name: "Kettlebell Lunge", category: "kettlebell", muscle_groups: ["quads", "glutes", "hamstrings"], description: "Lunge holding KB in goblet or rack position", is_bilateral: true },
  { name: "Kettlebell High Pull", category: "kettlebell", muscle_groups: ["shoulders", "back", "glutes"], description: "Explosive pull to chin height", is_bilateral: true },

  // Dumbbell exercises
  { name: "Dumbbell Bench Press", category: "dumbbell", muscle_groups: ["chest", "triceps", "shoulders"], description: "Press DBs from chest on bench", is_bilateral: false },
  { name: "Dumbbell Curl", category: "dumbbell", muscle_groups: ["biceps"], description: "Standard bicep curl", is_bilateral: false },
  { name: "Dumbbell Shoulder Press", category: "dumbbell", muscle_groups: ["shoulders", "triceps"], description: "Press DBs overhead", is_bilateral: false },
  { name: "Dumbbell Row", category: "dumbbell", muscle_groups: ["back", "biceps"], description: "Single arm bent over row", is_bilateral: true },
  { name: "Dumbbell Lateral Raise", category: "dumbbell", muscle_groups: ["shoulders"], description: "Raise DBs to sides", is_bilateral: false },
  { name: "Dumbbell Lunges", category: "dumbbell", muscle_groups: ["quads", "glutes", "hamstrings"], description: "Walking or stationary lunges with DBs", is_bilateral: true },
  { name: "Dumbbell Romanian Deadlift", category: "dumbbell", muscle_groups: ["hamstrings", "glutes", "back"], description: "Hip hinge with DBs", is_bilateral: false },
  { name: "Dumbbell Thruster", category: "dumbbell", muscle_groups: ["quads", "glutes", "shoulders"], description: "Squat to press with DBs", is_bilateral: false },
  { name: "Dumbbell Renegade Row", category: "dumbbell", muscle_groups: ["back", "core", "shoulders"], description: "Plank position alternating rows", is_bilateral: false },
  { name: "Dumbbell Goblet Squat", category: "dumbbell", muscle_groups: ["quads", "glutes", "core"], description: "Hold DB at chest, squat to depth", is_bilateral: false },
  { name: "Dumbbell Tricep Extension", category: "dumbbell", muscle_groups: ["triceps"], description: "Overhead tricep extension", is_bilateral: false },
  { name: "Dumbbell Devil Press", category: "dumbbell", muscle_groups: ["chest", "shoulders", "glutes", "core"], description: "Burpee to double DB snatch", is_bilateral: false },

  // Bodyweight exercises
  { name: "Push-Up", category: "bodyweight", muscle_groups: ["chest", "triceps", "shoulders", "core"], description: "Standard push-up", is_bilateral: false },
  { name: "Burpee", category: "bodyweight", muscle_groups: ["chest", "quads", "core", "shoulders"], description: "Full body explosive movement", is_bilateral: false },
  { name: "Mountain Climber", category: "bodyweight", muscle_groups: ["core", "quads", "shoulders"], description: "Plank position alternating knee drives", is_bilateral: false },
  { name: "Squat Jump", category: "bodyweight", muscle_groups: ["quads", "glutes", "calves"], description: "Bodyweight squat with explosive jump", is_bilateral: false },
  { name: "Plank", category: "bodyweight", muscle_groups: ["core", "shoulders"], description: "Isometric core hold", is_bilateral: false },
  { name: "Dead Bug", category: "bodyweight", muscle_groups: ["core"], description: "Supine alternating arm/leg extension", is_bilateral: false },
  { name: "Glute Bridge", category: "bodyweight", muscle_groups: ["glutes", "hamstrings"], description: "Supine hip extension", is_bilateral: false },
  { name: "Walking Lunge", category: "bodyweight", muscle_groups: ["quads", "glutes", "hamstrings"], description: "Forward stepping lunges", is_bilateral: true },
  { name: "Bear Crawl", category: "bodyweight", muscle_groups: ["core", "shoulders", "quads"], description: "Quadruped crawling movement", is_bilateral: false },
  { name: "Spider Crawl", category: "bodyweight", muscle_groups: ["core", "shoulders", "hip_flexors"], description: "Low crawl with lateral knee drive", is_bilateral: false },
  { name: "Box Jump", category: "bodyweight", muscle_groups: ["quads", "glutes", "calves"], description: "Explosive jump onto elevated surface", is_bilateral: false },
  { name: "Tuck Jump", category: "bodyweight", muscle_groups: ["quads", "core", "calves"], description: "Jump bringing knees to chest", is_bilateral: false },
  { name: "High Knees", category: "bodyweight", muscle_groups: ["quads", "core", "calves"], description: "Running in place with high knee drive", is_bilateral: false },
  { name: "Bodyweight Squat", category: "bodyweight", muscle_groups: ["quads", "glutes"], description: "Standard air squat", is_bilateral: false },
  { name: "Donkey Kick", category: "bodyweight", muscle_groups: ["glutes"], description: "Quadruped hip extension", is_bilateral: true },
  { name: "Fire Hydrant", category: "bodyweight", muscle_groups: ["glutes", "hip_flexors"], description: "Quadruped hip abduction", is_bilateral: true },
  { name: "Superman", category: "bodyweight", muscle_groups: ["back", "glutes"], description: "Prone back extension", is_bilateral: false },
  { name: "V-Up", category: "bodyweight", muscle_groups: ["core"], description: "Simultaneous upper and lower body crunch", is_bilateral: false },
  { name: "Skater Jump", category: "bodyweight", muscle_groups: ["quads", "glutes", "calves"], description: "Lateral bounding jumps", is_bilateral: false },
  { name: "Inchworm", category: "bodyweight", muscle_groups: ["core", "hamstrings", "shoulders"], description: "Walk hands out to plank, walk feet to hands", is_bilateral: false },

  // Band exercises
  { name: "Band Walks", category: "band", muscle_groups: ["glutes", "hip_flexors"], description: "Lateral walks with resistance band", is_bilateral: false },
  { name: "Band Glute Bridge", category: "band", muscle_groups: ["glutes", "hamstrings"], description: "Glute bridge with band around knees", is_bilateral: false },
  { name: "Band Pull-Apart", category: "band", muscle_groups: ["back", "shoulders"], description: "Pull band apart at chest height", is_bilateral: false },
  { name: "Band Squat", category: "band", muscle_groups: ["quads", "glutes"], description: "Squat with band resistance", is_bilateral: false },
];

export function seedExercises() {
  const db = getDb();
  const count = db.prepare("SELECT COUNT(*) as count FROM exercises").get() as { count: number };
  if (count.count > 0) return;

  const insert = db.prepare(
    "INSERT INTO exercises (id, name, category, muscle_groups, description, is_bilateral) VALUES (?, ?, ?, ?, ?, ?)"
  );

  const tx = db.transaction(() => {
    for (const ex of SEED_EXERCISES) {
      insert.run(uuid(), ex.name, ex.category, JSON.stringify(ex.muscle_groups), ex.description, ex.is_bilateral ? 1 : 0);
    }
  });
  tx();
}

export function getExercises(category?: string, muscleGroup?: string): Exercise[] {
  const db = getDb();
  seedExercises();

  let sql = "SELECT * FROM exercises WHERE 1=1";
  const params: string[] = [];

  if (category) {
    sql += " AND category = ?";
    params.push(category);
  }
  if (muscleGroup) {
    const escaped = muscleGroup.replace(/[%_\\]/g, "\\$&");
    sql += " AND muscle_groups LIKE ? ESCAPE '\\'";
    params.push(`%"${escaped}"%`);
  }

  sql += " ORDER BY name";
  const rows = db.prepare(sql).all(...params) as Array<Record<string, unknown>>;
  return rows.map((r) => ({
    id: r.id as string,
    name: r.name as string,
    category: r.category as string,
    muscle_groups: JSON.parse(r.muscle_groups as string),
    description: r.description as string,
    is_bilateral: r.is_bilateral === 1,
  }));
}
