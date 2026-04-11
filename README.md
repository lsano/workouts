# WOD Tracker

A workout tracking app with two modes:
- **Gym Mode** — Photograph a trainer's whiteboard, AI-transcribes the workout plan, then track sets/reps/weight as you go through stations.
- **Home Mode** — Browse HIIT templates (Tabata, EMOM, AMRAP, circuits) using kettlebells, dumbbells, and bodyweight exercises.

Built with Next.js, SQLite, Tailwind CSS, and Capacitor for native iOS.

---

## Prerequisites

- **Node.js** >= 18
- **npm** >= 9
- **macOS** (required for iOS/watchOS builds — web mode works on any OS)
- **Xcode** >= 15 (for native iOS builds only)
- **Apple Developer account** (for HealthKit and watchOS — free account works for device testing)

## Quick Start (Web)

```bash
# 1. Install dependencies
npm install

# 2. (Optional) Enable real whiteboard transcription
cp .env.local.example .env.local
# Edit .env.local and add your Anthropic API key

# 3. Start the dev server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

> Without `ANTHROPIC_API_KEY`, Gym Mode uses demo data for transcription. Everything else works normally.

## Available Scripts

| Command | Description |
|---------|-------------|
| `npm run dev` | Start Next.js dev server on port 3000 |
| `npm run build` | Production build (also runs TypeScript type-checking) |
| `npm run start` | Start production server (run `build` first) |
| `npm run lint` | Run ESLint |
| `npm run cap:init-ios` | Add iOS platform to Capacitor |
| `npm run cap:open-ios` | Open the Xcode project |
| `npm run cap:sync` | Sync web build to native platforms |
| `npm run cap:build-ios` | Build + sync + open Xcode (full iOS pipeline) |

## Build Verification

```bash
# Type-check + production build (catches all TS errors)
npm run build

# Lint
npm run lint
```

Both should pass with zero errors.

## Testing Manually

### Web (any browser)

1. `npm run dev`
2. Open `http://localhost:3000`

| Feature | How to test |
|---------|-------------|
| **Home page** | Three cards visible (Gym, Home, History). HealthDashboard hidden (no HealthKit on web). |
| **Gym Mode** | Click "Gym Mode" → click "Load example workout" → plan editor appears with sections. Reorder sections/exercises with arrow buttons. Edit exercise names by tapping. Delete with X button. Click "Start Workout". |
| **Plan Editor reordering** | Drag sections or use arrow buttons. Drag exercises between sections. Edit section type, timing, rounds. Delete a section. |
| **Active workout** | After starting, section tabs appear. Timer runs for timed sections. Tap checkmarks to complete sets. Enter reps/weight. Progress bar updates. |
| **Home Mode** | Browse templates. Filter by equipment/style/difficulty. Select a template → creates workout → redirects to tracker. |
| **History** | View past workouts grouped by date. Filter by mode. Delete workouts. |
| **PWA install** | Open in Safari/Chrome on mobile. "Add to Home Screen" prompt appears. App works offline after install. |

### iOS Simulator (no HealthKit)

```bash
# Build and open in Xcode
npm run cap:build-ios

# In Xcode: select a simulator, hit Run (Cmd+R)
```

- Camera uses file picker in simulator (no real camera)
- HealthKit is unavailable — HealthDashboard and HeartRateMonitor gracefully hide
- PWA install prompt will not appear (native app)
- All core workout tracking works identically to web

### iOS Device (with HealthKit)

```bash
npm run cap:build-ios
```

1. In Xcode, select your physical device
2. Sign with your Apple Developer team
3. Run the setup script to configure HealthKit:

```bash
./ios-plugins/setup-xcode.sh
```

4. Follow the manual Xcode steps printed by the script (see below)
5. Build and run on device (Cmd+R)

| Feature | How to test |
|---------|-------------|
| **HealthKit connect** | Home page shows "Connect Health" card. Tap "Connect" → iOS permission dialog. After granting, health metrics appear (resting HR, active calories, workouts, weight). |
| **Heart rate monitor** | Start a workout → heart rate monitor appears below the header. Shows live BPM with zone coloring (Rest/Fat Burn/Cardio/Hard/Peak). |
| **Workout save** | Complete a workout → check Apple Health app → workout appears under Workouts. |
| **Camera** | Gym Mode → tap to photograph → native camera opens. Take photo → transcribe. |

### watchOS (requires paired Apple Watch)

After running `setup-xcode.sh`, you must add the watchOS target manually in Xcode:

1. File > New > Target > watchOS > App
2. Product Name: `WODWatch`
3. Bundle ID: `com.wodtracker.app.watchkitapp`
4. Add HealthKit capability to the watch target
5. Drag Swift files from `ios/App/WODWatch/` into the watch target group
6. Set `WODWatch.entitlements` as the entitlements file
7. Select the watch scheme, build and run

| Feature | How to test |
|---------|-------------|
| **Idle screen** | No workout active → watch shows "WOD Tracker" with quick-start button. |
| **Workout sync** | Start workout on iPhone → watch automatically shows active workout view with timer, current exercise, heart rate, and calories. |
| **Set logging** | Tap exercise name or "Log Set" → SetInputView opens. Use Digital Crown for reps, +/- buttons for weight (5lb increments). Tap "Log Set" → data sent to iPhone, set marked complete. |
| **Quick Done** | "Quick Done" button completes a set without entering data. |
| **Exercise navigation** | Left/right arrows browse through exercises. Exercise counter shows position. |
| **Plan view** | Tap "Plan" → full exercise list grouped by section. Completion indicators: empty circle (not started), half (in progress), full checkmark (done). Tap any exercise → opens set input. |
| **End workout** | Tap "End" on watch → workout completes on iPhone, saved to Health. |

## iOS / Xcode Setup (Detailed)

### 1. Initialize Capacitor iOS

```bash
npm run cap:init-ios    # First time only
npm run cap:build-ios   # Build web, sync, open Xcode
```

### 2. Run the HealthKit setup script

```bash
chmod +x ios-plugins/setup-xcode.sh
./ios-plugins/setup-xcode.sh
```

This copies entitlements, Swift plugin sources, and watchOS files into the Xcode project.

### 3. Manual Xcode configuration

**iPhone App target:**
- Signing & Capabilities > + Capability > **HealthKit**
- Build Settings > Code Signing Entitlements = `App/WODTracker.entitlements`

**Register the HealthKit plugin** in `ios/App/App/AppDelegate.swift`:
```swift
import Capacitor

// In application(_:didFinishLaunchingWithOptions:):
bridge.registerPluginType(WODHealthKitPlugin.self)
```

**Add watchOS target** (see watchOS section above).

### 4. Required Info.plist entries

The setup script adds these automatically:

| Key | Value |
|-----|-------|
| `NSHealthShareUsageDescription` | Explains heart rate, calories, workout reading |
| `NSHealthUpdateUsageDescription` | Explains workout and calorie writing |

## Project Structure

```
src/
  app/
    page.tsx              # Landing page with HealthDashboard
    gym/page.tsx          # Whiteboard photo → transcribe → PlanEditor
    home-workout/page.tsx # HIIT template browser
    workout/[id]/page.tsx # Active workout tracker + watch sync
    history/page.tsx      # Past workouts
    api/
      transcribe/         # Anthropic Vision API for whiteboard OCR
      workouts/           # Workout CRUD
      workouts/[id]/reorder/ # Plan reordering API
      exercises/          # Exercise library
      templates/          # HIIT templates
  components/
    Timer.tsx             # Interval timer with audio beeps
    SetTracker.tsx        # Per-exercise set logging
    PlanEditor.tsx        # Drag-to-reorder plan editor
    HeartRateMonitor.tsx  # Live HR with zone coloring
    HealthDashboard.tsx   # Health summary cards
  lib/
    db.ts                 # SQLite setup (WAL mode, stored in .data/)
    workouts.ts           # Workout CRUD + reorder operations
    exercises.ts          # Exercise seed data
    hiit-templates.ts     # 13 HIIT templates with sources
    camera.ts             # Capacitor Camera bridge
    health/
      health-service.ts   # HealthKit web-side wrapper

ios-plugins/
  healthkit/
    src/definitions.ts    # TypeScript plugin interface
    src/index.ts          # Plugin registration
    src/web.ts            # Web fallback (safe no-ops)
    swift/                # Native Swift HealthKit implementation
    WODTracker.entitlements
    HealthKit-Info.plist
  watchos/
    WODWatchApp.swift     # Watch app entry point
    WatchWorkoutManager.swift # Watch state manager (WCSession)
    ActiveWorkoutView.swift   # Active workout UI
    IdleWatchView.swift       # Idle state UI
    SetInputView.swift        # Reps/weight input (Digital Crown)
    WorkoutPlanView.swift     # Full exercise plan overview
    WODWatch.entitlements
  setup-xcode.sh          # Xcode project configuration script

public/
  sw.js                   # Service worker (network-first caching)
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | No | Enables real whiteboard transcription. Without it, Gym Mode uses demo data. |

## Data Storage

- SQLite database stored in `.data/workouts.db` (outside the web root)
- Database auto-creates on first access with WAL mode enabled
- The `.data/` directory is gitignored

## Security

- CSP, HSTS, X-Frame-Options, and other security headers applied to all routes
- API input validation on all endpoints (size limits, type checks, enum whitelisting)
- SQL injection prevention with parameterized queries and LIKE-clause escaping
- File upload validation (10MB limit, MIME type whitelist)
- API errors logged server-side, generic messages returned to client
- Database stored outside web root
