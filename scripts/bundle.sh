#!/usr/bin/env bash
# Build the Swift Snaplite executable and assemble a .app bundle ready to
# launch from Finder. Output lands in `dist/Snaplite.app`.
#
# Usage:
#   scripts/bundle.sh [--arm64-only]
#
# Environment variables:
#   SIGN_ID   Code signing identity (e.g. "Snaplite Local" or "Developer ID Application: ...").
#             When set, signs with hardened runtime (no deprecated --deep).
#             When unset, falls back to ad-hoc signing (`-`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_DIR/dist"
APP_DIR="$DIST_DIR/Snaplite.app"
BIN_NAME="Snaplite"

ARM64_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arm64-only)
            ARM64_ONLY=1
            shift
            ;;
        -h|--help)
            sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

ARCH_FLAGS=()
if [[ "$ARM64_ONLY" -eq 1 ]]; then
    ARCH_FLAGS=(--arch arm64)
    ARCH_LABEL="arm64"
else
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
    ARCH_LABEL="universal (arm64 + x86_64)"
fi

BUILD_FLAGS=(
    -c release
    "${ARCH_FLAGS[@]}"
    -Xswiftc -Osize
    -Xswiftc -whole-module-optimization
    -Xlinker -dead_strip
    -Xlinker -dead_strip_dylibs
)

echo "==> Building ($ARCH_LABEL, release, -Osize, -whole-module-optimization, -dead_strip)..."
cd "$REPO_DIR"
swift build "${BUILD_FLAGS[@]}"

BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
BUILD_BIN="$BIN_DIR/$BIN_NAME"
if [[ ! -f "$BUILD_BIN" ]]; then
    # Fallback paths across SwiftPM build engines (swiftbuild vs legacy native).
    for candidate in \
        "$REPO_DIR/.build/apple/Products/Release/$BIN_NAME" \
        "$REPO_DIR/.build/out/Products/Release/$BIN_NAME" \
        "$REPO_DIR/.build/arm64-apple-macosx/release/$BIN_NAME"; do
        if [[ -f "$candidate" ]]; then
            BUILD_BIN="$candidate"
            break
        fi
    done
fi

if [[ ! -f "$BUILD_BIN" ]]; then
    echo "ERROR: built binary not found (checked $BIN_DIR/$BIN_NAME)" >&2
    exit 1
fi

echo "==> Assembling .app at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/$BIN_NAME"
cp "$REPO_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Strip local symbols before stamping/signing to keep binary size tight.
echo "==> Stripping binary..."
strip -x "$APP_DIR/Contents/MacOS/$BIN_NAME"

# SwiftPM stamps LC_BUILD_VERSION with sdk == deployment target (14.0), which
# puts macOS 26+ into pre-Liquid-Glass compatibility mode. Re-stamp with the
# active SDK version while preserving the deployment target (minos 14.0).
SDK_VER="$(xcrun --show-sdk-version)"
MIN_MACOS="14.0"
if [[ -x /usr/libexec/PlistBuddy ]]; then
    PLIST_MIN="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
    [[ -n "$PLIST_MIN" ]] && MIN_MACOS="$PLIST_MIN"
fi
echo "==> Stamping LC_BUILD_VERSION (macos minos=$MIN_MACOS, sdk=$SDK_VER)..."
vtool -set-build-version macos "$MIN_MACOS" "$SDK_VER" -replace \
    -output "$APP_DIR/Contents/MacOS/$BIN_NAME" \
    "$APP_DIR/Contents/MacOS/$BIN_NAME"

# Build app icon: prefer Icon Composer (.icon -> Assets.car) via actool when
# Xcode is installed; otherwise fall back cleanly to AppIcon.iconset -> .icns.
ICON_BUNDLE="$REPO_DIR/assets/AppIcon.icon"
ICONSET_DIR="$REPO_DIR/assets/AppIcon.iconset"
ACTOOL_BIN="$(xcrun --find actool 2>/dev/null || true)"

if [[ -n "$ACTOOL_BIN" && -d "$ICON_BUNDLE" ]]; then
    echo "==> Compiling $ICON_BUNDLE with actool (Assets.car + fallback .icns)..."
    PARTIAL_PLIST="$(mktemp -t snaplite-icon-plist)"
    trap 'rm -f "$PARTIAL_PLIST"' EXIT
    ACTOOL_LOG="$DIST_DIR/actool-output.txt"
    "$ACTOOL_BIN" "$ICON_BUNDLE" \
        --compile "$APP_DIR/Contents/Resources" \
        --app-icon AppIcon \
        --include-all-app-icons \
        --enable-on-demand-resources NO \
        --development-region en \
        --target-device mac \
        --minimum-deployment-target "$MIN_MACOS" \
        --platform macosx \
        --errors --warnings --notices \
        --output-format human-readable-text \
        --output-partial-info-plist "$PARTIAL_PLIST" >"$ACTOOL_LOG" 2>&1 || {
            cat "$ACTOOL_LOG" >&2
            echo "ERROR: actool failed to compile $ICON_BUNDLE" >&2
            exit 1
        }
    sed 's/^/    actool: /' "$ACTOOL_LOG"
    # ACTOOL_STRICT=1 (used in CI): any actool warning or error fails the build.
    if [[ "${ACTOOL_STRICT:-0}" == "1" ]] && grep -Eiq '(warning|error):' "$ACTOOL_LOG"; then
        echo "ERROR: actool reported warnings/errors (ACTOOL_STRICT=1)" >&2
        exit 1
    fi
    # Ensure CFBundleIconName is set in the assembled bundle's Info.plist so
    # macOS 26+ resolves the layered Liquid Glass icon from Assets.car.
    if [[ -x /usr/libexec/PlistBuddy ]]; then
        if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1; then
            /usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string AppIcon' "$APP_DIR/Contents/Info.plist"
        fi
    fi
    # Ensure legacy macOS 14/15 fallback .icns also exists alongside Assets.car.
    if [[ ! -f "$APP_DIR/Contents/Resources/AppIcon.icns" && -d "$ICONSET_DIR" ]]; then
        iconutil -c icns -o "$APP_DIR/Contents/Resources/AppIcon.icns" "$ICONSET_DIR"
    fi
elif [[ -d "$ICONSET_DIR" ]]; then
    echo "==> Generating AppIcon.icns from $ICONSET_DIR (actool unavailable)..."
    iconutil -c icns -o "$APP_DIR/Contents/Resources/AppIcon.icns" "$ICONSET_DIR"
else
    echo "WARN: neither $ICON_BUNDLE (with actool) nor $ICONSET_DIR found; skipping app icon" >&2
fi

# Code signing (never use deprecated --deep).
if [[ -n "${SIGN_ID:-}" ]]; then
    echo "==> Signing with identity: $SIGN_ID (hardened runtime)..."
    codesign --force --options runtime --sign "$SIGN_ID" "$APP_DIR"
else
    echo "==> Ad-hoc signing (SIGN_ID not set)..."
    codesign --force --sign - "$APP_DIR"
    echo "WARN: Signed ad-hoc (--sign -). macOS TCC Screen Recording permission will NOT" >&2
    echo "      persist across rebuilds. To preserve permission locally, create a self-signed" >&2
    echo "      code signing cert (e.g. \"Snaplite Local\") and run: SIGN_ID=\"Snaplite Local\" $0" >&2
fi

BIN_BYTES="$(stat -f '%z' "$APP_DIR/Contents/MacOS/$BIN_NAME")"
BIN_KB="$(awk -v b="$BIN_BYTES" 'BEGIN { printf "%.1f", b / 1024.0 }')"
ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/$BIN_NAME" 2>/dev/null || echo "$ARCH_LABEL")"

echo
echo "OK: $APP_DIR"
echo "    Binary: ${BIN_BYTES} bytes (${BIN_KB} KB) [${ARCHS}] (macos minos=${MIN_MACOS}, sdk=${SDK_VER})"
if [[ -f "$APP_DIR/Contents/Resources/Assets.car" ]]; then
    echo "    Icon:   Assets.car (Liquid Glass) + AppIcon.icns (CFBundleIconName=AppIcon)"
elif [[ -f "$APP_DIR/Contents/Resources/AppIcon.icns" ]]; then
    echo "    Icon:   AppIcon.icns"
fi
echo
echo "    Drag dist/Snaplite.app to /Applications to install."
echo "    Grant Screen Recording in System Settings → Privacy & Security."
