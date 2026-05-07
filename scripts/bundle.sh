#!/usr/bin/env bash
# Build the Swift Snaplite executable and assemble a .app bundle ready to
# launch from Finder. Output lands in `dist/Snaplite.app`.
set -euo pipefail

# Resolve repo root from this script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_DIR/dist"
APP_DIR="$DIST_DIR/Snaplite.app"
BIN_NAME="Snaplite"

echo "==> Building (release, arm64)..."
cd "$REPO_DIR"
swift build -c release --arch arm64

BUILD_BIN="$REPO_DIR/.build/arm64-apple-macosx/release/$BIN_NAME"
if [[ ! -f "$BUILD_BIN" ]]; then
    echo "ERROR: built binary not found at $BUILD_BIN" >&2
    exit 1
fi

echo "==> Assembling .app at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/$BIN_NAME"
cp "$REPO_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Build AppIcon.icns from the multi-resolution PNG iconset.
ICONSET_DIR="$REPO_DIR/assets/AppIcon.iconset"
if [[ -d "$ICONSET_DIR" ]]; then
    echo "==> Generating AppIcon.icns from $ICONSET_DIR..."
    iconutil -c icns -o "$APP_DIR/Contents/Resources/AppIcon.icns" "$ICONSET_DIR"
else
    echo "WARN: $ICONSET_DIR missing; skipping app icon"
fi

# Ad-hoc sign so Gatekeeper doesn't complain on first launch. The user
# still needs to grant Screen Recording permission once.
echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo
echo "OK: $APP_DIR"
echo
echo "    Drag dist/Snaplite.app to /Applications to install."
echo "    First launch may require Right-click → Open."
echo "    Grant Screen Recording in System Settings → Privacy & Security."
