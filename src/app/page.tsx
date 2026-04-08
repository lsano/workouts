import Link from "next/link";

export default function Home() {
  return (
    <main className="flex-1 flex flex-col items-center justify-center p-6">
      <div className="w-full max-w-md space-y-8">
        <div className="text-center">
          <h1 className="text-4xl font-bold tracking-tight mb-2">WOD Tracker</h1>
          <p className="text-gray-500 dark:text-gray-400">
            Track your gym workouts and build home HIIT sessions
          </p>
        </div>

        <div className="space-y-4">
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

          <Link
            href="/history"
            className="block w-full p-6 rounded-2xl bg-gradient-to-br from-gray-700 to-gray-900 text-white shadow-lg active:scale-[0.98] transition-transform"
          >
            <div className="flex items-center gap-4">
              <div className="text-4xl">&#x1F4CA;</div>
              <div>
                <h2 className="text-xl font-bold">History</h2>
                <p className="text-gray-300 text-sm mt-1">
                  View past workouts and track progress
                </p>
              </div>
            </div>
          </Link>
        </div>
      </div>
    </main>
  );
}
