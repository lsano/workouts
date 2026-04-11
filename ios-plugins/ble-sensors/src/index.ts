import { registerPlugin } from '@capacitor/core';

import type { BLESensorPlugin } from './definitions';

export * from './definitions';

export const BLESensors = registerPlugin<BLESensorPlugin>('BLESensors');
