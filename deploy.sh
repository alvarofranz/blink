#!/bin/bash
#
# deploy.sh — build Blink, install it, and launch it on a connected iPhone in one go.
#
# Usage:  ./deploy.sh
#
# The first build is slow; later builds are INCREMENTAL (only what changed is
# recompiled), so iterating is fast.
#
# The iPhone must be reachable (USB cable, or Wi-Fi if "Connect via network" is
# enabled in Xcode -> Window -> Devices and Simulators).
#
# Device selection: set BLINK_DEVICE_ID to target a specific device; otherwise
# the first connected device is auto-detected.

set -e
cd "$(dirname "$0")"

BUNDLE_ID="com.alvarofranz.blink"
APP_PATH="build/Build/Products/Debug-iphoneos/Blink.app"

DEVICE_ID="${BLINK_DEVICE_ID:-$(xcrun devicectl list devices 2>/dev/null \
  | grep -iE 'connected|available' | grep -ivE 'unavailable' \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  | head -1)}"

if [ -z "$DEVICE_ID" ]; then
  echo "No connected device found. Plug in your iPhone, or set BLINK_DEVICE_ID." >&2
  exit 1
fi
echo "▶︎  Device: $DEVICE_ID"

echo "▶︎  Building Blink (incremental)…"
xcodebuild \
  -project Blink.xcodeproj \
  -scheme Blink \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  -quiet \
  build

echo "▶︎  Installing on device…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "▶︎  Launching Blink…"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "✅  Blink updated on your iPhone."
