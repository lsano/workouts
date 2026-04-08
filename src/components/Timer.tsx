"use client";

import { useState, useEffect, useCallback, useRef } from "react";

interface TimerProps {
  workSeconds: number;
  restSeconds: number;
  rounds: number;
  onComplete?: () => void;
}

export default function Timer({ workSeconds, restSeconds, rounds, onComplete }: TimerProps) {
  const [isRunning, setIsRunning] = useState(false);
  const [currentRound, setCurrentRound] = useState(1);
  const [phase, setPhase] = useState<"work" | "rest">("work");
  const [timeLeft, setTimeLeft] = useState(workSeconds);
  const [isFinished, setIsFinished] = useState(false);
  const audioRef = useRef<AudioContext | null>(null);

  const playBeep = useCallback((frequency: number, duration: number) => {
    try {
      if (!audioRef.current) {
        audioRef.current = new AudioContext();
      }
      const ctx = audioRef.current;
      const oscillator = ctx.createOscillator();
      const gainNode = ctx.createGain();
      oscillator.connect(gainNode);
      gainNode.connect(ctx.destination);
      oscillator.frequency.value = frequency;
      gainNode.gain.value = 0.3;
      oscillator.start();
      oscillator.stop(ctx.currentTime + duration / 1000);
    } catch {
      // Audio not available
    }
  }, []);

  useEffect(() => {
    if (!isRunning || isFinished) return;

    const interval = setInterval(() => {
      setTimeLeft((prev) => {
        if (prev <= 1) {
          if (phase === "work") {
            if (restSeconds > 0) {
              playBeep(440, 300);
              setPhase("rest");
              return restSeconds;
            } else if (currentRound < rounds) {
              playBeep(880, 200);
              setCurrentRound((r) => r + 1);
              return workSeconds;
            } else {
              playBeep(880, 500);
              setIsRunning(false);
              setIsFinished(true);
              onComplete?.();
              return 0;
            }
          } else {
            // rest phase ended
            if (currentRound < rounds) {
              playBeep(880, 200);
              setCurrentRound((r) => r + 1);
              setPhase("work");
              return workSeconds;
            } else {
              playBeep(880, 500);
              setIsRunning(false);
              setIsFinished(true);
              onComplete?.();
              return 0;
            }
          }
        }
        if (prev <= 4) playBeep(660, 100);
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [isRunning, phase, currentRound, rounds, workSeconds, restSeconds, isFinished, onComplete, playBeep]);

  const reset = () => {
    setIsRunning(false);
    setCurrentRound(1);
    setPhase("work");
    setTimeLeft(workSeconds);
    setIsFinished(false);
  };

  const formatTime = (seconds: number) => {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${s.toString().padStart(2, "0")}`;
  };

  const totalTime = (workSeconds + restSeconds) * rounds;
  const elapsed =
    (currentRound - 1) * (workSeconds + restSeconds) +
    (phase === "work" ? workSeconds - timeLeft : workSeconds + restSeconds - timeLeft);
  const progress = (elapsed / totalTime) * 100;

  return (
    <div className={`rounded-2xl p-6 text-center ${phase === "work" ? "bg-red-500/10 border-2 border-red-500/30" : "bg-green-500/10 border-2 border-green-500/30"}`}>
      <div className="text-sm font-semibold uppercase tracking-wider mb-1 opacity-70">
        {isFinished ? "Complete!" : phase === "work" ? "Work" : "Rest"}
      </div>

      <div className="text-6xl font-mono font-bold mb-2">{formatTime(timeLeft)}</div>

      <div className="text-sm opacity-70 mb-4">
        Round {currentRound} of {rounds}
      </div>

      {/* Progress bar */}
      <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2 mb-4">
        <div
          className={`h-2 rounded-full transition-all ${phase === "work" ? "bg-red-500" : "bg-green-500"}`}
          style={{ width: `${Math.min(progress, 100)}%` }}
        />
      </div>

      <div className="flex gap-3 justify-center">
        {!isFinished && (
          <button
            onClick={() => setIsRunning(!isRunning)}
            className={`px-6 py-3 rounded-xl font-semibold text-white ${
              isRunning ? "bg-yellow-500 active:bg-yellow-600" : "bg-blue-500 active:bg-blue-600"
            }`}
          >
            {isRunning ? "Pause" : "Start"}
          </button>
        )}
        <button
          onClick={reset}
          className="px-6 py-3 rounded-xl font-semibold bg-gray-200 dark:bg-gray-700 active:bg-gray-300"
        >
          Reset
        </button>
      </div>
    </div>
  );
}
