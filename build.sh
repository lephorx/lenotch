#!/bin/bash
# Builds LephorNotch.app into dist/. Pass --run to launch it afterwards.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
APP="dist/LephorNotch.app"

echo "▸ compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/LephorNotch"

echo "▸ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LephorNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# An ad-hoc signature with a stable identifier keeps the app's TCC grants (Automation,
# Accessibility, Calendars) across rebuilds instead of re-prompting every launch.
echo "▸ signing"
codesign --force --deep \
  --sign - \
  --identifier com.lephor.notch \
  --entitlements Resources/LephorNotch.entitlements \
  --options runtime \
  "$APP" 2>&1 | sed 's/^/  /'

echo "✓ $APP"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x LephorNotch 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "✓ launched"
fi
