"use client";

import { useState, useEffect } from "react";
import Link from "next/link";

interface Workout {
  id: string;
  mode: string;
  name?: string;
  date: string;
  status: string;
  duration_minutes?: number;
  created_at: string;
  completed_at?: string;
}

export default function History() {
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [filter, setFilter] = useState<string>("all");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchWorkouts();
  }, [filter]);

  const fetchWorkouts = async () => {
    setLoading(true);
    const params = new URLSearchParams();
    if (filter !== "all") params.set("mode", filter);

    const res = await fetch(`/api/workouts?${params}`);
    const data = await res.json();
    setWorkouts(data);
    setLoading(false);
  };

  const deleteWorkout = async (id: string) => {
    if (!confirm("Delete this workout?")) return;
    await fetch(`/api/workouts/${id}`, { method: "DELETE" });
    fetchWorkouts();
  };

  // Group by date
  const grouped = workouts.reduce<Record<string, Workout[]>>((acc, w) => {
    const date = w.date;
    if (!acc[date]) acc[date] = [];
    acc[date].push(w);
    return acc;
  }, {});

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr + "T00:00:00");
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    if (date.getTime() === today.getTime()) return "Today";
    if (date.getTime() === yesterday.getTime()) return "Yesterday";
    return date.toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
    });
  };

  // Stats
  const totalWorkouts = workouts.length;
  const completedWorkouts = workouts.filter((w) => w.status === "completed").length;
  const thisWeek = workouts.filter((w) => {
    const d = new Date(w.date);
    const now = new Date();
    const weekAgo = new Date(now);
    weekAgo.setDate(weekAgo.getDate() - 7);
    return d >= weekAgo;
  }).length;

  return (
    <main className="flex-1 flex flex-col max-w-lg mx-auto w-full">
      {/* Header */}
      <div className="p-4 border-b border-gray-200 dark:border-gray-800">
        <div className="flex items-center gap-3 mb-4">
          <Link href="/" className="text-2xl">&#x2190;</Link>
          <h1 className="text-xl font-bold">Workout History</h1>
        </div>

        {/* Quick stats */}
        <div className="grid grid-cols-3 gap-2 mb-4">
          <div className="bg-blue-50 dark:bg-blue-900/20 rounded-xl p-3 text-center">
            <div className="text-2xl font-bold text-blue-600 dark:text-blue-400">{totalWorkouts}</div>
            <div className="text-xs text-gray-500">Total</div>
          </div>
          <div className="bg-green-50 dark:bg-green-900/20 rounded-xl p-3 text-center">
            <div className="text-2xl font-bold text-green-600 dark:text-green-400">{completedWorkouts}</div>
            <div className="text-xs text-gray-500">Completed</div>
          </div>
          <div className="bg-orange-50 dark:bg-orange-900/20 rounded-xl p-3 text-center">
            <div className="text-2xl font-bold text-orange-600 dark:text-orange-400">{thisWeek}</div>
            <div className="text-xs text-gray-500">This Week</div>
          </div>
        </div>

        {/* Filter */}
        <div className="flex gap-2">
          {[
            { value: "all", label: "All" },
            { value: "sensor", label: "Auto" },
            { value: "gym", label: "Gym" },
            { value: "home", label: "Home" },
          ].map((f) => (
            <button
              key={f.value}
              onClick={() => setFilter(f.value)}
              className={`flex-1 py-2 rounded-xl text-sm font-medium transition-colors ${
                filter === f.value
                  ? "bg-gray-900 dark:bg-gray-100 text-white dark:text-gray-900"
                  : "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400"
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {/* Workout list */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {loading ? (
          <div className="text-center py-8 text-gray-500 animate-pulse">Loading...</div>
        ) : workouts.length === 0 ? (
          <div className="text-center py-12">
            <div className="text-5xl mb-3">&#x1F3CB;</div>
            <p className="text-gray-500">No workouts yet</p>
            <p className="text-sm text-gray-400 mt-1">Start your first workout!</p>
            <div className="flex gap-3 justify-center mt-4">
              <Link href="/live-workout" className="px-4 py-2 rounded-xl bg-emerald-500 text-white text-sm font-medium">
                Auto-Detect
              </Link>
              <Link href="/gym" className="px-4 py-2 rounded-xl bg-blue-500 text-white text-sm font-medium">
                Gym Mode
              </Link>
            </div>
          </div>
        ) : (
          Object.entries(grouped).map(([date, dayWorkouts]) => (
            <div key={date}>
              <h3 className="text-sm font-semibold text-gray-500 mb-2">{formatDate(date)}</h3>
              <div className="space-y-2">
                {dayWorkouts.map((w) => (
                  <div
                    key={w.id}
                    className="bg-white dark:bg-gray-800 rounded-xl p-4 shadow-sm"
                  >
                    <div className="flex items-start justify-between">
                      <Link href={`/workout/${w.id}`} className="flex-1">
                        <h4 className="font-semibold">{w.name || "Workout"}</h4>
                        <div className="flex items-center gap-2 mt-1">
                          <span className={`text-xs px-2 py-0.5 rounded-full ${
                            w.mode === "sensor"
                              ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-900 dark:text-emerald-300"
                              : w.mode === "gym"
                                ? "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
                                : "bg-orange-100 text-orange-700 dark:bg-orange-900 dark:text-orange-300"
                          }`}>
                            {w.mode === "sensor" ? "auto" : w.mode}
                          </span>
                          <span className={`text-xs px-2 py-0.5 rounded-full ${
                            w.status === "completed"
                              ? "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
                              : w.status === "in_progress"
                              ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300"
                              : "bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400"
                          }`}>
                            {w.status.replace("_", " ")}
                          </span>
                        </div>
                      </Link>
                      <button
                        onClick={(e) => {
                          e.preventDefault();
                          deleteWorkout(w.id);
                        }}
                        className="p-2 text-gray-400 active:text-red-500"
                      >
                        &#x1F5D1;
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))
        )}
      </div>
    </main>
  );
}
