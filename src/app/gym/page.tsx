"use client";

import { useState, useRef, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { isNativeCamera, takePhotoNative, hapticImpact } from "@/lib/camera";
import { PlanEditor, type TranscribedPlan } from "@/components/PlanEditor";

export default function GymMode() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [capturedFile, setCapturedFile] = useState<File | null>(null);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [plan, setPlan] = useState<TranscribedPlan | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hasNativeCamera, setHasNativeCamera] = useState(false);

  useEffect(() => {
    isNativeCamera().then(setHasNativeCamera);
  }, []);

  const handleNativeCapture = async () => {
    hapticImpact("light");
    const file = await takePhotoNative();
    if (file) {
      setCapturedFile(file);
      const reader = new FileReader();
      reader.onload = (ev) => setPreview(ev.target?.result as string);
      reader.readAsDataURL(file);
      setError(null);
      setPlan(null);
    }
  };

  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setCapturedFile(file);
    const reader = new FileReader();
    reader.onload = (ev) => {
      setPreview(ev.target?.result as string);
    };
    reader.readAsDataURL(file);
    setError(null);
    setPlan(null);
  };

  const handleCaptureClick = () => {
    if (hasNativeCamera) {
      handleNativeCapture();
    } else {
      fileInputRef.current?.click();
    }
  };

  const transcribe = async () => {
    const file = capturedFile || fileInputRef.current?.files?.[0];
    if (!file) return;

    setIsTranscribing(true);
    setError(null);
    hapticImpact("light");

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
      hapticImpact("medium");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to transcribe");
    } finally {
      setIsTranscribing(false);
    }
  };

  const startWorkout = async () => {
    if (!plan) return;
    hapticImpact("heavy");

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
              onClick={handleCaptureClick}
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
                    {hasNativeCamera
                      ? "Opens your camera for a clear shot"
                      : "Take a clear photo of the workout plan"}
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
                    setCapturedFile(null);
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

        {/* Transcribed Plan Editor */}
        {plan && (
          <PlanEditor
            plan={plan}
            onChange={setPlan}
            onStart={startWorkout}
            onRescan={() => setPlan(null)}
          />
        )}
      </div>
    </main>
  );
}
