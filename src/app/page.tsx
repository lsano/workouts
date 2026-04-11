import Link from "next/link";
import { HealthDashboard } from "@/components/HealthDashboard";

export default function Home() {
  return (
    <main className="flex-1 flex flex-col items-center justify-center p-6">
      <div className="w-full max-w-md space-y-8">
        <div className="text-center">
          <h1 className="text-4xl font-bold tracking-tight mb-2">WOD Tracker</h1>
          <p className="text-gray-500 dark:text-gray-400">
            Auto-detect exercises, count reps, and track progress with sensors
          </p>
        </div>

        {/* Health dashboard - shows when HealthKit is available */}
        <HealthDashboard />

        <div className="space-y-4">
          <Link
            href="/live-workout"
            className="block w-full p-6 rounded-2xl bg-gradient-to-br from-emerald-500 to-green-700 text-white shadow-lg active:scale-[0.98] transition-transform"
          >
            <div className="flex items-center gap-4">
              <div className="text-4xl">&#x1F3AF;</div>
              <div>
                <h2 className="text-xl font-bold">Auto-Detect</h2>
                <p className="text-emerald-100 text-sm mt-1">
                  Sensors detect exercises, count reps automatically
                </p>
              </div>
            </div>
          </Link>

          <Link
            href="/gym"
            className="block w-full p-6 rounded-2xl bg-gradient-to-br from-blue-500 to-blue-700 text-white shadow-lg active:scale-[0.98] transition-transform"
          >
            <div className="flex items-center gap-4">
              <div className="text-4xl">&#x1F4F7;</div>
              <div>
                <h2 className="text-xl font-bold">Gym Mode</h2>
                <p className="text-blue-100 text-sm mt-1">
                  Snap the whiteboard, track your sets
                </p>
              </div>
            </div>
          </Link>

          <Link
            href="/home-workout"
            className="block w-full p-6 rounded-2xl bg-gradient-to-br from-orange-500 to-red-600 text-white shadow-lg active:scale-[0.98] transition-transform"
          >
            <div className="flex items-center gap-4">
              <div className="text-4xl">&#x1F3E0;</div>
              <div>
                <h2 className="text-xl font-bold">Home Mode</h2>
                <p className="text-orange-100 text-sm mt-1">
                  Build HIIT workouts with your equipment
                </p>
              </div>
            </div>
          </Link>

          <div className="grid grid-cols-2 gap-4">
            <Link
              href="/trends"
              className="block p-4 rounded-2xl bg-gradient-to-br from-purple-600 to-purple-800 text-white shadow-lg active:scale-[0.98] transition-transform"
            >
              <div className="text-2xl mb-1">&#x1F4C8;</div>
              <h2 className="text-lg font-bold">Trends</h2>
              <p className="text-purple-200 text-xs mt-1">
                Progress over time
              </p>
            </Link>

            <Link
              href="/history"
              className="block p-4 rounded-2xl bg-gradient-to-br from-gray-700 to-gray-900 text-white shadow-lg active:scale-[0.98] transition-transform"
            >
              <div className="text-2xl mb-1">&#x1F4CB;</div>
              <h2 className="text-lg font-bold">History</h2>
              <p className="text-gray-300 text-xs mt-1">
                Past workouts
              </p>
            </Link>
          </div>

          <Link
            href="/sensor-debug"
            className="block w-full p-3 rounded-xl bg-gray-800/50 border border-gray-700 text-gray-400 text-center text-sm active:scale-[0.98] transition-transform"
          >
            Sensor Debug View
          </Link>
        </div>
      </div>
    </main>
  );
}
