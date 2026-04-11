# Architecture Overview

## Fully Native SwiftUI App

This is a native iOS + watchOS app built entirely in Swift. No web views, no JavaScript bridges, no Capacitor.

```
┌─────────────────────────────────────────────────────┐
│                     iPhone                           │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │              SwiftUI App                        │  │
│  │                                                 │  │
│  │  ┌─────────┐ ┌──────────┐ ┌─────────────────┐  │  │
│  │  │  Home   │ │  Live    │ │    Trends /     │  │  │
│  │  │  View   │ │ Workout  │ │    History      │  │  │
│  │  └────┬────┘ └────┬─────┘ └────────┬────────┘  │  │
│  │       │           │                │            │  │
│  │       └───────────┼────────────────┘            │  │
│  │                   │                              │  │
│  │            @Observable ViewModels                │  │
│  │       ┌───────────┼────────────────┐            │  │
│  │       │           │                │            │  │
│  │  SensorManager  WorkoutManager  TrendService    │  │
│  │       │           │                │            │  │
│  └───────┼───────────┼────────────────┼────────────┘  │
│          │           │                │               │
│  ┌───────▼───────────▼────────────────▼────────────┐  │
│  │                Service Layer                     │  │
│  │                                                  │  │
│  │  ┌──────────┐  ┌──────────────┐  ┌───────────┐  │  │
│  │  │   BLE    │  │  Inference   │  │ HealthKit │  │  │
│  │  │ Manager  │  │   Engine     │  │  Service  │  │  │
│  │  │          │  │              │  │           │  │  │
│  │  │ CoreBT   │  │ SignalProc   │  │ HKWorkout │  │  │
│  │  │ Stryd    │  │ Fusion       │  │ HeartRate │  │  │
│  │  │ L/R pods │  │ Classifier   │  │ Calories  │  │  │
│  │  │          │  │ RepCounter   │  │           │  │  │
│  │  │          │  │ QualityScore │  │           │  │  │
│  │  └──────────┘  └──────────────┘  └───────────┘  │  │
│  │                                                  │  │
│  │  ┌──────────────┐  ┌─────────────────────────┐  │  │
│  │  │ WatchConnect │  │      SwiftData          │  │  │
│  │  │  or          │  │  WorkoutSession          │  │  │
│  │  │  WCSession   │  │  DetectedExerciseSet     │  │  │
│  │  │  relay       │  │  RepEvent                │  │  │
│  │  └──────┬───────┘  │  TrendAggregate          │  │  │
│  │         │          └─────────────────────────┘  │  │
│  └─────────┼───────────────────────────────────────┘  │
│            │                                          │
└────────────┼──────────────────────────────────────────┘
             │  WatchConnectivity
     ┌───────▼──────────────────────┐
     │        Apple Watch            │
     │                               │
     │  SwiftUI Views                │
     │  ┌─────────────────────────┐  │
     │  │   AutoWorkoutView       │  │
     │  │   - 72pt rep counter    │  │
     │  │   - Exercise name       │  │
     │  │   - Form alert banner   │  │
     │  │   - Haptic feedback     │  │
     │  └─────────────────────────┘  │
     │                               │
     │  WatchWorkoutManager          │
     │  - CMMotionManager (100Hz)    │
     │  - HKWorkoutSession           │
     │  - WCSession → phone          │
     └──────────────────────────────┘
```

## Why Native

Previous iterations used Capacitor (web app in a WKWebView with Swift plugins). We migrated to fully native because:

1. **Most code was already Swift** — BLE, CoreMotion, inference pipeline, watch app were all native. The web layer was just forwarding events through a bridge.
2. **No cross-platform need** — targeting iPhone + Apple Watch only. No Android.
3. **Eliminated bridge overhead** — sensor events no longer serialize through a JS bridge.
4. **One language, one debugger** — Swift + Xcode end to end.
5. **Better system integration** — background processing, notifications, and always-on sensor capture work more reliably without a WebView.

## Layers

| Layer | Technology | Responsibility |
|-------|-----------|----------------|
| **Views** | SwiftUI | All screens: home, live workout, sensor debug, history, trends |
| **ViewModels** | @Observable classes | State management, coordinates services, drives UI |
| **Services** | Plain Swift classes | BLE, WatchConnectivity, HealthKit, inference orchestration |
| **Inference** | Swift + Accelerate | Signal processing, sensor fusion, exercise classification, rep counting |
| **Persistence** | SwiftData | Workout sessions, sets, reps, trends — all on device |
| **Watch** | SwiftUI + CoreMotion | Sensor capture, rep display, form alerts, haptics |

## Data Flow: Sensor to Screen

```
Foot Sensors (BLE, 50Hz)        Apple Watch (CoreMotion, 100Hz)
    │                               │
    ▼                               ▼
BLEManager.swift                WatchWorkoutManager.swift
(CoreBluetooth)                 (CMMotionManager)
    │                               │
    │  onSensorData callback        │  WCSession.sendMessage
    │                               │  (batched every 100ms)
    ▼                               ▼
SensorManager.swift ◄──── WatchConnector.swift
    │                       (receives batches,
    │                        applies time sync)
    │
    ▼
InferenceEngine.swift
    │
    ├── SensorFusion (align 3 streams)
    ├── SetSegmenter (activity vs rest)
    ├── MovementClassifier (rule-based)
    ├── RepCounter (adaptive peaks)
    └── QualityScorer (tempo, symmetry, depth)
    │
    │  @Published properties update directly
    ▼
┌─────────────────────┐    ┌──────────────────────┐
│  SwiftUI Views      │    │  Apple Watch          │
│  (LiveWorkoutView)  │    │  (via WatchConnector) │
│                     │    │                       │
│  Reads @Observable  │    │  Receives:            │
│  properties from    │    │  - repUpdate          │
│  WorkoutManager     │    │  - formAlert          │
│  and InferenceEngine│    │  - setTransition      │
│                     │    │  Fires haptics        │
└─────────────────────┘    └───────────────────────┘
```

**Key difference from Capacitor version:** No serialization boundary. SwiftUI views read @Observable/@Published properties directly from the inference engine. When a rep is detected, the view updates in the same process, on the same thread dispatch — no JSON encoding, no bridge crossing.

## File Organization

```
ios/
├── WODTracker/                          # iPhone app
│   ├── App/
│   │   ├── WODTrackerApp.swift          # @main, SwiftData container
│   │   └── ContentView.swift            # Root NavigationStack
│   │
│   ├── Models/
│   │   └── WorkoutModels.swift          # SwiftData models + enums
│   │       - ExerciseType               # jump_rope, pogo_hops, etc.
│   │       - MovementState              # idle, active, resting
│   │       - WorkoutSession             # @Model — top-level session
│   │       - DetectedExerciseSet        # @Model — auto-detected set
│   │       - RepEvent                   # @Model — single rep
│   │       - SensorDevice               # @Model — paired sensor
│   │       - TrendAggregate             # @Model — daily trends
│   │
│   ├── Views/
│   │   ├── HomeView.swift               # Dashboard + navigation
│   │   ├── LiveWorkoutView.swift        # 3-phase auto-detect workout
│   │   ├── SensorDebugView.swift        # Real-time sensor charts
│   │   ├── HistoryView.swift            # Past workouts list
│   │   ├── WorkoutDetailView.swift      # Drill into a session
│   │   ├── TrendsView.swift             # Exercise analytics
│   │   └── Components/
│   │       ├── SetCardView.swift        # Reusable set card with edit
│   │       ├── SensorStatusBar.swift    # L/R/W connection dots
│   │       └── TrendChartView.swift     # Canvas-drawn charts
│   │
│   ├── Sensors/
│   │   ├── BLEManager.swift             # CoreBluetooth for foot pods
│   │   └── WatchConnector.swift         # WCSession + time sync
│   │
│   ├── Inference/
│   │   ├── InferenceEngine.swift        # Orchestrates pipeline
│   │   ├── SignalProcessing.swift       # Butterworth, FFT, peaks
│   │   ├── SensorFusion.swift           # Multi-source alignment
│   │   ├── SetSegmenter.swift           # Activity/rest detection
│   │   ├── MovementClassifier.swift     # Exercise classification
│   │   ├── RepCounter.swift             # Rep counting
│   │   └── QualityScorer.swift          # Quality metrics
│   │
│   └── Services/
│       ├── SensorManager.swift          # Coordinates BLE + Watch + Engine
│       ├── WorkoutManager.swift         # Session lifecycle
│       ├── HealthKitService.swift       # HKWorkoutSession, heart rate
│       ├── TrendService.swift           # Trend computation + queries
│       └── PersistenceController.swift  # SwiftData helpers
│
├── WODTrackerWatch/                     # watchOS companion
│   ├── WODWatchApp.swift                # @main entry
│   ├── WatchWorkoutManager.swift        # CoreMotion + WCSession + state
│   ├── AutoWorkoutView.swift            # Auto-detect rep display
│   ├── ActiveWorkoutView.swift          # Manual + auto modes
│   ├── IdleWatchView.swift              # "Start on iPhone" prompt
│   ├── SetInputView.swift               # Digital Crown input
│   ├── WorkoutPlanView.swift            # Exercise list
│   └── WODWatch.entitlements            # HealthKit permissions
│
└── (legacy)
    ├── src/                             # Old Next.js web app (reference)
    └── ios-plugins/                     # Old Capacitor plugins (reference)
```

## SwiftData Persistence

All data stays on device. No server, no cloud sync (MVP).

```
WorkoutSession (1)
    ├── DetectedExerciseSet (many)
    │       ├── RepEvent (many)
    │       └── quality: SetQualityMetrics (embedded JSON)
    └── SensorRecording (many, optional)

SensorDevice (standalone)
TrendAggregate (standalone, indexed by exercise + date)
```

SwiftData handles migrations automatically. The model container is configured in `WODTrackerApp.swift`.

## Watch Communication Protocol

Bidirectional via `WatchConnectivity` (`WCSession`):

**Phone → Watch:**
```swift
// Rep update
["type": "repUpdate", "repCount": 7, "exerciseName": "Jump Rope", "confidence": 0.85]

// Form alert (triggers haptic)
["type": "formAlert", "message": "Go deeper!", "severity": "warning"]

// Set transition (triggers haptic)
["type": "setTransition", "transition": "restStart"]

// Movement state
["type": "movementState", "state": "active"]
```

**Watch → Phone:**
```swift
// Sensor data batch (every 100ms)
["sensorBatch": [["t": 1234.5, "ax": 0.1, "ay": 9.8, ...]]]

// User actions
["action": "correctExercise", "payload": ["exerciseType": "alternating_lunges"]]
["action": "adjustReps", "payload": ["delta": -1]]
["action": "endWorkout"]
```

## Inference Pipeline

Rule-based for MVP. Runs every 200ms on a background DispatchQueue.

```
Raw samples (3 sources, 50-100Hz each)
    │
    ▼
Signal Conditioning
    - Butterworth low-pass (20Hz cutoff)
    - Gravity removal (complementary filter)
    - Acceleration magnitude
    │
    ▼
Set Segmentation
    - Variance-based activity detection
    - Rest window > 3s = set boundary
    │
    ▼
Exercise Classification (within active windows)
    - FFT dominant frequency
    - Peak acceleration amplitude
    - Vertical vs lateral axis ratios
    - L/R alternation pattern
    - Gyro rotation magnitude
    │
    ▼
Rep Counting
    - Adaptive peak detection per exercise type
    - Bilateral exercises: count both feet, divide by 2
    │
    ▼
Quality Scoring
    - Tempo consistency (CV of inter-rep intervals)
    - L/R symmetry (peak amplitude ratio)
    - Depth proxy (peak accel vs personal baseline)
    - Overall weighted score
```

**Classification rules (Tier 1):**

| Exercise | Frequency | Amplitude | L/R Pattern | Key Signal |
|----------|-----------|-----------|-------------|------------|
| Jump Rope | 2-3 Hz | Low (<2g) | Simultaneous | High freq, both feet |
| Pogo Hops | 1-2 Hz | Moderate | Simultaneous | Lower freq than rope |
| Alt. Lunges | 0.3-0.7 Hz | High | Alternating | Slow, asymmetric L/R |
| Step-Ups | 0.5-1 Hz | Moderate | Alternating | One foot leads |

## Xcode Project Setup

The repo contains Swift source files. To build:

1. Create new Xcode project: iOS App (SwiftUI, SwiftData)
2. Add watchOS companion target
3. Add source files from `ios/WODTracker/` and `ios/WODTrackerWatch/`
4. Add capabilities: HealthKit, Bluetooth (Background Modes)
5. Add frameworks: CoreBluetooth, HealthKit, WatchConnectivity, Accelerate
6. Build and run

No CocoaPods, no SPM dependencies. Everything uses Apple frameworks.
