"use client";

import { useState, useEffect, useCallback, useRef, use } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import Timer from "@/components/Timer";
import SetTracker from "@/components/SetTracker";
import { HeartRateMonitor } from "@/components/HeartRateMonitor";
import {
  saveWorkoutToHealth,
  syncToWatch,
  onWatchAction,
  checkHealthKitAvailable,
} from "@/lib/health/health-service";
import type { WatchExerciseEntry } from "../../../../ios-plugins/healthkit/src/definitions";

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
  const [activeExerciseIdx, setActiveExerciseIdx] = useState(0);
  const [loading, setLoading] = useState(true);
  const [healthStats, setHealthStats] = useState<{ totalCalories?: number; averageHeartRate?: number }>({});
  const workoutStartRef = useRef<Date | null>(null);
  const watchListenerRef = useRef<{ remove: () => void } | null>(null);

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

  // Build flat exercise list for watch sync
  const buildExerciseList = useCallback((w: Workout): WatchExerciseEntry[] => {
    const list: WatchExerciseEntry[] = [];
    for (const section of w.sections) {
      for (const exercise of section.exercises) {
        const completedSets = exercise.sets.filter(s => s.completed);
        const lastCompleted = completedSets[completedSets.length - 1];
        list.push({
          id: exercise.id,
          name: exercise.exercise_name,
          notes: exercise.notes,
          sectionName: section.name,
          setsTotal: exercise.sets.length,
          setsCompleted: completedSets.length,
          lastReps: lastCompleted?.reps,
          lastWeight: lastCompleted?.weight_lbs,
        });
      }
    }
    return list;
  }, []);

  // Find the global exercise index from section + exercise position
  const getGlobalExerciseIndex = useCallback((w: Workout, sectionIdx: number, exerciseIdx: number): number => {
    let idx = 0;
    for (let si = 0; si < w.sections.length; si++) {
      for (let ei = 0; ei < w.sections[si].exercises.length; ei++) {
        if (si === sectionIdx && ei === exerciseIdx) return idx;
        idx++;
      }
    }
    return 0;
  }, []);

  // Find section + exercise position from global index
  const fromGlobalIndex = useCallback((w: Workout, globalIdx: number): { sectionIdx: number; exerciseIdx: number } => {
    let idx = 0;
    for (let si = 0; si < w.sections.length; si++) {
      for (let ei = 0; ei < w.sections[si].exercises.length; ei++) {
        if (idx === globalIdx) return { sectionIdx: si, exerciseIdx: ei };
        idx++;
      }
    }
    return { sectionIdx: 0, exerciseIdx: 0 };
  }, []);

  // Sync workout state to Apple Watch
  useEffect(() => {
    if (!workout || workout.status !== "in_progress") return;

    const section = workout.sections[activeSection];
    const exercise = section?.exercises[activeExerciseIdx];
    const completedSets = exercise?.sets.filter(s => s.completed).length ?? 0;

    syncToWatch({
      isActive: true,
      workoutName: workout.name || "Workout",
      currentExercise: exercise?.exercise_name,
      currentExerciseIndex: getGlobalExerciseIndex(workout, activeSection, activeExerciseIdx),
      currentSet: completedSets,
      totalSets: exercise?.sets.length ?? 0,
      timerPhase: "work",
      exercises: buildExerciseList(workout),
    });
  }, [workout, activeSection, activeExerciseIdx, buildExerciseList, getGlobalExerciseIndex]);

  // Listen for watch actions
  useEffect(() => {
    let cancelled = false;

    checkHealthKitAvailable().then(async (available) => {
      if (!available || cancelled) return;

      const listener = await onWatchAction(async (action, payload) => {
        if (!workout) return;

        switch (action) {
          case "logSet": {
            const exIdx = (payload?.exerciseIndex as number) ?? 0;
            const reps = payload?.reps as number | undefined;
            const weight = payload?.weight as number | undefined;
            const { sectionIdx, exerciseIdx } = fromGlobalIndex(workout, exIdx);
            const exercise = workout.sections[sectionIdx]?.exercises[exerciseIdx];
            if (!exercise) break;

            // Find the first incomplete set
            const incompleteSet = exercise.sets.find(s => !s.completed);
            if (incompleteSet) {
              await fetch(`/api/workouts/${id}/sets/${incompleteSet.id}`, {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ completed: true, reps, weight_lbs: weight }),
              });
              fetchWorkout();
            }
            break;
          }

          case "completeSet": {
            const exIdx = (payload?.exerciseIndex as number) ?? 0;
            const { sectionIdx, exerciseIdx } = fromGlobalIndex(workout, exIdx);
            const exercise = workout.sections[sectionIdx]?.exercises[exerciseIdx];
            if (!exercise) break;

            const incompleteSet = exercise.sets.find(s => !s.completed);
            if (incompleteSet) {
              await fetch(`/api/workouts/${id}/sets/${incompleteSet.id}`, {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ completed: true }),
              });
              fetchWorkout();
            }
            break;
          }

          case "navigateExercise": {
            const targetIdx = payload?.index as number;
            if (typeof targetIdx === "number") {
              const { sectionIdx, exerciseIdx } = fromGlobalIndex(workout, targetIdx);
              setActiveSection(sectionIdx);
              setActiveExerciseIdx(exerciseIdx);
            }
            break;
          }

          case "endWorkout": {
            completeWorkout();
            break;
          }
        }
      });

      if (!cancelled && listener) {
        watchListenerRef.current = listener;
      }
    });

    return () => {
      cancelled = true;
      watchListenerRef.current?.remove();
      watchListenerRef.current = null;
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workout?.id, workout?.status]);

  const startWorkout = async () => {
    workoutStartRef.current = new Date();
    await fetch(`/api/workouts/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "in_progress" }),
    });
    fetchWorkout();
  };

  const completeWorkout = async () => {
    const endDate = new Date();

    // Tell watch workout is over
    syncToWatch({ isActive: false }).catch(() => {});

    await fetch(`/api/workouts/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "completed" }),
    });

    if (workoutStartRef.current && workout) {
      saveWorkoutToHealth({
        startDate: workoutStartRef.current,
        endDate,
        name: workout.name || "WOD Workout",
        type: "functionalStrengthTraining",
        calories: healthStats.totalCalories,
      }).catch(() => {});
    }

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

  const currentExercise = section?.exercises[activeExerciseIdx] ?? section?.exercises[0];

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
              onClick={() => { setActiveSection(i); setActiveExerciseIdx(0); }}
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

      {/* Heart rate monitor - visible during active workouts */}
      {workout.status === "in_progress" && (
        <div className="px-4 pt-3">
          <HeartRateMonitor
            workoutName={workout.name || "Workout"}
            currentExercise={currentExercise?.exercise_name}
            currentSet={currentExercise?.sets.filter(s => s.completed).length ?? 0}
            totalSets={currentExercise?.sets.length ?? 0}
            isActive={workout.status === "in_progress"}
            onSessionEnd={(stats) => setHealthStats(stats)}
          />
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
        {section?.exercises.map((exercise, ei) => (
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
