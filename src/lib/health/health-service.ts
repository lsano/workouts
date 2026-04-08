// Health service wrapping the WODHealthKit Capacitor plugin.
// Provides a clean async API for the web layer and handles
// graceful degradation when HealthKit is unavailable.

import type {
  WODHealthKitPlugin,
  WorkoutActivityType,
  HealthSummary,
  HeartRateSample,
  WatchWorkoutState,
} from "../../../ios-plugins/healthkit/src/definitions";

let plugin: WODHealthKitPlugin | null = null;
let availabilityChecked = false;
let isHealthKitAvailable = false;

async function getPlugin(): Promise<WODHealthKitPlugin | null> {
  if (plugin) return plugin;
  try {
    const mod = await import("../../../ios-plugins/healthkit/src/index");
    plugin = mod.WODHealthKit;
    return plugin;
  } catch {
    return null;
  }
}

/**
 * Check if HealthKit is available on this device.
 * Caches the result after first check.
 */
export async function checkHealthKitAvailable(): Promise<boolean> {
  if (availabilityChecked) return isHealthKitAvailable;

  const p = await getPlugin();
  if (!p) {
    availabilityChecked = true;
    isHealthKitAvailable = false;
    return false;
  }

  const result = await p.isAvailable();
  isHealthKitAvailable = result.available;
  availabilityChecked = true;
  return isHealthKitAvailable;
}

/**
 * Request HealthKit permissions. Call once during onboarding.
 */
export async function requestHealthPermissions(): Promise<boolean> {
  const p = await getPlugin();
  if (!p) return false;

  const result = await p.requestPermissions({
    read: ["heartRate", "restingHeartRate", "activeEnergyBurned", "workout", "bodyMass"],
    write: ["workout", "activeEnergyBurned"],
  });
  return result.granted;
}

/**
 * Save a completed workout to HealthKit.
 */
export async function saveWorkoutToHealth(opts: {
  startDate: Date;
  endDate: Date;
  name: string;
  type: WorkoutActivityType;
  calories?: number;
}): Promise<boolean> {
  const p = await getPlugin();
  if (!p) return false;

  const result = await p.saveWorkout({
    activityType: opts.type,
    startDate: opts.startDate.toISOString(),
    endDate: opts.endDate.toISOString(),
    totalEnergyBurned: opts.calories,
    metadata: { workoutName: opts.name },
  });
  return result.success;
}

/**
 * Start a live workout session for heart rate streaming.
 * Returns a session controller.
 */
export async function startLiveSession(type: WorkoutActivityType = "functionalStrengthTraining") {
  const p = await getPlugin();
  if (!p) return null;

  const result = await p.startWorkoutSession({
    activityType: type,
    metadata: {},
  });

  if (!result.sessionId) return null;

  return {
    sessionId: result.sessionId,

    async end() {
      return p.endWorkoutSession({ sessionId: result.sessionId });
    },

    onHeartRate(callback: (bpm: number) => void) {
      return p.addListener("heartRateUpdate", (data) => {
        callback(data.bpm);
      });
    },
  };
}

/**
 * Get health summary data (calories, resting HR, workouts this week).
 */
export async function getHealthSummary(): Promise<HealthSummary | null> {
  const p = await getPlugin();
  if (!p) return null;

  return p.getHealthSummary();
}

/**
 * Get heart rate samples for a time range.
 */
export async function getHeartRateSamples(
  startDate: Date,
  endDate?: Date,
  limit?: number
): Promise<HeartRateSample[]> {
  const p = await getPlugin();
  if (!p) return [];

  const result = await p.getHeartRateSamples({
    startDate: startDate.toISOString(),
    endDate: endDate?.toISOString(),
    limit,
  });
  return result.samples;
}

/**
 * Send current workout state to the Apple Watch.
 */
export async function syncToWatch(state: WatchWorkoutState): Promise<boolean> {
  const p = await getPlugin();
  if (!p) return false;

  const result = await p.sendWorkoutStateToWatch(state);
  return result.delivered;
}

/**
 * Listen for actions from the Apple Watch.
 */
export async function onWatchAction(
  callback: (action: string, payload?: Record<string, unknown>) => void
) {
  const p = await getPlugin();
  if (!p) return null;

  return p.addListener("watchMessage", (data) => {
    callback(data.action, data.payload);
  });
}

/**
 * Check Apple Watch connectivity.
 */
export async function checkWatchAvailable(): Promise<{
  available: boolean;
  paired: boolean;
  reachable: boolean;
}> {
  const p = await getPlugin();
  if (!p) return { available: false, paired: false, reachable: false };

  return p.isWatchAvailable();
}
