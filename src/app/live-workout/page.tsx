"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import Link from "next/link";
import {
  type ExerciseType,
  type DetectedSet,
  type MovementState,
  type FormAlertEvent,
  type SetQualityMetrics,
  EXERCISE_TYPE_LABELS,
  getConfidenceLevel,
} from "@/lib/sensor-types";

interface LiveSet {
  exerciseType: ExerciseType;
  reps: number;
  confidence: number;
  durationSeconds: number;
  startTime: string;
  endTime?: string;
  quality?: SetQualityMetrics;
  isActive: boolean;
}

type WorkoutPhase = "pre" | "active" | "summary";

export default function LiveWorkoutPage() {
  const [phase, setPhase] = useState<WorkoutPhase>("pre");
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [currentReps, setCurrentReps] = useState(0);
  const [currentExercise, setCurrentExercise] = useState<ExerciseType>("unknown");
  const [currentConfidence, setCurrentConfidence] = useState(0);
  const [movementState, setMovementState] = useState<MovementState>("idle");
  const [formAlert, setFormAlert] = useState<FormAlertEvent | null>(null);
  const [completedSets, setCompletedSets] = useState<LiveSet[]>([]);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [editingSet, setEditingSet] = useState<number | null>(null);
  const [sensorStatus, setSensorStatus] = useState({
    leftFoot: false,
    rightFoot: false,
    watch: false,
  });

  const timerRef = useRef<ReturnType<typeof setInterval>>(undefined);
  const startTimeRef = useRef<Date>(undefined);
  const cleanupFns = useRef<Array<() => void>>([]);

  // Elapsed time tracker
  useEffect(() => {
    if (phase === "active") {
      startTimeRef.current = new Date();
      timerRef.current = setInterval(() => {
        if (startTimeRef.current) {
          setElapsedSeconds(
            Math.floor((Date.now() - startTimeRef.current.getTime()) / 1000)
          );
        }
      }, 1000);
      return () => clearInterval(timerRef.current);
    }
  }, [phase]);

  // Simulate sensor events in browser
  useEffect(() => {
    if (phase !== "active") return;

    const isNative = !!(window as unknown as { Capacitor?: unknown }).Capacitor;
    if (isNative) return; // Will use real plugin events in native mode

    // Simulate exercise detection cycle
    const exercises: ExerciseType[] = [
      "jump_rope",
      "alternating_lunges",
      "pogo_hops",
      "step_ups",
    ];
    let setIndex = 0;
    let repCount = 0;
    let exerciseIdx = 0;

    const simInterval = setInterval(() => {
      // Simulate movement state changes
      const cycleTime = Date.now() % 45000; // 45-second cycles

      if (cycleTime < 30000) {
        // Active phase (30s)
        setMovementState("active");
        repCount++;
        setCurrentReps(repCount);
        setCurrentExercise(exercises[exerciseIdx]);
        setCurrentConfidence(0.75 + Math.random() * 0.2);

        // Simulate form alert occasionally
        if (repCount === 8) {
          setFormAlert({ message: "Go deeper!", severity: "warning" });
          setTimeout(() => setFormAlert(null), 3000);
        }
      } else if (cycleTime < 40000) {
        // Rest phase (10s)
        if (movementState === "active" && repCount > 0) {
          // Set just ended
          setCompletedSets((prev) => [
            ...prev,
            {
              exerciseType: exercises[exerciseIdx],
              reps: repCount,
              confidence: 0.82,
              durationSeconds: 30,
              startTime: new Date(Date.now() - 30000).toISOString(),
              endTime: new Date().toISOString(),
              quality: {
                avgTempo: 800 + Math.random() * 200,
                tempoConsistency: 0.7 + Math.random() * 0.2,
                symmetryScore: 0.75 + Math.random() * 0.2,
                depthScore: 0.7 + Math.random() * 0.25,
                depthConsistency: 0.65 + Math.random() * 0.3,
                overallQuality: 0.72 + Math.random() * 0.2,
              },
              isActive: false,
            },
          ]);
          repCount = 0;
          setIndex++;
          exerciseIdx = (exerciseIdx + 1) % exercises.length;
          setCurrentReps(0);
        }
        setMovementState("resting");
      } else {
        setMovementState("idle");
      }
    }, 1000);

    return () => clearInterval(simInterval);
  }, [phase, movementState]);

  const handleStartWorkout = async () => {
    // Create session via API
    try {
      const res = await fetch("/api/sensor-sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sensorConfig: {
            leftFootConnected: sensorStatus.leftFoot,
            rightFootConnected: sensorStatus.rightFoot,
            watchConnected: sensorStatus.watch,
            sampleRateHz: 50,
          },
        }),
      });
      const session = await res.json();
      setSessionId(session.id);
    } catch {
      // Continue even if API fails (browser testing)
      setSessionId("demo-session");
    }

    setPhase("active");
    setSensorStatus({ leftFoot: true, rightFoot: true, watch: true });
  };

  const handleEndWorkout = async () => {
    clearInterval(timerRef.current);

    // Save detected sets via API
    if (sessionId && sessionId !== "demo-session") {
      for (const set of completedSets) {
        await fetch(`/api/sensor-sessions/${sessionId}/sets`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            exerciseType: set.exerciseType,
            detectedType: set.exerciseType,
            classifierConfidence: set.confidence,
            startTime: set.startTime,
            endTime: set.endTime || new Date().toISOString(),
            repCountDetected: set.reps,
            qualityMetrics: set.quality,
          }),
        });
      }

      // End the session
      await fetch(`/api/sensor-sessions/${sessionId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "end" }),
      });
    }

    setPhase("summary");
  };

  const handleCorrectExercise = (setIndex: number, newType: ExerciseType) => {
    setCompletedSets((prev) =>
      prev.map((s, i) =>
        i === setIndex ? { ...s, exerciseType: newType } : s
      )
    );
    setEditingSet(null);
  };

  const handleCorrectReps = (setIndex: number, delta: number) => {
    setCompletedSets((prev) =>
      prev.map((s, i) =>
        i === setIndex ? { ...s, reps: Math.max(0, s.reps + delta) } : s
      )
    );
  };

  const handleDeleteSet = (setIndex: number) => {
    setCompletedSets((prev) => prev.filter((_, i) => i !== setIndex));
  };

  const formatTime = (s: number) => {
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec.toString().padStart(2, "0")}`;
  };

  const totalReps = completedSets.reduce((sum, s) => sum + s.reps, 0);
  const avgQuality =
    completedSets.length > 0
      ? completedSets.reduce(
          (sum, s) => sum + (s.quality?.overallQuality ?? 0),
          0
        ) / completedSets.filter((s) => s.quality).length || 0
      : 0;

  // --- Pre-workout: Sensor check ---
  if (phase === "pre") {
    return (
      <main className="flex-1 flex flex-col p-4 max-w-lg mx-auto w-full">
        <div className="flex items-center gap-3 mb-6">
          <Link href="/" className="text-gray-400 hover:text-white">&larr;</Link>
          <h1 className="text-2xl font-bold">Auto-Detect Workout</h1>
        </div>

        <div className="flex-1 flex flex-col justify-center space-y-6">
          <div className="text-center mb-4">
            <div className="text-6xl mb-4">&#x1F3CB;</div>
            <p className="text-gray-400">
              Connect your sensors and start training. The app will
              automatically detect exercises, count reps, and track your sets.
            </p>
          </div>

          {/* Sensor Status */}
          <div className="space-y-3">
            <h2 className="text-sm font-semibold text-gray-400 uppercase">
              Sensors
            </h2>
            {[
              { key: "leftFoot", label: "Left Foot Sensor", icon: "&#x1F9B6;" },
              { key: "rightFoot", label: "Right Foot Sensor", icon: "&#x1F9B6;" },
              { key: "watch", label: "Apple Watch", icon: "&#x231A;" },
            ].map(({ key, label, icon }) => (
              <div
                key={key}
                className="flex items-center justify-between p-3 rounded-xl bg-gray-800 border border-gray-700"
              >
                <div className="flex items-center gap-3">
                  <span
                    className="text-2xl"
                    dangerouslySetInnerHTML={{ __html: icon }}
                  />
                  <span className="font-medium">{label}</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-2.5 h-2.5 rounded-full bg-gray-600" />
                  <span className="text-xs text-gray-500">Not connected</span>
                </div>
              </div>
            ))}
          </div>

          <p className="text-xs text-gray-500 text-center">
            Sensor connection is optional in demo mode. Tap Start to try with
            simulated data.
          </p>

          <button
            onClick={handleStartWorkout}
            className="w-full py-4 rounded-2xl bg-gradient-to-r from-green-500 to-emerald-600 text-white text-lg font-bold shadow-lg active:scale-[0.98] transition-transform"
          >
            Start Workout
          </button>

          <Link
            href="/sensor-debug"
            className="block text-center text-sm text-blue-400 hover:text-blue-300"
          >
            Open Sensor Debug View
          </Link>
        </div>
      </main>
    );
  }

  // --- Active workout ---
  if (phase === "active") {
    return (
      <main className="flex-1 flex flex-col p-4 max-w-lg mx-auto w-full">
        {/* Form Alert Banner */}
        {formAlert && (
          <div
            className={`fixed top-0 left-0 right-0 z-50 p-3 text-center font-bold text-white ${
              formAlert.severity === "error"
                ? "bg-red-600"
                : formAlert.severity === "warning"
                  ? "bg-orange-500"
                  : "bg-blue-500"
            }`}
          >
            {formAlert.message}
          </div>
        )}

        {/* Top Bar */}
        <div className="flex items-center justify-between mb-4">
          <div className="text-sm text-gray-400">
            {formatTime(elapsedSeconds)}
          </div>
          <div className="flex gap-1.5">
            {[
              { connected: sensorStatus.leftFoot, label: "L" },
              { connected: sensorStatus.rightFoot, label: "R" },
              { connected: sensorStatus.watch, label: "W" },
            ].map(({ connected, label }) => (
              <div
                key={label}
                className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${
                  connected
                    ? "bg-green-500/20 text-green-400 border border-green-500/30"
                    : "bg-gray-800 text-gray-600 border border-gray-700"
                }`}
              >
                {label}
              </div>
            ))}
          </div>
          <button
            onClick={handleEndWorkout}
            className="px-4 py-1.5 rounded-xl bg-red-600/20 text-red-400 border border-red-600/30 text-sm font-medium active:scale-95"
          >
            End
          </button>
        </div>

        {/* Hero Rep Counter */}
        <div className="text-center mb-6">
          <div
            className={`text-8xl font-black tabular-nums ${
              movementState === "active"
                ? "text-white"
                : movementState === "resting"
                  ? "text-blue-400"
                  : "text-gray-600"
            }`}
          >
            {currentReps}
          </div>
          <div className="flex items-center justify-center gap-2 mt-2">
            <div
              className={`w-2.5 h-2.5 rounded-full ${
                getConfidenceLevel(currentConfidence) === "high"
                  ? "bg-green-500"
                  : getConfidenceLevel(currentConfidence) === "medium"
                    ? "bg-yellow-500"
                    : "bg-red-500"
              }`}
            />
            <span className="text-lg font-semibold">
              {currentExercise !== "unknown"
                ? EXERCISE_TYPE_LABELS[currentExercise]
                : "Detecting..."}
            </span>
          </div>
          <div
            className={`text-sm mt-1 font-medium ${
              movementState === "active"
                ? "text-green-400"
                : movementState === "resting"
                  ? "text-blue-400"
                  : "text-gray-500"
            }`}
          >
            {movementState === "active"
              ? "Active"
              : movementState === "resting"
                ? "Resting..."
                : "Idle"}
          </div>
        </div>

        {/* Completed Sets */}
        <div className="flex-1 overflow-y-auto space-y-2">
          <h2 className="text-xs font-semibold text-gray-500 uppercase">
            Sets ({completedSets.length})
          </h2>
          {completedSets.map((set, i) => (
            <SetCard
              key={i}
              set={set}
              index={i}
              isEditing={editingSet === i}
              onStartEdit={() => setEditingSet(i)}
              onCancelEdit={() => setEditingSet(null)}
              onCorrectExercise={(type) => handleCorrectExercise(i, type)}
              onCorrectReps={(delta) => handleCorrectReps(i, delta)}
              onDelete={() => handleDeleteSet(i)}
            />
          ))}
          {completedSets.length === 0 && (
            <p className="text-center text-gray-600 text-sm py-8">
              Sets will appear here as you exercise
            </p>
          )}
        </div>
      </main>
    );
  }

  // --- Workout Summary ---
  return (
    <main className="flex-1 flex flex-col p-4 max-w-lg mx-auto w-full">
      <div className="text-center mb-6">
        <div className="text-5xl mb-3">&#x1F3C6;</div>
        <h1 className="text-2xl font-bold">Workout Complete</h1>
        <p className="text-gray-400 mt-1">{formatTime(elapsedSeconds)}</p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-3 mb-6">
        <div className="p-4 rounded-xl bg-gray-800 border border-gray-700 text-center">
          <div className="text-2xl font-bold text-white">
            {completedSets.length}
          </div>
          <div className="text-xs text-gray-400">Sets</div>
        </div>
        <div className="p-4 rounded-xl bg-gray-800 border border-gray-700 text-center">
          <div className="text-2xl font-bold text-white">{totalReps}</div>
          <div className="text-xs text-gray-400">Reps</div>
        </div>
        <div className="p-4 rounded-xl bg-gray-800 border border-gray-700 text-center">
          <div className="text-2xl font-bold text-white">
            {avgQuality > 0 ? `${Math.round(avgQuality * 100)}%` : "--"}
          </div>
          <div className="text-xs text-gray-400">Quality</div>
        </div>
      </div>

      {/* Exercise Breakdown */}
      <h2 className="text-sm font-semibold text-gray-400 uppercase mb-3">
        Exercise Breakdown
      </h2>
      <div className="space-y-2 mb-6">
        {Array.from(
          completedSets.reduce((map, set) => {
            const key = set.exerciseType;
            const existing = map.get(key) || { sets: 0, reps: 0 };
            map.set(key, {
              sets: existing.sets + 1,
              reps: existing.reps + set.reps,
            });
            return map;
          }, new Map<ExerciseType, { sets: number; reps: number }>())
        ).map(([type, stats]) => (
          <div
            key={type}
            className="flex items-center justify-between p-3 rounded-xl bg-gray-800 border border-gray-700"
          >
            <span className="font-medium">
              {EXERCISE_TYPE_LABELS[type]}
            </span>
            <span className="text-gray-400 text-sm">
              {stats.sets} sets &middot; {stats.reps} reps
            </span>
          </div>
        ))}
      </div>

      {/* Set Details */}
      <h2 className="text-sm font-semibold text-gray-400 uppercase mb-3">
        All Sets
      </h2>
      <div className="space-y-2 mb-6">
        {completedSets.map((set, i) => (
          <SetCard
            key={i}
            set={set}
            index={i}
            isEditing={editingSet === i}
            onStartEdit={() => setEditingSet(i)}
            onCancelEdit={() => setEditingSet(null)}
            onCorrectExercise={(type) => handleCorrectExercise(i, type)}
            onCorrectReps={(delta) => handleCorrectReps(i, delta)}
            onDelete={() => handleDeleteSet(i)}
          />
        ))}
      </div>

      {/* Actions */}
      <div className="space-y-3">
        <Link
          href="/history"
          className="block w-full py-3 rounded-xl bg-blue-600 text-white text-center font-semibold active:scale-[0.98] transition-transform"
        >
          View History
        </Link>
        <Link
          href="/"
          className="block w-full py-3 rounded-xl bg-gray-700 text-white text-center font-semibold active:scale-[0.98] transition-transform"
        >
          Home
        </Link>
      </div>
    </main>
  );
}

// --- Set Card Component ---

function SetCard({
  set,
  index,
  isEditing,
  onStartEdit,
  onCancelEdit,
  onCorrectExercise,
  onCorrectReps,
  onDelete,
}: {
  set: LiveSet;
  index: number;
  isEditing: boolean;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onCorrectExercise: (type: ExerciseType) => void;
  onCorrectReps: (delta: number) => void;
  onDelete: () => void;
}) {
  const confidenceLevel = getConfidenceLevel(set.confidence);

  return (
    <div className="p-3 rounded-xl bg-gray-800/80 border border-gray-700">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div
            className={`w-2 h-2 rounded-full ${
              confidenceLevel === "high"
                ? "bg-green-500"
                : confidenceLevel === "medium"
                  ? "bg-yellow-500"
                  : "bg-red-500"
            }`}
          />
          <span className="font-medium text-sm">
            {EXERCISE_TYPE_LABELS[set.exerciseType]}
          </span>
        </div>
        <div className="flex items-center gap-3 text-sm text-gray-400">
          <span className="font-semibold text-white">{set.reps} reps</span>
          <span>{set.durationSeconds}s</span>
        </div>
      </div>

      {/* Quality Metrics */}
      {set.quality && (
        <div className="flex gap-3 mt-2 text-xs text-gray-500">
          <span>
            Tempo: {Math.round(set.quality.avgTempo)}ms
          </span>
          <span>
            Symmetry: {Math.round(set.quality.symmetryScore * 100)}%
          </span>
          <span>
            Quality: {Math.round(set.quality.overallQuality * 100)}%
          </span>
        </div>
      )}

      {/* Edit Controls */}
      {!isEditing ? (
        <button
          onClick={onStartEdit}
          className="mt-2 text-xs text-blue-400 hover:text-blue-300"
        >
          Edit
        </button>
      ) : (
        <div className="mt-3 space-y-2">
          {/* Exercise Correction */}
          <div className="flex flex-wrap gap-1">
            {(Object.keys(EXERCISE_TYPE_LABELS) as ExerciseType[])
              .filter((t) => t !== "unknown")
              .map((type) => (
                <button
                  key={type}
                  onClick={() => onCorrectExercise(type)}
                  className={`px-2 py-1 text-xs rounded-lg border ${
                    type === set.exerciseType
                      ? "bg-blue-600/20 border-blue-500/50 text-blue-300"
                      : "border-gray-600 text-gray-400 hover:border-gray-500"
                  }`}
                >
                  {EXERCISE_TYPE_LABELS[type]}
                </button>
              ))}
          </div>

          {/* Rep Adjustment */}
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-400">Reps:</span>
            <button
              onClick={() => onCorrectReps(-1)}
              className="w-7 h-7 rounded-lg bg-gray-700 text-gray-300 text-sm font-bold active:scale-90"
            >
              -
            </button>
            <span className="text-sm font-bold w-8 text-center">
              {set.reps}
            </span>
            <button
              onClick={() => onCorrectReps(1)}
              className="w-7 h-7 rounded-lg bg-gray-700 text-gray-300 text-sm font-bold active:scale-90"
            >
              +
            </button>
          </div>

          <div className="flex gap-2">
            <button
              onClick={onDelete}
              className="px-3 py-1.5 text-xs rounded-lg bg-red-600/20 text-red-400 border border-red-600/30"
            >
              Delete Set
            </button>
            <button
              onClick={onCancelEdit}
              className="px-3 py-1.5 text-xs rounded-lg bg-gray-700 text-gray-300"
            >
              Done
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
