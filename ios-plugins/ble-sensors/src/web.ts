import { WebPlugin } from '@capacitor/core';

import type {
  BLESensorPlugin,
  ConnectedDevice,
} from './definitions';

export class BLESensorWeb extends WebPlugin implements BLESensorPlugin {
  async startScanning(): Promise<void> {
    console.warn('[BLESensors] startScanning is not supported on web');
  }

  async stopScanning(): Promise<void> {
    console.warn('[BLESensors] stopScanning is not supported on web');
  }

  async connectDevice(_options: {
    id: string;
    side: 'left' | 'right';
  }): Promise<{ connected: boolean }> {
    console.warn('[BLESensors] connectDevice is not supported on web');
    return { connected: false };
  }

  async disconnectDevice(_options: { id: string }): Promise<void> {
    console.warn('[BLESensors] disconnectDevice is not supported on web');
  }

  async getConnectedDevices(): Promise<{ devices: ConnectedDevice[] }> {
    console.warn('[BLESensors] getConnectedDevices is not supported on web');
    return { devices: [] };
  }

  async startSensorStream(): Promise<void> {
    console.warn('[BLESensors] startSensorStream is not supported on web');
  }

  async stopSensorStream(): Promise<void> {
    console.warn('[BLESensors] stopSensorStream is not supported on web');
  }
}
