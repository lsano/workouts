import { registerPlugin } from "@capacitor/core";
import type { SensorEnginePlugin } from "./definitions";

export * from "./definitions";
export const SensorEngine =
  registerPlugin<SensorEnginePlugin>("SensorEngine");
