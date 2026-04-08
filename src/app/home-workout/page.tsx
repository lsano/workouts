"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

interface HiitTemplate {
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

const EQUIPMENT_OPTIONS = [
  { value: "kettlebell", label: "Kettlebell", icon: "\u{1F3CB}" },
  { value: "dumbbell", label: "Dumbbell", icon: "\u{1F4AA}" },
  { value: "bodyweight", label: "Bodyweight", icon: "\u{1F9CD}" },
  { value: "band", label: "Band", icon: "\u{1F7E1}" },
];

const STYLE_OPTIONS = [
  { value: "", label: "All Styles" },
  { value: "tabata", label: "Tabata" },
  { value: "emom", label: "EMOM" },
  { value: "amrap", label: "AMRAP" },
  { value: "circuit", label: "Circuit" },
  { value: "ladder", label: "Ladder" },
];

const DIFFICULTY_OPTIONS = [
  { value: "", label: "All Levels" },
  { value: "beginner", label: "Beginner" },
  { value: "intermediate", label: "Intermediate" },
  { value: "advanced", label: "Advanced" },
];

export default function HomeWorkout() {
  const router = useRouter();
  const [templates, setTemplates] = useState<HiitTemplate[]>([]);
  const [equipment, setEquipment] = useState<string[]>([]);
  const [style, setStyle] = useState("");
  const [difficulty, setDifficulty] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchTemplates();
  }, [equipment, style, difficulty]);

  const fetchTemplates = async () => {
    setLoading(true);
    const params = new URLSearchParams();
    if (equipment.length === 1) params.set("equipment", equipment[0]);
    if (style) params.set("style", style);
    if (difficulty) params.set("difficulty", difficulty);

    const res = await fetch(`/api/templates?${params}`);
    const data = await res.json();

    // Client-side filter for multiple equipment selections
    let filtered = data;
    if (equipment.length > 1) {
      filtered = data.filter((t: HiitTemplate) =>
        t.equipment.some((e: string) => equipment.includes(e))
      );
    }

    setTemplates(filtered);
    setLoading(false);
  };

  const toggleEquipment = (eq: string) => {
    setEquipment((prev) =>
      prev.includes(eq) ? prev.filter((e) => e !== eq) : [...prev, eq]
    );
  };

  const startTemplate = async (template: HiitTemplate) => {
    const res = await fetch("/api/workouts", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mode: "home",
        name: template.name,
        sections: [
          {
            name: template.name,
            section_type: template.style,
            work_seconds: template.work_seconds,
            rest_seconds: template.rest_seconds,
            rounds: template.rounds,
            exercises: template.exercises.map((name) => ({
              exercise_name: name,
              sets: Array.from(
                { length: template.style === "amrap" ? 1 : template.rounds },
                () => ({})
              ),
            })),
          },
        ],
      }),
    });

    if (res.ok) {
      const { id } = await res.json();
      router.push(`/workout/${id}`);
    }
  };

  const formatTime = (seconds: number) => {
    if (seconds >= 60) {
      const m = Math.floor(seconds / 60);
      const s = seconds % 60;
      return s > 0 ? `${m}m ${s}s` : `${m}m`;
    }
    return `${seconds}s`;
  };

  const estimateDuration = (t: HiitTemplate) => {
    const total = (t.work_seconds + t.rest_seconds) * t.rounds * (t.style === "amrap" ? 1 : t.exercises.length);
    return Math.ceil(total / 60);
  };

  return (
    <main className="flex-1 flex flex-col max-w-lg mx-auto w-full">
      {/* Header */}
      <div className="p-4 border-b border-gray-200 dark:border-gray-800">
        <div className="flex items-center gap-3 mb-3">
          <Link href="/" className="text-2xl">&#x2190;</Link>
          <h1 className="text-xl font-bold">Home Workouts</h1>
        </div>

        {/* Equipment filter */}
        <div className="mb-3">
          <p className="text-xs text-gray-500 font-medium mb-2 uppercase tracking-wider">My Equipment</p>
          <div className="flex gap-2 flex-wrap">
            {EQUIPMENT_OPTIONS.map((eq) => (
              <button
                key={eq.value}
                onClick={() => toggleEquipment(eq.value)}
                className={`px-3 py-2 rounded-xl text-sm font-medium transition-colors ${
                  equipment.includes(eq.value)
                    ? "bg-orange-500 text-white"
                    : "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400"
                }`}
              >
                {eq.icon} {eq.label}
              </button>
            ))}
          </div>
        </div>

        {/* Style & Difficulty filters */}
        <div className="flex gap-2">
          <select
            value={style}
            onChange={(e) => setStyle(e.target.value)}
            className="flex-1 px-3 py-2 rounded-xl bg-gray-100 dark:bg-gray-800 text-sm border-0"
          >
            {STYLE_OPTIONS.map((s) => (
              <option key={s.value} value={s.value}>{s.label}</option>
            ))}
          </select>
          <select
            value={difficulty}
            onChange={(e) => setDifficulty(e.target.value)}
            className="flex-1 px-3 py-2 rounded-xl bg-gray-100 dark:bg-gray-800 text-sm border-0"
          >
            {DIFFICULTY_OPTIONS.map((d) => (
              <option key={d.value} value={d.value}>{d.label}</option>
            ))}
          </select>
        </div>
      </div>

      {/* Templates list */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {loading ? (
          <div className="text-center py-8 text-gray-500 animate-pulse">
            Loading workouts...
          </div>
        ) : templates.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-gray-500">No workouts match your filters</p>
            <button
              onClick={() => {
                setEquipment([]);
                setStyle("");
                setDifficulty("");
              }}
              className="text-blue-500 text-sm mt-2"
            >
              Clear filters
            </button>
          </div>
        ) : (
          templates.map((template) => (
            <div
              key={template.id}
              className="bg-white dark:bg-gray-800 rounded-xl p-4 shadow-sm"
            >
              <div className="flex items-start justify-between mb-2">
                <h3 className="font-semibold text-base">{template.name}</h3>
                <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${
                  template.difficulty === "beginner"
                    ? "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
                    : template.difficulty === "intermediate"
                    ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300"
                    : "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300"
                }`}>
                  {template.difficulty}
                </span>
              </div>

              <p className="text-sm text-gray-500 dark:text-gray-400 mb-3">
                {template.description}
              </p>

              {/* Workout details */}
              <div className="flex flex-wrap gap-2 mb-3">
                <span className="text-xs px-2 py-1 rounded-full bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400">
                  {template.style.toUpperCase()}
                </span>
                <span className="text-xs px-2 py-1 rounded-full bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400">
                  {formatTime(template.work_seconds)} / {formatTime(template.rest_seconds)}
                </span>
                <span className="text-xs px-2 py-1 rounded-full bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400">
                  {template.rounds} rounds
                </span>
                <span className="text-xs px-2 py-1 rounded-full bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400">
                  ~{estimateDuration(template)} min
                </span>
              </div>

              {/* Equipment */}
              <div className="flex flex-wrap gap-1 mb-3">
                {template.equipment.map((eq) => (
                  <span key={eq} className="text-xs px-2 py-0.5 rounded bg-orange-50 dark:bg-orange-900/20 text-orange-600 dark:text-orange-400">
                    {eq}
                  </span>
                ))}
              </div>

              {/* Exercises */}
              <div className="mb-3">
                <p className="text-xs text-gray-500 font-medium mb-1">Exercises:</p>
                <p className="text-sm">{template.exercises.join(" \u2022 ")}</p>
              </div>

              {/* Source */}
              <p className="text-xs text-gray-400 mb-3 italic">
                Based on: {template.source}
              </p>

              <button
                onClick={() => startTemplate(template)}
                className="w-full py-3 rounded-xl font-semibold bg-orange-500 text-white active:bg-orange-600"
              >
                Start Workout
              </button>
            </div>
          ))
        )}
      </div>
    </main>
  );
}
