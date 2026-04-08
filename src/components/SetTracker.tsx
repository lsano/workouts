"use client";

import { useState } from "react";
import { hapticImpact } from "@/lib/camera";

interface SetData {
  id: string;
  set_number: number;
  reps?: number;
  weight_lbs?: number;
  duration_seconds?: number;
  completed: boolean;
  rpe?: number;
}

interface SetTrackerProps {
  exerciseName: string;
  exerciseId: string;
  sets: SetData[];
  workoutId: string;
  onUpdate: () => void;
}

export default function SetTracker({ exerciseName, sets, workoutId, onUpdate }: SetTrackerProps) {
  const [localSets, setLocalSets] = useState(sets);

  const updateSet = async (setId: string, field: string, value: number | boolean) => {
    await fetch(`/api/workouts/${workoutId}/sets/${setId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ [field]: value }),
    });

    setLocalSets((prev) =>
      prev.map((s) => (s.id === setId ? { ...s, [field]: value } : s))
    );
    onUpdate();
  };

  const addSet = async () => {
    const res = await fetch(`/api/workouts/${workoutId}/sets`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ workout_exercise_id: sets[0]?.id ? undefined : undefined }),
    });
    if (res.ok) {
      onUpdate();
    }
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-xl p-4 shadow-sm">
      <h4 className="font-semibold text-base mb-3">{exerciseName}</h4>

      <div className="space-y-2">
        {/* Header */}
        <div className="grid grid-cols-[2rem_1fr_1fr_2.5rem] gap-2 text-xs text-gray-500 font-medium px-1">
          <span>Set</span>
          <span>Reps</span>
          <span>Weight</span>
          <span></span>
        </div>

        {localSets.map((set) => (
          <div
            key={set.id}
            className={`grid grid-cols-[2rem_1fr_1fr_2.5rem] gap-2 items-center p-1 rounded-lg ${
              set.completed ? "bg-green-50 dark:bg-green-900/20" : ""
            }`}
          >
            <span className="text-sm font-medium text-center">{set.set_number}</span>

            <input
              type="number"
              inputMode="numeric"
              placeholder="--"
              value={set.reps ?? ""}
              onChange={(e) => {
                const val = parseInt(e.target.value) || 0;
                setLocalSets((prev) =>
                  prev.map((s) => (s.id === set.id ? { ...s, reps: val } : s))
                );
              }}
              onBlur={(e) => {
                const val = parseInt(e.target.value);
                if (!isNaN(val)) updateSet(set.id, "reps", val);
              }}
              className="w-full px-2 py-2 text-center rounded-lg border border-gray-200 dark:border-gray-600 dark:bg-gray-700 text-sm"
            />

            <input
              type="number"
              inputMode="decimal"
              placeholder="lbs"
              value={set.weight_lbs ?? ""}
              onChange={(e) => {
                const val = parseFloat(e.target.value) || 0;
                setLocalSets((prev) =>
                  prev.map((s) => (s.id === set.id ? { ...s, weight_lbs: val } : s))
                );
              }}
              onBlur={(e) => {
                const val = parseFloat(e.target.value);
                if (!isNaN(val)) updateSet(set.id, "weight_lbs", val);
              }}
              className="w-full px-2 py-2 text-center rounded-lg border border-gray-200 dark:border-gray-600 dark:bg-gray-700 text-sm"
            />

            <button
              onClick={() => {
                hapticImpact(set.completed ? "light" : "heavy");
                updateSet(set.id, "completed", !set.completed);
              }}
              className={`w-8 h-8 rounded-full flex items-center justify-center text-lg ${
                set.completed
                  ? "bg-green-500 text-white"
                  : "border-2 border-gray-300 dark:border-gray-600"
              }`}
            >
              {set.completed ? "\u2713" : ""}
            </button>
          </div>
        ))}
      </div>

      <button
        onClick={addSet}
        className="mt-2 w-full py-2 text-sm text-blue-500 font-medium rounded-lg border border-dashed border-blue-300 active:bg-blue-50"
      >
        + Add Set
      </button>
    </div>
  );
}
