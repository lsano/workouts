import { WebPlugin } from "@capacitor/core";
import type {
  SensorEnginePlugin,
  SensorBatchInput,
  SessionSummary,
} from "./definitions";

export class SensorEngineWeb extends WebPlugin implements SensorEnginePlugin {
  async startProcessing(): Promise<void> {
    console.warn("SensorEngine: startProcessing not available in browser");
  }

  async stopProcessing(): Promise<void> {
    console.warn("SensorEngine: stopProcessing not available in browser");
  }

  async ingestSamples(_data: { batch: SensorBatchInput }): Promise<void> {
    // No-op in browser
  }

  async getSessionSummary(): Promise<SessionSummary> {
    return {
      sets: [],
      totalReps: 0,
      totalSets: 0,
      elapsedSeconds: 0,
      movementState: "idle",
    };
  }

  async correctExerciseType(_opts: {
    setIndex: number;
    exerciseType: string;
  }): Promise<void> {
    console.warn("SensorEngine: correctExerciseType not available in browser");
  }

  async correctRepCount(_opts: {
    setIndex: number;
    repCount: number;
  }): Promise<void> {
    console.warn("SensorEngine: correctRepCount not available in browser");
  }
}
