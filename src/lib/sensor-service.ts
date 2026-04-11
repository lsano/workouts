// Sensor service wrapping the BLE Sensors and Sensor Engine Capacitor plugins.
// Provides a clean async API for the web layer with graceful browser fallback.

import type {
  SensorDataBatch,
  ConnectedSensor,
  RepDetectedEvent,
  SetStartedEvent,
  SetCompletedEvent,
  FormAlertEvent,
  MovementStateEvent,
} from "./sensor-types";

// Dynamic imports for Capacitor plugins - fail gracefully in browser
let bleSensorsPlugin: unknown = null;
let sensorEnginePlugin: unknown = null;

interface BLEPlugin {
  startScanning(): Promise<void>;
  stopScanning(): Promise<void>;
  connectDevice(opts: { id: string; side: "left" | "right" }): Promise<{ connected: boolean }>;
  disconnectDevice(opts: { id: string }): Promise<void>;
  getConnectedDevices(): Promise<{ devices: ConnectedSensor[] }>;
  startSensorStream(): Promise<void>;
  stopSensorStream(): Promise<void>;
  addListener(event: string, cb: (data: unknown) => void): Promise<{ remove: () => void }>;
}

interface EnginePlugin {
  startProcessing(): Promise<void>;
  stopProcessing(): Promise<void>;
  ingestSamples(data: { batch: SensorDataBatch }): Promise<void>;
  getSessionSummary(): Promise<unknown>;
  correctExerciseType(opts: { setIndex: number; exerciseType: string }): Promise<void>;
  correctRepCount(opts: { setIndex: number; repCount: number }): Promise<void>;
  addListener(event: string, cb: (data: unknown) => void): Promise<{ remove: () => void }>;
}

async function getBLEPlugin(): Promise<BLEPlugin | null> {
  if (bleSensorsPlugin) return bleSensorsPlugin as BLEPlugin;
  try {
    const mod = await import("../../ios-plugins/ble-sensors/src/index");
    bleSensorsPlugin = mod.BLESensors;
    return bleSensorsPlugin as BLEPlugin;
  } catch {
    return null;
  }
}

async function getEnginePlugin(): Promise<EnginePlugin | null> {
  if (sensorEnginePlugin) return sensorEnginePlugin as EnginePlugin;
  try {
    const mod = await import("../../ios-plugins/sensor-engine/src/index");
    sensorEnginePlugin = mod.SensorEngine;
    return sensorEnginePlugin as EnginePlugin;
  } catch {
    return null;
  }
}

// --- BLE Sensor Management ---

export async function startSensorScanning(): Promise<boolean> {
  const p = await getBLEPlugin();
  if (!p) return false;
  await p.startScanning();
  return true;
}

export async function stopSensorScanning(): Promise<void> {
  const p = await getBLEPlugin();
  if (p) await p.stopScanning();
}

export async function connectSensor(
  deviceId: string,
  side: "left" | "right"
): Promise<boolean> {
  const p = await getBLEPlugin();
  if (!p) return false;
  const result = await p.connectDevice({ id: deviceId, side });
  return result.connected;
}

export async function disconnectSensor(deviceId: string): Promise<void> {
  const p = await getBLEPlugin();
  if (p) await p.disconnectDevice({ id: deviceId });
}

export async function getConnectedSensors(): Promise<ConnectedSensor[]> {
  const p = await getBLEPlugin();
  if (!p) return [];
  const result = await p.getConnectedDevices();
  return result.devices;
}

export async function onDeviceDiscovered(
  callback: (device: { id: string; name: string; rssi: number }) => void
): Promise<(() => void) | null> {
  const p = await getBLEPlugin();
  if (!p) return null;
  const sub = await p.addListener("deviceDiscovered", callback as (data: unknown) => void);
  return sub.remove;
}

export async function onSensorData(
  callback: (batch: SensorDataBatch) => void
): Promise<(() => void) | null> {
  const p = await getBLEPlugin();
  if (!p) return null;
  const sub = await p.addListener("sensorData", callback as (data: unknown) => void);
  return sub.remove;
}

export async function onDeviceDisconnected(
  callback: (data: { id: string; side: string; reason: string }) => void
): Promise<(() => void) | null> {
  const p = await getBLEPlugin();
  if (!p) return null;
  const sub = await p.addListener("deviceDisconnected", callback as (data: unknown) => void);
  return sub.remove;
}

// --- Sensor Engine ---

export async function startInferenceEngine(): Promise<boolean> {
  const p = await getEnginePlugin();
  if (!p) return false;
  await p.startProcessing();
  return true;
}

export async function stopInferenceEngine(): Promise<void> {
  const p = await getEnginePlugin();
  if (p) await p.stopProcessing();
}

export async function feedSensorData(batch: SensorDataBatch): Promise<void> {
  const p = await getEnginePlugin();
  if (p) await p.ingestSamples({ batch });
}

export async function correctExercise(
  setIndex: number,
  exerciseType: string
): Promise<void> {
  const p = await getEnginePlugin();
  if (p) await p.correctExerciseType({ setIndex, exerciseType });
}

export async function correctReps(
  setIndex: number,
  repCount: number
): Promise<void> {
  const p = await getEnginePlugin();
  if (p) await p.correctRepCount({ setIndex, repCount });
}

// --- Engine Event Listeners ---

export async function onRepDetected(
  callback: (event: RepDetectedEvent) => void
): Promise<(() => void) | null> {
  const p = await getEnginePlugin();
  if (!p) return null;
  const sub = await p.addListener("repDetected", callback as (data: unknown) => void);
  return sub.remove;
}

export async function onSetStarted(
  callback: (event: SetStartedEvent) => void
): Promise<(() => void) | null> {
  const p = await getEnginePlugin();
  if (!p) return null;
  const sub = await p.addListener("setStarted", callback as (data: unknown) => void);
  return sub.remove;
}

export async function onSetCompleted(
  callback: (event: SetCompletedEvent) => void
): Promise<(() => void) | null> {
  const p = await getEnginePlugin();
  if (!p) return null;
  const sub = await p.addListener("setCompleted", callback as (data: unknown) => void);
  return sub.remove;
}

export async function onFormAlert(
  callback: (event: FormAlertEvent) => void
): Promise<(() => void) | null> {
  const p = await getEnginePlugin();
  if (!p) return null;
  const sub = await p.addListener("formAlert", callback as (data: unknown) => void);
  return sub.remove;
}

export async function onMovementStateChanged(
  callback: (event: MovementStateEvent) => void
): Promise<(() => void) | null> {
  const p = await getEnginePlugin();
  if (!p) return null;
  const sub = await p.addListener("movementStateChanged", callback as (data: unknown) => void);
  return sub.remove;
}
