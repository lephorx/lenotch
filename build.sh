#!/usr/bin/env bash
# Builds build/Lenotch.app.
#   ./build.sh           build only
#   ./build.sh run       build and (re)launch from build/
#   ./build.sh install   build, copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="build/Lenotch.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lenotch" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Vendor/MediaRemoteAdapter "$APP/Contents/Resources/"
cp Resources/logo.png Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"

# Quit a running copy and wait for it to exit before relaunching.
quit_running() {
  # LephorNotch is the app's old name.
  pkill -x Lenotch || true
  pkill -x LephorNotch || true
  while pgrep -x Lenotch >/dev/null || pgrep -x LephorNotch >/dev/null; do sleep 0.1; done
}

case "${1:-}" in
  run)
    quit_running
    open "$APP"
    ;;
  install)
    quit_running
    rm -rf /Applications/Lenotch.app /Applications/LephorNotch.app
    cp -R "$APP" /Applications/
    open /Applications/Lenotch.app
    echo "Installed to /Applications"
    ;;
esac
