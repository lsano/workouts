"use client";

import { useState, useEffect, useRef } from "react";
import {
  checkHealthKitAvailable,
  startLiveSession,
  syncToWatch,
} from "@/lib/health/health-service";
import type { WorkoutActivityType } from "../../ios-plugins/healthkit/src/definitions";

interface HeartRateMonitorProps {
  workoutName: string;
  currentExercise?: string;
  currentSet?: number;
  totalSets?: number;
  timerPhase?: "work" | "rest" | "idle";
  timeRemaining?: number;
  isActive: boolean;
  onSessionEnd?: (stats: { totalCalories?: number; averageHeartRate?: number }) => void;
}

export function HeartRateMonitor({
  workoutName,
  currentExercise,
  currentSet,
  totalSets,
  timerPhase,
  timeRemaining,
  isActive,
  onSessionEnd,
}: HeartRateMonitorProps) {
  const [available, setAvailable] = useState(false);
  const [heartRate, setHeartRate] = useState<number | null>(null);
  const [sessionActive, setSessionActive] = useState(false);
  const sessionRef = useRef<Awaited<ReturnType<typeof startLiveSession>>>(null);
  const listenerRef = useRef<{ remove: () => void } | null>(null);

  useEffect(() => {
    checkHealthKitAvailable().then(setAvailable);
  }, []);

  // Start/stop live session based on workout state
  useEffect(() => {
    if (!available) return;

    if (isActive && !sessionActive) {
      startSession();
    } else if (!isActive && sessionActive) {
      endSession();
    }
  }, [isActive, available, sessionActive]);

  // Sync state to Apple Watch whenever it changes
  useEffect(() => {
    if (!available) return;

    syncToWatch({
      isActive,
      workoutName,
      currentExercise,
      currentSet,
      totalSets,
      timerPhase,
      timeRemaining,
      heartRate: heartRate ?? undefined,
    });
  }, [available, isActive, workoutName, currentExercise, currentSet, totalSets, timerPhase, timeRemaining, heartRate]);

  async function startSession() {
    const activityType: WorkoutActivityType = "functionalStrengthTraining";
    const session = await startLiveSession(activityType);
    if (!session) return;

    sessionRef.current = session;
    setSessionActive(true);

    const listener = await session.onHeartRate((bpm) => {
      setHeartRate(bpm);
    });
    listenerRef.current = listener;
  }

  async function endSession() {
    if (listenerRef.current) {
      listenerRef.current.remove();
      listenerRef.current = null;
    }

    if (sessionRef.current) {
      const result = await sessionRef.current.end();
      sessionRef.current = null;
      setSessionActive(false);
      setHeartRate(null);

      if (result && onSessionEnd) {
        onSessionEnd({
          totalCalories: result.totalCalories,
          averageHeartRate: result.averageHeartRate,
        });
      }
    }
  }

  if (!available || !sessionActive) return null;

  // Heart rate zone coloring
  const getZoneColor = (bpm: number) => {
    if (bpm < 100) return "text-blue-500";
    if (bpm < 130) return "text-green-500";
    if (bpm < 155) return "text-yellow-500";
    if (bpm < 175) return "text-orange-500";
    return "text-red-500";
  };

  const getZoneLabel = (bpm: number) => {
    if (bpm < 100) return "Rest";
    if (bpm < 130) return "Fat Burn";
    if (bpm < 155) return "Cardio";
    if (bpm < 175) return "Hard";
    return "Peak";
  };

  return (
    <div className="bg-gray-900 rounded-xl p-3 flex items-center gap-3">
      {/* Animated heart */}
      <div className={`text-2xl ${heartRate ? "animate-pulse" : ""}`}>
        &#x2764;&#xFE0F;
      </div>

      {heartRate ? (
        <div className="flex items-baseline gap-2">
          <span className={`text-3xl font-bold font-mono ${getZoneColor(heartRate)}`}>
            {Math.round(heartRate)}
          </span>
          <span className="text-xs text-gray-400">bpm</span>
          <span className={`text-xs font-medium ml-1 ${getZoneColor(heartRate)}`}>
            {getZoneLabel(heartRate)}
          </span>
        </div>
      ) : (
        <span className="text-sm text-gray-400 animate-pulse">Connecting...</span>
      )}
    </div>
  );
}
