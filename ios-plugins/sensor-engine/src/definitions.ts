// TypeScript definitions for the SensorEngine Capacitor plugin.
// This bridges the native Swift inference pipeline to the web layer.

export interface SensorEngineSample {
  timestamp: number;
  ax: number;
  ay: number;
  az: number;
  gx: number;
  gy: number;
  gz: number;
}

export interface SensorBatchInput {
  source: "left_foot" | "right_foot" | "watch";
  samples: SensorEngineSample[];
}

export interface DetectedSetSummary {
  setIndex: number;
  exerciseType: string;
  detectedType: string;
  confidence: number;
  repCount: number;
  startTime: string;
  endTime: string;
  durationSeconds: number;
  quality: {
    avgTempo: number;
    tempoConsistency: number;
    symmetryScore: number;
    depthScore: number;
    depthConsistency: number;
    overallQuality: number;
  };
  wasCorrected: boolean;
}

export interface SessionSummary {
  sets: DetectedSetSummary[];
  totalReps: number;
  totalSets: number;
  elapsedSeconds: number;
  movementState: "idle" | "active" | "resting";
}

export interface RepDetectedEvent {
  repCount: number;
  exerciseName: string;
  confidence: number;
  setIndex: number;
}

export interface SetStartedEvent {
  exerciseType: string;
  confidence: number;
  startTime: string;
}

export interface SetCompletedEvent {
  exerciseType: string;
  reps: number;
  durationSeconds: number;
  quality: {
    avgTempo: number;
    tempoConsistency: number;
    symmetryScore: number;
    depthScore: number;
    depthConsistency: number;
    overallQuality: number;
  };
  setIndex: number;
}

export interface FormAlertEvent {
  message: string;
  severity: "info" | "warning" | "error";
}

export interface MovementStateEvent {
  state: "idle" | "active" | "resting";
}

export interface SensorEnginePlugin {
  /** Start the inference processing loop (runs every 200ms). */
  startProcessing(): Promise<void>;

  /** Stop the inference processing loop. */
  stopProcessing(): Promise<void>;

  /** Feed sensor samples into the fusion engine. */
  ingestSamples(data: { batch: SensorBatchInput }): Promise<void>;

  /** Get the current session summary (all detected sets). */
  getSessionSummary(): Promise<SessionSummary>;

  /** Correct the exercise type for a detected set. */
  correctExerciseType(opts: {
    setIndex: number;
    exerciseType: string;
  }): Promise<void>;

  /** Correct the rep count for a detected set. */
  correctRepCount(opts: {
    setIndex: number;
    repCount: number;
  }): Promise<void>;

  /** Listen for rep detection events. */
  addListener(
    eventName: "repDetected",
    callback: (event: RepDetectedEvent) => void
  ): Promise<{ remove: () => void }>;

  /** Listen for new set detection. */
  addListener(
    eventName: "setStarted",
    callback: (event: SetStartedEvent) => void
  ): Promise<{ remove: () => void }>;

  /** Listen for set completion. */
  addListener(
    eventName: "setCompleted",
    callback: (event: SetCompletedEvent) => void
  ): Promise<{ remove: () => void }>;

  /** Listen for form alerts. */
  addListener(
    eventName: "formAlert",
    callback: (event: FormAlertEvent) => void
  ): Promise<{ remove: () => void }>;

  /** Listen for movement state changes. */
  addListener(
    eventName: "movementStateChanged",
    callback: (event: MovementStateEvent) => void
  ): Promise<{ remove: () => void }>;
}
