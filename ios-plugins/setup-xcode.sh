#!/bin/bash
#
# setup-xcode.sh — Configure the Xcode project for HealthKit + watchOS
#
# Run this AFTER `npx cap sync ios` to patch the generated Xcode project
# with HealthKit entitlements, Info.plist entries, and watchOS target setup.
#
# Usage:
#   chmod +x ios-plugins/setup-xcode.sh
#   ./ios-plugins/setup-xcode.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios/App"
APP_DIR="$IOS_DIR/App"
PLIST="$APP_DIR/Info.plist"

echo "=== WOD Tracker iOS Setup ==="
echo ""

# ─── 1. Check prerequisites ────────────────────────────────────────────

if [ ! -d "$IOS_DIR" ]; then
  echo "Error: ios/App directory not found."
  echo "Run 'npx cap add ios && npx cap sync ios' first."
  exit 1
fi

if ! command -v /usr/libexec/PlistBuddy &>/dev/null; then
  echo "Error: PlistBuddy not found. This script must run on macOS."
  exit 1
fi

PB="/usr/libexec/PlistBuddy"

# ─── 2. Merge Info.plist entries ────────────────────────────────────────

echo "[1/5] Adding HealthKit usage descriptions to Info.plist..."

$PB -c "Add :NSHealthShareUsageDescription string 'WOD Tracker reads your heart rate, resting heart rate, active calories, and workout history to display health metrics and track your training progress.'" "$PLIST" 2>/dev/null || \
$PB -c "Set :NSHealthShareUsageDescription 'WOD Tracker reads your heart rate, resting heart rate, active calories, and workout history to display health metrics and track your training progress.'" "$PLIST"

$PB -c "Add :NSHealthUpdateUsageDescription string 'WOD Tracker saves your completed workouts and calorie data to Apple Health so all your fitness data stays in one place.'" "$PLIST" 2>/dev/null || \
$PB -c "Set :NSHealthUpdateUsageDescription 'WOD Tracker saves your completed workouts and calorie data to Apple Health so all your fitness data stays in one place.'" "$PLIST"

echo "  Done."

# ─── 3. Copy entitlements ──────────────────────────────────────────────

echo "[2/5] Copying entitlements files..."

cp "$SCRIPT_DIR/healthkit/WODTracker.entitlements" "$APP_DIR/WODTracker.entitlements"
echo "  Copied WODTracker.entitlements"

# ─── 4. Copy Swift plugin source ───────────────────────────────────────

echo "[3/5] Copying HealthKit plugin Swift source..."

PLUGIN_DEST="$APP_DIR/Plugins"
mkdir -p "$PLUGIN_DEST"
cp "$SCRIPT_DIR/healthkit/swift/WODHealthKitPlugin.swift" "$PLUGIN_DEST/WODHealthKitPlugin.swift"
echo "  Copied WODHealthKitPlugin.swift"

# ─── 5. Copy watchOS sources ──────────────────────────────────────────

echo "[4/5] Copying watchOS companion app sources..."

WATCH_DEST="$IOS_DIR/WODWatch"
mkdir -p "$WATCH_DEST"
cp "$SCRIPT_DIR/watchos/"*.swift "$WATCH_DEST/"
cp "$SCRIPT_DIR/watchos/WODWatch.entitlements" "$WATCH_DEST/"
echo "  Copied watchOS sources to $WATCH_DEST"

# ─── 6. Print manual steps ────────────────────────────────────────────

echo "[5/5] Setup complete!"
echo ""
echo "=== Manual Xcode Steps Required ==="
echo ""
echo "Open the Xcode project: ios/App/App.xcworkspace"
echo ""
echo "1. iPhone App Target (App):"
echo "   - Signing & Capabilities > + Capability > HealthKit"
echo "   - Check 'Clinical Health Records' if using health records"
echo "   - Build Settings > Code Signing Entitlements = App/WODTracker.entitlements"
echo ""
echo "2. Add watchOS Target:"
echo "   - File > New > Target > watchOS > App"
echo "   - Product Name: WODWatch"
echo "   - Bundle ID: your.bundle.id.watchkitapp"
echo "   - Add HealthKit capability to the watchOS target"
echo "   - Copy files from ios/App/WODWatch/ into the watchOS target group"
echo "   - Set WODWatch.entitlements as the entitlements file"
echo ""
echo "3. Add Plugin to Build:"
echo "   - Drag Plugins/WODHealthKitPlugin.swift into the App target in Xcode"
echo "   - Register the plugin in AppDelegate or Capacitor bridge config"
echo ""
echo "4. Register the Capacitor plugin in ios/App/App/AppDelegate.swift:"
echo '   import Capacitor'
echo ''
echo '   // In application(_:didFinishLaunchingWithOptions:):'
echo '   let bridge = // your Capacitor bridge'
echo '   bridge.registerPluginType(WODHealthKitPlugin.self)'
echo ""
echo "=== Done ==="
