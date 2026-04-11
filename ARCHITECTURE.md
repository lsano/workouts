# Architecture Overview

## How It Works: Capacitor Hybrid App

This app uses [Capacitor](https://capacitorjs.com/) to run a web app inside a native iOS shell. Understanding this architecture is key to understanding why React/TypeScript and Swift coexist in the same repo.

```
┌─────────────────────────────────────────────────┐
│                   iPhone                         │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │           Native iOS Shell (Swift)          │ │
│  │                                             │ │
│  │  ┌───────────────────────────────────────┐  │ │
│  │  │         WKWebView (Safari)            │  │ │
│  │  │                                       │  │ │
│  │  │   Next.js React App                   │  │ │
│  │  │   ┌─────────┐ ┌─────────┐            │  │ │
│  │  │   │ /live-  │ │/sensor- │            │  │ │
│  │  │   │ workout │ │ debug   │  ...pages  │  │ │
│  │  │   └────┬────┘ └────┬────┘            │  │ │
│  │  │        │           │                  │  │ │
│  │  │   Capacitor JS Bridge                 │  │ │
│  │  └────────┼───────────┼──────────────────┘  │ │
│  │           │           │                      │ │
│  │  ┌────────▼───────────▼──────────────────┐  │ │
│  │  │       Native Capacitor Plugins        │  │ │
│  │  │                                       │  │ │
│  │  │  ┌─────────────┐ ┌─────────────────┐  │  │ │
│  │  │  │ HealthKit   │ │  BLE Sensors    │  │  │ │
│  │  │  │ Plugin      │ │  Plugin         │  │  │ │
│  │  │  │ (Swift)     │ │  (Swift)        │  │  │ │
│  │  │  │             │ │  CoreBluetooth  │  │  │ │
│  │  │  │ HKWorkout   │ │  Stryd L/R     │  │  │ │
│  │  │  │ HeartRate   │ │  foot pods     │  │  │ │
│  │  │  │ WCSession   │ └─────────────────┘  │  │ │
│  │  │  └──────┬──────┘                      │  │ │
│  │  │         │        ┌─────────────────┐  │  │ │
│  │  │         │        │  Sensor Engine  │  │  │ │
│  │  │         │        │  Plugin (Swift) │  │  │ │
│  │  │         │        │                 │  │  │ │
│  │  │         │        │  SignalProc     │  │  │ │
│  │  │         │        │  SensorFusion   │  │  │ │
│  │  │         │        │  Classifier     │  │  │ │
│  │  │         │        │  RepCounter     │  │  │ │
│  │  │         │        │  QualityScorer  │  │  │ │
│  │  │         │        └─────────────────┘  │  │ │
│  │  └─────────┼─────────────────────────────┘  │ │
│  │            │                                  │ │
│  │            │  WatchConnectivity               │ │
│  └────────────┼──────────────────────────────────┘ │
│               │                                     │
└───────────────┼─────────────────────────────────────┘
                │
        ┌───────▼───────────────────┐
        │      Apple Watch          │
        │                           │
        │  SwiftUI App              │
        │  ┌─────────────────────┐  │
        │  │ AutoWorkoutView     │  │
        │  │  - Rep counter      │  │
        │  │  - Exercise name    │  │
        │  │  - Form alerts      │  │
        │  │  - Haptic feedback  │  │
        │  └─────────────────────┘  │
        │                           │
        │  WatchWorkoutManager      │
        │  - CMMotionManager 100Hz  │
        │  - HKWorkoutSession       │
        │  - WCSession relay        │
        └───────────────────────────┘
```

## Why React Components Exist in a Native App

Capacitor's model: **the UI is a web app**. The iPhone renders the React/Next.js pages inside a `WKWebView` (embedded Safari). Native Swift code only runs when the web layer calls into a plugin through the Capacitor bridge.

This means:

| Layer | Technology | Runs Where | Responsibility |
|-------|-----------|------------|----------------|
| **UI pages** | React/Next.js/TypeScript | WKWebView on iPhone | All screens the user sees and interacts with |
| **API routes** | Next.js API routes | Node.js on a server or static export | Data persistence (SQLite), CRUD operations |
| **Native plugins** | Swift | Native iOS process | Hardware access: BLE, CoreBluetooth, HealthKit, WatchConnectivity |
| **Sensor engine** | Swift | Native iOS process | Real-time signal processing, inference (runs on background thread at 200ms intervals) |
| **Watch app** | SwiftUI | watchOS | Sensor capture (CoreMotion), display rep counts, haptic feedback |

**The web app cannot access hardware directly.** Bluetooth, HealthKit, CoreMotion, and WatchConnectivity are iOS-only APIs. The Capacitor plugin bridge is how the web layer reaches them.

## Data Flow: From Sensor to Screen

### During a Live Workout

```
1. Foot sensors (BLE)          2. Apple Watch (CoreMotion)
   │ 50Hz accel+gyro              │ 100Hz accel+gyro
   │                              │
   ▼                              ▼
   BLESensorPlugin.swift          WatchWorkoutManager.swift
   (CoreBluetooth)                (CMMotionManager)
   │                              │
   │  Capacitor event             │  WCSession.sendMessage
   │  "sensorData"                │  (batched every 100ms)
   │                              │
   ▼                              ▼
   Web Layer (JS)                 WODHealthKitPlugin.swift
   sensor-service.ts              (receives watch batches)
   │                              │
   │  Calls plugin                │  Capacitor event
   │  ingestSamples()             │  "sensorData"
   │                              │
   ▼                              ▼
   ┌──────────────────────────────────┐
   │   SensorEnginePlugin.swift       │
   │   (native, background thread)    │
   │                                  │
   │   SensorFusion ──► SetSegmenter  │
   │        │                │        │
   │        ▼                ▼        │
   │   MovementClassifier  RepCounter │
   │        │                │        │
   │        ▼                ▼        │
   │      QualityScorer               │
   └──────────┬───────────────────────┘
              │
              │ Capacitor events:
              │  "repDetected"
              │  "setCompleted"
              │  "formAlert"
              ▼
   ┌──────────────────────┐     ┌──────────────────────┐
   │  Web Layer (React)   │     │  Apple Watch          │
   │  live-workout/page   │     │  (via WCSession)      │
   │                      │     │                       │
   │  Updates rep counter │     │  Updates rep display   │
   │  Shows set cards     │     │  Fires haptics        │
   │  Form alert banner   │     │  Shows form alert     │
   └──────────────────────┘     └───────────────────────┘
```

### Key point: The sensor engine runs natively

The inference pipeline (signal processing, FFT, classification, rep counting) runs as native Swift on a background `DispatchQueue`. It processes sensor data every 200ms. Results are emitted back to the web layer as Capacitor events, which the React UI subscribes to.

The web layer never touches raw sensor data at 50-100Hz. It only receives high-level events like "rep 7 detected" or "set completed: 12 reps of Jump Rope."

## File Organization

```
workouts/
├── src/                              # Web app (React/Next.js)
│   ├── app/                          # Pages (rendered in WKWebView)
│   │   ├── page.tsx                  # Home screen
│   │   ├── live-workout/page.tsx     # Auto-detection workout UI
│   │   ├── sensor-debug/page.tsx     # Sensor visualization
│   │   ├── trends/page.tsx           # Trend analytics charts
│   │   ├── gym/page.tsx              # Manual gym mode
│   │   ├── history/page.tsx          # Workout history
│   │   └── api/                      # Server-side API routes
│   │       ├── sensor-sessions/      # Sensor workout CRUD
│   │       └── trends/               # Trend data queries
│   ├── lib/                          # Shared logic
│   │   ├── db.ts                     # SQLite schema + connection
│   │   ├── sensor-types.ts           # TypeScript types for sensor system
│   │   ├── sensor-sessions.ts        # Sensor session CRUD operations
│   │   ├── sensor-service.ts         # Bridge to native plugins
│   │   └── health/health-service.ts  # Bridge to HealthKit plugin
│   └── components/                   # Reusable React components
│
├── ios-plugins/                      # Native Swift code
│   ├── healthkit/
│   │   ├── swift/WODHealthKitPlugin.swift   # HealthKit + WatchConnectivity
│   │   └── src/definitions.ts               # TypeScript interface
│   ├── ble-sensors/
│   │   ├── swift/BLESensorPlugin.swift      # CoreBluetooth for foot pods
│   │   └── src/definitions.ts               # TypeScript interface
│   ├── sensor-engine/
│   │   ├── swift/SignalProcessing.swift      # DSP: filters, FFT, peaks
│   │   ├── swift/SensorFusion.swift         # Multi-source alignment
│   │   ├── swift/SetSegmenter.swift         # Activity/rest detection
│   │   ├── swift/MovementClassifier.swift   # Exercise classification
│   │   ├── swift/RepCounter.swift           # Rep counting
│   │   ├── swift/QualityScorer.swift        # Quality metrics
│   │   ├── swift/SensorEnginePlugin.swift   # Capacitor plugin orchestrator
│   │   └── src/definitions.ts               # TypeScript interface
│   ├── watchos/
│   │   ├── WODWatchApp.swift                # Watch app entry point
│   │   ├── WatchWorkoutManager.swift        # Sensor capture + state
│   │   ├── AutoWorkoutView.swift            # Auto-detect workout display
│   │   ├── ActiveWorkoutView.swift          # Manual/auto workout display
│   │   └── SetInputView.swift               # Digital Crown rep/weight input
│   └── setup-xcode.sh                       # Xcode project configuration
│
├── capacitor.config.ts               # Capacitor configuration
└── .data/workouts.db                 # SQLite database (local)
```

## The Capacitor Plugin Bridge Pattern

Each native plugin follows the same pattern:

1. **Swift class** extends `CAPPlugin` — implements native functionality
2. **TypeScript definitions** (`definitions.ts`) — declares the API contract
3. **TypeScript index** (`index.ts`) — registers the plugin with `registerPlugin()`
4. **Web fallback** (`web.ts`) — stub for browser testing (returns empty data)
5. **Service wrapper** (`src/lib/sensor-service.ts`) — clean async API for React components

Example call chain for getting connected sensors:

```
React Component
  └─► sensor-service.ts: getConnectedSensors()
        └─► BLESensors plugin (registered via Capacitor)
              └─► BLESensorPlugin.swift: getConnectedDevices()
                    └─► CoreBluetooth: returns peripheral list
```

## Watch Communication Protocol

The watch and phone communicate via `WatchConnectivity` (`WCSession`):

**Phone → Watch** (workout state updates):
- Rep count, exercise name, confidence score
- Form alerts ("Go deeper!") with severity
- Set transitions (start/rest/end) triggering haptics
- Movement state (active/resting/idle)

**Watch → Phone** (sensor data + user actions):
- Batched CoreMotion samples (every 100ms, ~10 samples per batch)
- User corrections (wrong exercise, adjust reps)
- Session control (end workout)

## Why Not a Fully Native App?

The Capacitor hybrid approach was chosen because:

1. **The existing app was web-first** — whiteboard transcription, HIIT templates, and history were already built as React pages
2. **UI for history, trends, corrections, settings is not latency-sensitive** — web rendering at 60fps is fine for scrolling lists and charts
3. **Sensor processing IS latency-sensitive** — that's why it runs natively in Swift plugins, not in JavaScript
4. **Faster iteration** — React/TypeScript is faster to iterate on for UI than SwiftUI, especially for data-heavy screens like trends
5. **Single codebase** — one repo, one database, shared types

The tradeoff: UI rendering goes through a WebView layer, which adds ~5ms of overhead versus native SwiftUI. For a workout tracking app (not a game), this is imperceptible.

## What Runs Where

| Code | Runtime | Thread | Latency Requirement |
|------|---------|--------|-------------------|
| React pages | WKWebView (Safari) | Main (JS) | ~16ms (60fps) |
| API routes | Node.js / static | Server | ~50ms |
| BLE plugin | Native iOS | CBCentralManager queue | ~20ms |
| Sensor engine | Native iOS | Background DispatchQueue | 200ms processing loop |
| Watch sensor capture | watchOS native | CMMotionManager queue | 10ms (100Hz) |
| Watch UI | watchOS SwiftUI | Main | ~16ms (60fps) |
| SQLite queries | Native (better-sqlite3) | Server | ~1ms |
