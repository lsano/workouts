"use client";

import { useState, useEffect } from "react";
import {
  checkHealthKitAvailable,
  requestHealthPermissions,
  getHealthSummary,
} from "@/lib/health/health-service";

interface HealthData {
  restingHeartRate?: number;
  activeCaloriesToday?: number;
  workoutsThisWeek?: number;
  bodyMass?: number;
}

export function HealthDashboard() {
  const [available, setAvailable] = useState(false);
  const [permitted, setPermitted] = useState(false);
  const [data, setData] = useState<HealthData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    checkHealth();
  }, []);

  async function checkHealth() {
    const avail = await checkHealthKitAvailable();
    setAvailable(avail);

    if (avail) {
      // Try loading data (will succeed if permissions already granted)
      const summary = await getHealthSummary();
      if (summary && Object.keys(summary).length > 0) {
        setPermitted(true);
        setData(summary);
      }
    }
    setLoading(false);
  }

  async function handleConnect() {
    const granted = await requestHealthPermissions();
    setPermitted(granted);
    if (granted) {
      const summary = await getHealthSummary();
      setData(summary);
    }
  }

  if (loading || !available) return null;

  if (!permitted) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-2xl p-4 shadow-sm">
        <div className="flex items-center gap-3">
          <div className="text-3xl">&#x2764;&#xFE0F;</div>
          <div className="flex-1">
            <h3 className="font-semibold">Connect Health</h3>
            <p className="text-xs text-gray-500">
              Sync workouts to Apple Health and track heart rate
            </p>
          </div>
          <button
            onClick={handleConnect}
            className="px-4 py-2 rounded-xl bg-red-500 text-white text-sm font-medium"
          >
            Connect
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white dark:bg-gray-800 rounded-2xl p-4 shadow-sm">
      <h3 className="font-semibold text-sm text-gray-500 mb-3 uppercase tracking-wider">
        Health
      </h3>
      <div className="grid grid-cols-2 gap-3">
        {data?.restingHeartRate != null && (
          <div className="bg-red-50 dark:bg-red-900/20 rounded-xl p-3">
            <div className="text-xs text-gray-500 mb-1">Resting HR</div>
            <div className="flex items-baseline gap-1">
              <span className="text-2xl font-bold text-red-600 dark:text-red-400">
                {Math.round(data.restingHeartRate)}
              </span>
              <span className="text-xs text-gray-500">bpm</span>
            </div>
          </div>
        )}

        {data?.activeCaloriesToday != null && (
          <div className="bg-orange-50 dark:bg-orange-900/20 rounded-xl p-3">
            <div className="text-xs text-gray-500 mb-1">Active Cal</div>
            <div className="flex items-baseline gap-1">
              <span className="text-2xl font-bold text-orange-600 dark:text-orange-400">
                {Math.round(data.activeCaloriesToday)}
              </span>
              <span className="text-xs text-gray-500">kcal</span>
            </div>
          </div>
        )}

        {data?.workoutsThisWeek != null && (
          <div className="bg-green-50 dark:bg-green-900/20 rounded-xl p-3">
            <div className="text-xs text-gray-500 mb-1">This Week</div>
            <div className="flex items-baseline gap-1">
              <span className="text-2xl font-bold text-green-600 dark:text-green-400">
                {data.workoutsThisWeek}
              </span>
              <span className="text-xs text-gray-500">workouts</span>
            </div>
          </div>
        )}

        {data?.bodyMass != null && (
          <div className="bg-blue-50 dark:bg-blue-900/20 rounded-xl p-3">
            <div className="text-xs text-gray-500 mb-1">Weight</div>
            <div className="flex items-baseline gap-1">
              <span className="text-2xl font-bold text-blue-600 dark:text-blue-400">
                {Math.round(data.bodyMass)}
              </span>
              <span className="text-xs text-gray-500">lbs</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
