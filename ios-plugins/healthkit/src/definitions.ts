// TypeScript definitions for the WODHealthKit Capacitor plugin.
// This defines the bridge between the web app and native HealthKit/watchOS APIs.

export interface HealthKitPermissions {
  read: HealthDataType[];
  write: HealthDataType[];
}

export type HealthDataType =
  | "activeEnergyBurned"
  | "heartRate"
  | "restingHeartRate"
  | "workout"
  | "bodyMass"
  | "stepCount";

export interface WorkoutSession {
  /** Workout type maps to HKWorkoutActivityType */
  activityType: WorkoutActivityType;
  startDate: string; // ISO 8601
  endDate: string; // ISO 8601
  /** Total active calories burned */
  totalEnergyBurned?: number; // kcal
  /** Workout name/metadata */
  metadata?: Record<string, string>;
}

export type WorkoutActivityType =
  | "traditionalStrengthTraining"
  | "functionalStrengthTraining"
  | "highIntensityIntervalTraining"
  | "coreTraining"
  | "flexibility"
  | "mixedCardio"
  | "other";

export interface HeartRateSample {
  value: number; // bpm
  timestamp: string; // ISO 8601
}

export interface HealthSummary {
  restingHeartRate?: number;
  averageHeartRate?: number;
  activeCaloriesToday?: number;
  workoutsThisWeek?: number;
  bodyMass?: number;
}

export interface WatchWorkoutState {
  isActive: boolean;
  workoutName?: string;
  currentExercise?: string;
  currentSet?: number;
  totalSets?: number;
  timerPhase?: "work" | "rest" | "idle";
  timeRemaining?: number;
  heartRate?: number;
}

export interface WODHealthKitPlugin {
  /**
   * Check if HealthKit is available on this device.
   * Returns false on simulators and non-iOS devices.
   */
  isAvailable(): Promise<{ available: boolean }>;

  /**
   * Request HealthKit permissions for reading and writing health data.
   * Must be called before any read/write operations.
   */
  requestPermissions(options: HealthKitPermissions): Promise<{ granted: boolean }>;

  /**
   * Check if specific permissions have already been granted.
   */
  checkPermissions(options: HealthKitPermissions): Promise<{ granted: boolean }>;

  /**
   * Save a completed workout session to HealthKit.
   * This creates an HKWorkout object visible in the Health app and Activity rings.
   */
  saveWorkout(session: WorkoutSession): Promise<{ success: boolean; workoutId?: string }>;

  /**
   * Start a live workout session (enables heart rate streaming on Apple Watch).
   * The workout must be ended with endWorkoutSession().
   */
  startWorkoutSession(options: {
    activityType: WorkoutActivityType;
    metadata?: Record<string, string>;
  }): Promise<{ sessionId: string }>;

  /**
   * End the current live workout session and save it to HealthKit.
   */
  endWorkoutSession(options: {
    sessionId: string;
  }): Promise<{ success: boolean; totalCalories?: number; averageHeartRate?: number }>;

  /**
   * Get heart rate samples from the current or recent workout session.
   */
  getHeartRateSamples(options: {
    startDate: string;
    endDate?: string;
    limit?: number;
  }): Promise<{ samples: HeartRateSample[] }>;

  /**
   * Get the user's current resting heart rate.
   */
  getRestingHeartRate(): Promise<{ value: number | null }>;

  /**
   * Get a health summary (today's calories, this week's workouts, etc.)
   */
  getHealthSummary(): Promise<HealthSummary>;

  /**
   * Send the current workout state to the paired Apple Watch companion app.
   * This updates the watch UI in real-time during a workout.
   */
  sendWorkoutStateToWatch(state: WatchWorkoutState): Promise<{ delivered: boolean }>;

  /**
   * Listen for messages from the Apple Watch (e.g., set completed, workout control).
   */
  addListener(
    eventName: "watchMessage",
    callback: (data: { action: string; payload?: Record<string, unknown> }) => void
  ): Promise<{ remove: () => void }>;

  /**
   * Listen for live heart rate updates during an active workout session.
   */
  addListener(
    eventName: "heartRateUpdate",
    callback: (data: { bpm: number; timestamp: string }) => void
  ): Promise<{ remove: () => void }>;

  /**
   * Check if an Apple Watch is paired and the companion app is reachable.
   */
  isWatchAvailable(): Promise<{ available: boolean; paired: boolean; reachable: boolean }>;
}
