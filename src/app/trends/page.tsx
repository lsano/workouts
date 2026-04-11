"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import Link from "next/link";
import {
  type ExerciseType,
  type TrendAggregate,
  type TrendPeriod,
  EXERCISE_TYPE_LABELS,
} from "@/lib/sensor-types";

export default function TrendsPage() {
  const [period, setPeriod] = useState<TrendPeriod>("30d");
  const [trends, setTrends] = useState<Record<string, TrendAggregate[]>>({});
  const [selectedExercise, setSelectedExercise] = useState<ExerciseType | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchTrends();
  }, [period]);

  const fetchTrends = async () => {
    setLoading(true);
    try {
      const res = await fetch(`/api/trends?period=${period}`);
      const data = await res.json();
      setTrends(data);
    } catch {
      // Use demo data in case of error
      setTrends(generateDemoTrends(period));
    }
    setLoading(false);
  };

  const exerciseTypes = Object.keys(trends) as ExerciseType[];
  const selectedTrend = selectedExercise ? trends[selectedExercise] || [] : null;

  // Calculate overall stats
  const totalWorkouts = new Set(
    Object.values(trends)
      .flat()
      .map((t) => t.dateBucket)
  ).size;
  const totalSets = Object.values(trends)
    .flat()
    .reduce((sum, t) => sum + t.totalSets, 0);
  const totalReps = Object.values(trends)
    .flat()
    .reduce((sum, t) => sum + t.totalReps, 0);

  return (
    <main className="flex-1 flex flex-col p-4 max-w-lg mx-auto w-full">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <Link href="/" className="text-gray-400 hover:text-white">&larr;</Link>
        <h1 className="text-2xl font-bold">Trends</h1>
      </div>

      {/* Period Selector */}
      <div className="flex gap-1 mb-6 p-1 bg-gray-800 rounded-xl">
        {(["7d", "30d", "90d"] as TrendPeriod[]).map((p) => (
          <button
            key={p}
            onClick={() => setPeriod(p)}
            className={`flex-1 py-2 text-sm font-medium rounded-lg transition-colors ${
              period === p
                ? "bg-blue-600 text-white"
                : "text-gray-400 hover:text-gray-300"
            }`}
          >
            {p === "7d" ? "7 Days" : p === "30d" ? "30 Days" : "90 Days"}
          </button>
        ))}
      </div>

      {/* Overall Stats */}
      <div className="grid grid-cols-3 gap-3 mb-6">
        <div className="p-4 rounded-xl bg-gray-800 border border-gray-700 text-center">
          <div className="text-2xl font-bold text-white">{totalWorkouts}</div>
          <div className="text-xs text-gray-400">Workouts</div>
        </div>
        <div className="p-4 rounded-xl bg-gray-800 border border-gray-700 text-center">
          <div className="text-2xl font-bold text-white">{totalSets}</div>
          <div className="text-xs text-gray-400">Total Sets</div>
        </div>
        <div className="p-4 rounded-xl bg-gray-800 border border-gray-700 text-center">
          <div className="text-2xl font-bold text-white">{totalReps}</div>
          <div className="text-xs text-gray-400">Total Reps</div>
        </div>
      </div>

      {/* Exercise Selector */}
      {!selectedExercise ? (
        <section>
          <h2 className="text-sm font-semibold text-gray-400 uppercase mb-3">
            Exercises
          </h2>
          {loading ? (
            <div className="text-center text-gray-500 py-8">Loading...</div>
          ) : exerciseTypes.length === 0 ? (
            <div className="text-center text-gray-500 py-12">
              <div className="text-4xl mb-3">&#x1F4C8;</div>
              <p>No trend data yet.</p>
              <p className="text-sm mt-1">
                Complete some auto-detected workouts to see trends here.
              </p>
              <Link
                href="/live-workout"
                className="inline-block mt-4 px-4 py-2 rounded-xl bg-green-600 text-white font-medium"
              >
                Start a Workout
              </Link>
            </div>
          ) : (
            <div className="space-y-2">
              {exerciseTypes.map((type) => {
                const data = trends[type] || [];
                const latestSets = data.reduce((sum, t) => sum + t.totalSets, 0);
                const latestReps = data.reduce((sum, t) => sum + t.totalReps, 0);
                const avgQuality =
                  data.filter((t) => t.avgQuality).length > 0
                    ? data
                        .filter((t) => t.avgQuality)
                        .reduce((sum, t) => sum + (t.avgQuality ?? 0), 0) /
                      data.filter((t) => t.avgQuality).length
                    : null;

                return (
                  <button
                    key={type}
                    onClick={() => setSelectedExercise(type)}
                    className="w-full p-4 rounded-xl bg-gray-800 border border-gray-700 text-left active:scale-[0.99] transition-transform"
                  >
                    <div className="flex items-center justify-between">
                      <span className="font-semibold">
                        {EXERCISE_TYPE_LABELS[type] || type}
                      </span>
                      <span className="text-gray-400 text-sm">&rarr;</span>
                    </div>
                    <div className="flex gap-4 mt-2 text-sm text-gray-400">
                      <span>{latestSets} sets</span>
                      <span>{latestReps} reps</span>
                      {avgQuality !== null && (
                        <span>
                          Quality: {Math.round(avgQuality * 100)}%
                        </span>
                      )}
                    </div>
                    {/* Mini sparkline */}
                    {data.length > 1 && (
                      <div className="mt-2">
                        <MiniChart
                          data={data.map((d) => d.totalReps)}
                          color="#3b82f6"
                        />
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          )}
        </section>
      ) : (
        /* Exercise Detail View */
        <section>
          <button
            onClick={() => setSelectedExercise(null)}
            className="text-blue-400 text-sm mb-4 hover:text-blue-300"
          >
            &larr; All Exercises
          </button>

          <h2 className="text-xl font-bold mb-4">
            {EXERCISE_TYPE_LABELS[selectedExercise]}
          </h2>

          {selectedTrend && selectedTrend.length > 0 ? (
            <>
              {/* Volume Chart */}
              <TrendChart
                title="Volume (Reps)"
                data={selectedTrend}
                valueKey="totalReps"
                color="#3b82f6"
              />

              {/* Reps Per Set */}
              <TrendChart
                title="Avg Reps/Set"
                data={selectedTrend}
                valueKey="avgRepsPerSet"
                color="#22c55e"
              />

              {/* Tempo */}
              <TrendChart
                title="Avg Tempo (ms)"
                data={selectedTrend}
                valueKey="avgTempo"
                color="#f59e0b"
              />

              {/* Symmetry */}
              <TrendChart
                title="Symmetry"
                data={selectedTrend}
                valueKey="avgSymmetry"
                color="#a855f7"
                isPercentage
              />

              {/* Quality */}
              <TrendChart
                title="Quality Score"
                data={selectedTrend}
                valueKey="avgQuality"
                color="#ec4899"
                isPercentage
              />

              {/* Insights */}
              <InsightsSection
                exerciseType={selectedExercise}
                data={selectedTrend}
              />
            </>
          ) : (
            <p className="text-center text-gray-500 py-8">
              No data for this period
            </p>
          )}
        </section>
      )}
    </main>
  );
}

// --- Mini Sparkline ---

function MiniChart({ data, color }: { data: number[]; color: string }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || data.length < 2) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = canvas.offsetWidth * dpr;
    canvas.height = canvas.offsetHeight * dpr;
    ctx.scale(dpr, dpr);

    const w = canvas.offsetWidth;
    const h = canvas.offsetHeight;
    const max = Math.max(...data);
    const min = Math.min(...data);
    const range = max - min || 1;

    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    data.forEach((val, i) => {
      const x = (i / (data.length - 1)) * w;
      const y = h - ((val - min) / range) * (h * 0.8) - h * 0.1;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }, [data, color]);

  return <canvas ref={canvasRef} className="w-full" style={{ height: "24px" }} />;
}

// --- Trend Chart ---

function TrendChart({
  title,
  data,
  valueKey,
  color,
  isPercentage = false,
}: {
  title: string;
  data: TrendAggregate[];
  valueKey: keyof TrendAggregate;
  color: string;
  isPercentage?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const values = data
    .map((d) => d[valueKey] as number | undefined)
    .filter((v): v is number => v !== undefined && v !== null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || values.length < 1) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    const w = rect.width;
    const h = rect.height;
    const padding = { top: 8, bottom: 20, left: 8, right: 8 };
    const chartW = w - padding.left - padding.right;
    const chartH = h - padding.top - padding.bottom;

    const max = Math.max(...values);
    const min = Math.min(...values);
    const range = max - min || 1;

    ctx.clearRect(0, 0, w, h);

    // Grid
    ctx.strokeStyle = "#333";
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= 3; i++) {
      const y = padding.top + (chartH / 3) * i;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(w - padding.right, y);
      ctx.stroke();
    }

    // Bars
    if (values.length > 0) {
      const barWidth = Math.max(4, chartW / values.length - 2);
      values.forEach((val, i) => {
        const x = padding.left + (i / Math.max(values.length - 1, 1)) * chartW - barWidth / 2;
        const barH = ((val - min) / range) * chartH * 0.85 + chartH * 0.05;
        const y = padding.top + chartH - barH;

        ctx.fillStyle = color + "40";
        ctx.fillRect(x, y, barWidth, barH);
        ctx.fillStyle = color;
        ctx.fillRect(x, y, barWidth, 2);
      });
    }

    // Line overlay
    if (values.length > 1) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.beginPath();
      values.forEach((val, i) => {
        const x = padding.left + (i / (values.length - 1)) * chartW;
        const y = padding.top + chartH - ((val - min) / range) * chartH * 0.85 - chartH * 0.05;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.stroke();
    }

    // Date labels
    if (data.length > 0) {
      ctx.fillStyle = "#666";
      ctx.font = "10px system-ui";
      ctx.textAlign = "center";
      const first = data[0].dateBucket.slice(5);
      const last = data[data.length - 1].dateBucket.slice(5);
      ctx.fillText(first, padding.left + 20, h - 4);
      ctx.fillText(last, w - padding.right - 20, h - 4);
    }
  }, [data, values, valueKey, color]);

  const latest = values.length > 0 ? values[values.length - 1] : null;
  const first = values.length > 1 ? values[0] : null;
  const change =
    latest !== null && first !== null && first !== 0
      ? ((latest - first) / first) * 100
      : null;

  return (
    <div className="mb-5">
      <div className="flex items-center justify-between mb-1">
        <h3 className="text-sm font-medium text-gray-300">{title}</h3>
        <div className="flex items-center gap-2 text-sm">
          {latest !== null && (
            <span className="font-semibold" style={{ color }}>
              {isPercentage
                ? `${Math.round(latest * 100)}%`
                : Math.round(latest)}
            </span>
          )}
          {change !== null && (
            <span
              className={`text-xs ${
                change > 0
                  ? "text-green-400"
                  : change < 0
                    ? "text-red-400"
                    : "text-gray-500"
              }`}
            >
              {change > 0 ? "+" : ""}
              {Math.round(change)}%
            </span>
          )}
        </div>
      </div>
      <canvas
        ref={canvasRef}
        className="w-full rounded-lg bg-gray-900/50"
        style={{ height: "100px" }}
      />
    </div>
  );
}

// --- Insights ---

function InsightsSection({
  exerciseType,
  data,
}: {
  exerciseType: ExerciseType;
  data: TrendAggregate[];
}) {
  const insights: string[] = [];
  const name = EXERCISE_TYPE_LABELS[exerciseType];

  if (data.length >= 2) {
    const first = data[0];
    const last = data[data.length - 1];

    // Symmetry trend
    if (first.avgSymmetry && last.avgSymmetry) {
      const diff = last.avgSymmetry - first.avgSymmetry;
      if (diff > 0.05) {
        insights.push(
          `Your ${name} symmetry improved by ${Math.round(diff * 100)}% over this period.`
        );
      } else if (diff < -0.05) {
        insights.push(
          `Your ${name} symmetry decreased by ${Math.round(Math.abs(diff) * 100)}%. Consider focusing on balance.`
        );
      }
    }

    // Volume trend
    if (last.totalReps > first.totalReps * 1.1) {
      insights.push(
        `Your ${name} volume increased - great progress!`
      );
    }

    // Quality trend
    if (first.avgQuality && last.avgQuality) {
      if (last.avgQuality > first.avgQuality + 0.05) {
        insights.push(
          `Your ${name} quality score is trending up. Nice consistency!`
        );
      } else if (last.avgQuality < first.avgQuality - 0.1) {
        insights.push(
          `Your ${name} quality has dipped. Check form and consider reducing volume.`
        );
      }
    }
  }

  if (insights.length === 0) {
    insights.push(
      `Keep training ${name} to build meaningful trend data.`
    );
  }

  return (
    <div className="mt-4">
      <h3 className="text-sm font-semibold text-gray-400 uppercase mb-2">
        Insights
      </h3>
      <div className="space-y-2">
        {insights.map((insight, i) => (
          <div
            key={i}
            className="p-3 rounded-xl bg-blue-600/10 border border-blue-600/20 text-sm text-blue-200"
          >
            {insight}
          </div>
        ))}
      </div>
    </div>
  );
}

// --- Demo Data Generator ---

function generateDemoTrends(
  period: TrendPeriod
): Record<string, TrendAggregate[]> {
  const days = period === "7d" ? 7 : period === "30d" ? 30 : 90;
  const exercises: ExerciseType[] = [
    "jump_rope",
    "alternating_lunges",
    "pogo_hops",
    "step_ups",
  ];

  const result: Record<string, TrendAggregate[]> = {};

  for (const exercise of exercises) {
    const data: TrendAggregate[] = [];
    for (let i = 0; i < days; i += Math.ceil(days / 10)) {
      const date = new Date();
      date.setDate(date.getDate() - (days - i));
      const baseReps = 40 + Math.random() * 20;
      const baseSets = 3 + Math.floor(Math.random() * 2);

      data.push({
        id: `demo-${exercise}-${i}`,
        exerciseType: exercise,
        dateBucket: date.toISOString().split("T")[0],
        totalSessions: 1,
        totalSets: baseSets,
        totalReps: Math.round(baseReps + i * 0.5),
        avgRepsPerSet: Math.round(baseReps / baseSets),
        avgTempo: 700 + Math.random() * 200 - i * 2,
        avgSymmetry: 0.7 + Math.random() * 0.15 + i * 0.002,
        avgQuality: 0.65 + Math.random() * 0.15 + i * 0.003,
        avgFatigueDropoff: 0.1 + Math.random() * 0.05,
      });
    }
    result[exercise] = data;
  }

  return result;
}
