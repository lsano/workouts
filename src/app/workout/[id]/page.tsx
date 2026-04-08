"use client";

import { useState, useEffect, useCallback, use } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import Timer from "@/components/Timer";
import SetTracker from "@/components/SetTracker";

interface ExerciseSet {
  id: string;
  set_number: number;
  reps?: number;
  weight_lbs?: number;
  duration_seconds?: number;
  completed: boolean;
  rpe?: number;
}

interface WorkoutExercise {
  id: string;
  exercise_name: string;
  notes?: string;
  sets: ExerciseSet[];
}

interface WorkoutSection {
  id: string;
  name: string;
  section_type: string;
  work_seconds?: number;
  rest_seconds?: number;
  rounds?: number;
  exercises: WorkoutExercise[];
}

interface Workout {
  id: string;
  mode: string;
  name?: string;
  date: string;
  status: string;
  sections: WorkoutSection[];
}

export default function WorkoutPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();
  const [workout, setWorkout] = useState<Workout | null>(null);
  const [activeSection, setActiveSection] = useState(0);
  const [loading, setLoading] = useState(true);

  const fetchWorkout = useCallback(async () => {
    const res = await fetch(`/api/workouts/${id}`);
    if (res.ok) {
      const data = await res.json();
      setWorkout(data);
    }
    setLoading(false);
  }, [id]);

  useEffect(() => {
    fetchWorkout();
  }, [fetchWorkout]);

  const startWorkout = async () => {
    await fetch(`/api/workouts/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "in_progress" }),
    });
    fetchWorkout();
  };

  const completeWorkout = async () => {
    await fetch(`/api/workouts/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "completed" }),
    });
    router.push("/history");
  };

  if (loading) {
    return (
      <main className="flex-1 flex items-center justify-center">
        <div className="animate-pulse text-gray-500">Loading workout...</div>
      </main>
    );
  }

  if (!workout) {
    return (
      <main className="flex-1 flex flex-col items-center justify-center gap-4">
        <p className="text-gray-500">Workout not found</p>
        <Link href="/" className="text-blue-500">Go home</Link>
      </main>
    );
  }

  const section = workout.sections[activeSection];
  const totalSets = workout.sections.flatMap((s) => s.exercises.flatMap((e) => e.sets));
  const completedSets = totalSets.filter((s) => s.completed);
  const progress = totalSets.length > 0 ? (completedSets.length / totalSets.length) * 100 : 0;

  return (
    <main className="flex-1 flex flex-col max-w-lg mx-auto w-full">
      {/* Header */}
      <div className="p-4 border-b border-gray-200 dark:border-gray-800">
        <div className="flex items-center justify-between mb-2">
          <Link href="/" className="text-2xl">&#x2190;</Link>
          <span className={`text-xs px-2 py-1 rounded-full font-medium ${
            workout.status === "completed"
              ? "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
              : workout.status === "in_progress"
              ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300"
              : "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300"
          }`}>
            {workout.status.replace("_", " ")}
          </span>
        </div>
        <h1 className="text-xl font-bold">{workout.name || "Workout"}</h1>
        <p className="text-sm text-gray-500">{workout.date}</p>

        {/* Progress bar */}
        <div className="mt-3">
          <div className="flex justify-between text-xs text-gray-500 mb-1">
            <span>{completedSets.length} / {totalSets.length} sets</span>
            <span>{Math.round(progress)}%</span>
          </div>
          <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
            <div
              className="h-2 rounded-full bg-green-500 transition-all"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>
      </div>

      {/* Section tabs */}
      {workout.sections.length > 1 && (
        <div className="flex overflow-x-auto border-b border-gray-200 dark:border-gray-800 px-2">
          {workout.sections.map((s, i) => (
            <button
              key={s.id}
              onClick={() => setActiveSection(i)}
              className={`flex-shrink-0 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
                i === activeSection
                  ? "border-blue-500 text-blue-600 dark:text-blue-400"
                  : "border-transparent text-gray-500"
              }`}
            >
              {s.name}
            </button>
          ))}
        </div>
      )}

      {/* Section content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {workout.status === "planned" && (
          <button
            onClick={startWorkout}
            className="w-full py-4 rounded-2xl font-bold text-lg bg-green-500 text-white active:bg-green-600"
          >
            Start Workout
          </button>
        )}

        {/* Timer for timed sections */}
        {section && section.work_seconds && section.work_seconds > 0 && workout.status === "in_progress" && (
          <Timer
            workSeconds={section.work_seconds}
            restSeconds={section.rest_seconds || 0}
            rounds={section.rounds || 1}
          />
        )}

        {/* Exercises */}
        {section?.exercises.map((exercise) => (
          <SetTracker
            key={exercise.id}
            exerciseName={exercise.exercise_name + (exercise.notes ? ` (${exercise.notes})` : "")}
            exerciseId={exercise.id}
            sets={exercise.sets}
            workoutId={workout.id}
            onUpdate={fetchWorkout}
          />
        ))}

        {workout.status === "in_progress" && (
          <button
            onClick={completeWorkout}
            className="w-full py-4 rounded-2xl font-bold text-lg bg-blue-500 text-white active:bg-blue-600 mt-4"
          >
            Complete Workout
          </button>
        )}
      </div>
    </main>
  );
}
