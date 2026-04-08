"use client";

import { useState, useRef } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

interface TranscribedExercise {
  exercise_name: string;
  notes?: string | null;
}

interface TranscribedSection {
  name: string;
  section_type: string;
  work_seconds?: number | null;
  rest_seconds?: number | null;
  rounds?: number | null;
  exercises: TranscribedExercise[];
}

interface TranscribedPlan {
  name?: string;
  sections: TranscribedSection[];
}

export default function GymMode() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [plan, setPlan] = useState<TranscribedPlan | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (ev) => {
      setPreview(ev.target?.result as string);
    };
    reader.readAsDataURL(file);
    setError(null);
    setPlan(null);
  };

  const transcribe = async () => {
    const file = fileInputRef.current?.files?.[0];
    if (!file) return;

    setIsTranscribing(true);
    setError(null);

    try {
      const formData = new FormData();
      formData.append("image", file);

      const res = await fetch("/api/transcribe", {
        method: "POST",
        body: formData,
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Transcription failed");
      }

      const data = await res.json();
      setPlan(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to transcribe");
    } finally {
      setIsTranscribing(false);
    }
  };

  const startWorkout = async () => {
    if (!plan) return;

    const res = await fetch("/api/workouts", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mode: "gym",
        name: plan.name || `Gym Workout ${new Date().toLocaleDateString()}`,
        raw_transcription: JSON.stringify(plan),
        structured_plan: plan,
        sections: plan.sections.map((s) => ({
          name: s.name,
          section_type: s.section_type,
          work_seconds: s.work_seconds,
          rest_seconds: s.rest_seconds,
          rounds: s.rounds,
          exercises: s.exercises.map((e) => ({
            exercise_name: e.exercise_name,
            notes: e.notes,
            sets: Array.from({ length: s.rounds || 4 }, () => ({})),
          })),
        })),
      }),
    });

    if (res.ok) {
      const { id } = await res.json();
      router.push(`/workout/${id}`);
    }
  };

  return (
    <main className="flex-1 flex flex-col max-w-lg mx-auto w-full">
      {/* Header */}
      <div className="flex items-center gap-3 p-4 border-b border-gray-200 dark:border-gray-800">
        <Link href="/" className="text-2xl">&#x2190;</Link>
        <h1 className="text-xl font-bold">Gym Mode</h1>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Camera/Upload Section */}
        {!plan && (
          <div className="space-y-4">
            <div
              onClick={() => fileInputRef.current?.click()}
              className="border-2 border-dashed border-gray-300 dark:border-gray-700 rounded-2xl p-8 text-center cursor-pointer active:bg-gray-50 dark:active:bg-gray-900"
            >
              {preview ? (
                <img
                  src={preview}
                  alt="Whiteboard preview"
                  className="max-h-64 mx-auto rounded-lg"
                />
              ) : (
                <>
                  <div className="text-5xl mb-3">&#x1F4F7;</div>
                  <p className="font-semibold">Tap to photograph the whiteboard</p>
                  <p className="text-sm text-gray-500 mt-1">
                    Take a clear photo of the workout plan
                  </p>
                </>
              )}
            </div>

            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              capture="environment"
              onChange={handleImageSelect}
              className="hidden"
            />

            {preview && (
              <div className="flex gap-3">
                <button
                  onClick={() => {
                    setPreview(null);
                    if (fileInputRef.current) fileInputRef.current.value = "";
                  }}
                  className="flex-1 py-3 rounded-xl font-semibold bg-gray-200 dark:bg-gray-700"
                >
                  Retake
                </button>
                <button
                  onClick={transcribe}
                  disabled={isTranscribing}
                  className="flex-1 py-3 rounded-xl font-semibold bg-blue-500 text-white disabled:opacity-50"
                >
                  {isTranscribing ? "Transcribing..." : "Transcribe"}
                </button>
              </div>
            )}

            {error && (
              <div className="p-3 rounded-xl bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 text-sm">
                {error}
              </div>
            )}

            {/* Manual entry option */}
            <div className="text-center">
              <p className="text-sm text-gray-500 mb-2">or use demo data</p>
              <button
                onClick={async () => {
                  setIsTranscribing(true);
                  const res = await fetch("/api/transcribe", { method: "POST", body: new FormData() });
                  const data = await res.json();
                  setPlan(data);
                  setIsTranscribing(false);
                }}
                className="text-blue-500 font-medium text-sm"
              >
                Load example workout
              </button>
            </div>
          </div>
        )}

        {/* Transcribed Plan Preview */}
        {plan && (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold">{plan.name || "Workout Plan"}</h2>
              <button
                onClick={() => setPlan(null)}
                className="text-sm text-blue-500 font-medium"
              >
                Re-scan
              </button>
            </div>

            {plan.sections.map((section, i) => (
              <div
                key={i}
                className="bg-white dark:bg-gray-800 rounded-xl p-4 shadow-sm"
              >
                <div className="flex items-center justify-between mb-2">
                  <h3 className="font-semibold">{section.name}</h3>
                  <span className="text-xs px-2 py-1 rounded-full bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300">
                    {section.section_type}
                  </span>
                </div>

                {(section.work_seconds || section.rest_seconds || section.rounds) && (
                  <div className="flex gap-3 mb-2 text-xs text-gray-500">
                    {section.work_seconds && <span>Work: {section.work_seconds}s</span>}
                    {section.rest_seconds && <span>Rest: {section.rest_seconds}s</span>}
                    {section.rounds && <span>Rounds: {section.rounds}</span>}
                  </div>
                )}

                <ul className="space-y-1">
                  {section.exercises.map((ex, j) => (
                    <li key={j} className="flex items-start gap-2 text-sm">
                      <span className="text-blue-500 mt-0.5">&#x2022;</span>
                      <span>
                        {ex.exercise_name}
                        {ex.notes && (
                          <span className="text-gray-400 ml-1">({ex.notes})</span>
                        )}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}

            <button
              onClick={startWorkout}
              className="w-full py-4 rounded-2xl font-bold text-lg bg-green-500 text-white active:bg-green-600 shadow-lg"
            >
              Start Workout
            </button>
          </div>
        )}
      </div>
    </main>
  );
}
