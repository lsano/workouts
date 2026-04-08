import { WebPlugin } from "@capacitor/core";
import type {
  WODHealthKitPlugin,
  HealthKitPermissions,
  WorkoutSession,
  WorkoutActivityType,
  WatchWorkoutState,
} from "./definitions";

/**
 * Web fallback implementation. Returns safe defaults so the app works
 * in browsers without HealthKit. The UI can check isAvailable() to
 * conditionally show/hide health features.
 */
export class WODHealthKitWeb extends WebPlugin implements WODHealthKitPlugin {
  async isAvailable() {
    return { available: false };
  }

  async requestPermissions(_options: HealthKitPermissions) {
    return { granted: false };
  }

  async checkPermissions(_options: HealthKitPermissions) {
    return { granted: false };
  }

  async saveWorkout(_session: WorkoutSession) {
    return { success: false };
  }

  async startWorkoutSession(_options: {
    activityType: WorkoutActivityType;
    metadata?: Record<string, string>;
  }) {
    return { sessionId: "" };
  }

  async endWorkoutSession(_options: { sessionId: string }) {
    return { success: false };
  }

  async getHeartRateSamples(_options: {
    startDate: string;
    endDate?: string;
    limit?: number;
  }) {
    return { samples: [] };
  }

  async getRestingHeartRate() {
    return { value: null };
  }

  async getHealthSummary() {
    return {};
  }

  async sendWorkoutStateToWatch(_state: WatchWorkoutState) {
    return { delivered: false };
  }

  async isWatchAvailable() {
    return { available: false, paired: false, reachable: false };
  }
}
