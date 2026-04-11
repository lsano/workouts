// TypeScript types for the sensor auto-detection system.
// Used across the web layer for live workout, debug, history, and trends.

// --- Sensor Hardware ---

export type SensorSource = "left_foot" | "right_foot" | "watch";

export interface SensorDevice {
  id: string;
  type: "foot_sensor" | "watch" | "camera";
  side?: "left" | "right";
  name: string;
  firmware?: string;
  lastSeenAt?: string;
}

export interface ConnectedSensor {
  id: string;
  source: SensorSource;
  name: string;
  connected: boolean;
  batteryLevel?: number;
  signalStrength?: number;
}

export interface SensorConfig {
  leftFootConnected: boolean;
  rightFootConnected: boolean;
  watchConnected: boolean;
  leftFootDeviceId?: string;
  rightFootDeviceId?: string;
  sampleRateHz: number;
}

// --- Raw Sensor Data ---

export interface SensorSample {
  timestamp: number; // ms since epoch
  ax: number;
  ay: number;
  az: number;
  gx: number;
  gy: number;
  gz: number;
}

export interface SensorDataBatch {
  source: SensorSource;
  samples: SensorSample[];
}

// --- Detection Results ---

export type ExerciseType =
  | "jump_rope"
  | "pogo_hops"
  | "alternating_lunges"
  | "step_ups"
  | "skater_hops"
  | "agility_ladder"
  | "box_jumps"
  | "unknown";

export const EXERCISE_TYPE_LABELS: Record<ExerciseType, string> = {
  jump_rope: "Jump Rope",
  pogo_hops: "Pogo Hops",
  alternating_lunges: "Alternating Lunges",
  step_ups: "Step-Ups",
  skater_hops: "Skater Hops",
  agility_ladder: "Agility Ladder",
  box_jumps: "Box Jumps",
  unknown: "Unknown",
};

export type MovementState = "idle" | "active" | "resting";

export type ConfidenceLevel = "high" | "medium" | "low";

export function getConfidenceLevel(confidence: number): ConfidenceLevel {
  if (confidence >= 0.8) return "high";
  if (confidence >= 0.5) return "medium";
  return "low";
}

// --- Detected Sets & Reps ---

export interface DetectedSet {
  id: string;
  sessionId: string;
  exerciseType: ExerciseType;
  detectedType?: ExerciseType;
  classifierConfidence: number;
  startTime: string;
  endTime: string;
  durationSeconds: number;
  repCountDetected: number;
  repCountCorrected?: number;
  wasUserCorrected: boolean;
  userCorrectedType?: string;
  sourceMode: "wearables_only" | "wearables_plus_camera";
  qualityMetrics?: SetQualityMetrics;
  sortOrder: number;
  reps?: RepEvent[];
}

export interface RepEvent {
  id: string;
  setId: string;
  repIndex: number;
  timestamp: string;
  durationMs?: number;
  repConfidence: number;
  leftRightPattern?: "left" | "right" | "both";
  tempoMs?: number;
  qualityScore?: number;
  symmetryScore?: number;
  depthScore?: number;
  stabilityScore?: number;
}

export interface SetQualityMetrics {
  avgTempo: number;
  tempoConsistency: number;
  symmetryScore: number;
  depthScore: number;
  depthConsistency: number;
  overallQuality: number;
}

// --- Sensor Session ---

export interface SensorSession {
  id: string;
  workoutId: string;
  startTime: string;
  endTime?: string;
  sensorConfig: SensorConfig;
  overallConfidence?: number;
  notes?: string;
  sets: DetectedSet[];
  createdAt: string;
}

// --- Exercise Summary ---

export interface ExerciseSummary {
  id: string;
  sessionId: string;
  exerciseType: ExerciseType;
  totalSets: number;
  totalReps: number;
  avgTempo?: number;
  avgSymmetry?: number;
  avgQuality?: number;
  avgDepth?: number;
  fatigueDropoff?: number;
}

// --- Trend Data ---

export interface TrendAggregate {
  id: string;
  exerciseType: ExerciseType;
  dateBucket: string;
  totalSessions: number;
  totalSets: number;
  totalReps: number;
  avgRepsPerSet?: number;
  avgTempo?: number;
  avgSymmetry?: number;
  avgQuality?: number;
  avgFatigueDropoff?: number;
}

export type TrendPeriod = "7d" | "30d" | "90d";

// --- Live Workout Events (from native plugin) ---

export interface RepDetectedEvent {
  repCount: number;
  exerciseName: string;
  confidence: number;
  setIndex: number;
}

export interface SetStartedEvent {
  exerciseType: ExerciseType;
  confidence: number;
  startTime: string;
}

export interface SetCompletedEvent {
  exerciseType: ExerciseType;
  reps: number;
  durationSeconds: number;
  quality: SetQualityMetrics;
  setIndex: number;
}

export interface FormAlertEvent {
  message: string;
  severity: "info" | "warning" | "error";
}

export interface MovementStateEvent {
  state: MovementState;
}
