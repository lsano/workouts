export interface BLESensorPlugin {
  startScanning(): Promise<void>;
  stopScanning(): Promise<void>;
  connectDevice(options: {
    id: string;
    side: 'left' | 'right';
  }): Promise<{ connected: boolean }>;
  disconnectDevice(options: { id: string }): Promise<void>;
  getConnectedDevices(): Promise<{ devices: ConnectedDevice[] }>;
  startSensorStream(): Promise<void>;
  stopSensorStream(): Promise<void>;
  addListener(
    eventName: 'deviceDiscovered',
    callback: (data: DiscoveredDevice) => void,
  ): Promise<{ remove: () => void }>;
  addListener(
    eventName: 'deviceConnected',
    callback: (data: { id: string; side: string; name: string }) => void,
  ): Promise<{ remove: () => void }>;
  addListener(
    eventName: 'deviceDisconnected',
    callback: (data: { id: string; side: string; reason: string }) => void,
  ): Promise<{ remove: () => void }>;
  addListener(
    eventName: 'sensorData',
    callback: (data: SensorDataBatch) => void,
  ): Promise<{ remove: () => void }>;
  addListener(
    eventName: 'batteryUpdate',
    callback: (data: { id: string; side: string; level: number }) => void,
  ): Promise<{ remove: () => void }>;
}

export interface DiscoveredDevice {
  id: string;
  name: string;
  rssi: number;
}

export interface ConnectedDevice {
  id: string;
  side: 'left' | 'right';
  name: string;
  connected: boolean;
  batteryLevel?: number;
}

export interface SensorSample {
  timestamp: number;
  ax: number;
  ay: number;
  az: number;
  gx: number;
  gy: number;
  gz: number;
}

export interface SensorDataBatch {
  side: 'left' | 'right';
  samples: SensorSample[];
}
