# WOD Tracker — Auto-Detected Workout Tracking

A native iOS + watchOS app that automatically detects exercises, counts reps, and provides real-time form feedback using dual foot-mounted BLE sensors and Apple Watch.

## Features

- **Auto exercise detection** — Classifies jump rope, pogo hops, alternating lunges, step-ups, skater hops, agility ladder, and box jumps using sensor fusion
- **Rep counting** — Adaptive peak detection with per-exercise tuning
- **Form feedback** — Real-time alerts on Apple Watch (depth, symmetry, tempo) with haptics
- **Quality scoring** — Tempo consistency, L/R symmetry, depth tracking
- **Trend analytics** — Per-exercise trends over 7/30/90 day periods
- **All on device** — SwiftData persistence, no server required

## Architecture

Fully native Swift/SwiftUI. See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

```
ios/
├── WODTracker/          # iPhone app (SwiftUI + SwiftData)
│   ├── App/             # Entry point, root navigation
│   ├── Models/          # SwiftData models
│   ├── Views/           # All screens + reusable components
│   ├── Sensors/         # BLE (CoreBluetooth) + Watch (WCSession)
│   ├── Inference/       # Signal processing, classification, rep counting
│   └── Services/        # SensorManager, WorkoutManager, HealthKit, Trends
│
└── WODTrackerWatch/     # watchOS companion (CoreMotion + haptics)
```

## Building

1. Open Xcode and create a new iOS App project (SwiftUI, SwiftData)
2. Add a watchOS companion target
3. Add source files from `ios/WODTracker/` and `ios/WODTrackerWatch/`
4. Add capabilities: HealthKit, Bluetooth (Background Modes)
5. Add frameworks: CoreBluetooth, HealthKit, WatchConnectivity, Accelerate
6. Build and run

No CocoaPods or SPM dependencies — uses Apple frameworks only.

## Sensor Requirements

- 2x Stryd foot pods (or compatible BLE IMU sensors) — left + right foot
- Apple Watch with watchOS 10+ — wrist accelerometer/gyroscope
- iPhone with iOS 17+ — sensor fusion and inference hub
