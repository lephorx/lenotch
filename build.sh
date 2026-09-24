#!/usr/bin/env bash
# Builds build/Lenotch.app.
#   ./build.sh           build only
#   ./build.sh run       build and (re)launch from build/
#   ./build.sh install   build, copy to /Applications and launch
#   ./build.sh dmg       build and package build/Lenotch.dmg
#
# Environment:
#   CONFIG=debug|release      build configuration (default release)
#   ARCHS="arm64 x86_64"      architectures (default: this Mac's)
#   VERSION=2.1 BUILD=42      override the app's version and build number
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="build/Lenotch.app"

ARCH_FLAGS=()
for arch in ${ARCHS:-}; do ARCH_FLAGS+=(--arch "$arch"); done

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lenotch" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Vendor/MediaRemoteAdapter "$APP/Contents/Resources/"
cp Resources/logo-white.png Resources/AppIcon.icns Resources/glyph-amp.svg "$APP/Contents/Resources/"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi
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
  dmg)
    DMG="build/Lenotch.dmg"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname Lenotch -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    echo "Built $DMG"
    ;;
esac
