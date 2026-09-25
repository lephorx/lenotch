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
#   SIGN_IDENTITY="…"          signing identity (default: your Apple Development cert, else ad-hoc)
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
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Lenotch"
cp Resources/Info.plist "$APP/Contents/"
cp -R Vendor/MediaRemoteAdapter "$APP/Contents/Resources/"
cp Resources/logo-white.png Resources/AppIcon.icns Resources/glyph-amp.svg "$APP/Contents/Resources/"
if [ "${1:-}" = dmg ]; then
  cp Resources/installer-background.png "$APP/Contents/Resources/"
fi
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  # Only released versions show What's New after an update.
  /usr/libexec/PlistBuddy -c "Add :LenotchRelease bool true" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi
SPARKLE_SOURCE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_DEST="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_SOURCE" "$SPARKLE_DEST"
# Lenotch is not sandboxed, so Sparkle's XPC services are unnecessary.
rm -rf "$SPARKLE_DEST/Versions/B/XPCServices" "$SPARKLE_DEST/XPCServices"
codesign --force --sign - "$SPARKLE_DEST/Versions/B/Autoupdate"
codesign --force --sign - "$SPARKLE_DEST/Versions/B/Updater.app"
codesign --force --sign - "$SPARKLE_DEST"
# Sign with a real certificate when there is one: macOS keeps permissions (calendar,
# camera, automation…) for the same signer across builds. Ad-hoc signatures are tied
# to the exact binary, so every rebuild would lose them. SIGN_IDENTITY=- forces ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"

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
    if ! command -v create-dmg >/dev/null 2>&1; then
      echo "create-dmg is required to package the installer (brew install create-dmg)" >&2
      exit 1
    fi
    DMG="build/Lenotch.dmg"
    STAGE="$(mktemp -d)"
    MOUNT="$(mktemp -d)"
    trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$MOUNT"' EXIT
    cp -R "$APP" "$STAGE/"
    rm -f "$DMG"
    create-dmg \
      --volname "Lenotch Installer" \
      --window-pos 160 120 \
      --window-size 600 340 \
      --text-size 14 \
      --icon-size 112 \
      --icon "Lenotch.app" 155 165 \
      --hide-extension "Lenotch.app" \
      --app-drop-link 445 165 \
      --skip-finalize \
      "$DMG" "$STAGE"
    hdiutil attach -readwrite -nobrowse -mountpoint "$MOUNT" "$DMG" -quiet
    STYLED=0
    for attempt in 1 2 3 4 5; do
      if osascript scripts/style_dmg.applescript "$(basename "$MOUNT")" "$MOUNT"; then
        STYLED=1
        break
      fi
      sleep 2
    done
    if [ "$STYLED" -ne 1 ]; then
      echo "Finder could not style the installer window" >&2
      exit 1
    fi
    hdiutil detach "$MOUNT" -quiet
    rm -f "${DMG%.dmg}-compressed.dmg"
    hdiutil convert "$DMG" -format UDBZ -o "${DMG%.dmg}-compressed.dmg" -quiet
    mv "${DMG%.dmg}-compressed.dmg" "$DMG"
    echo "Built $DMG"
    ;;
esac
