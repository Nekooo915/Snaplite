#!/usr/bin/env bash
# Render Snaplite's app icon in light and dark appearance for review (used by CI).
#
# Usage:
#   scripts/render-icon.sh [App.app=dist/Snaplite.app] [out-dir=dist/icon-renders]
#
# 1. Icon Composer's `ictool` (ships inside Xcode 26) renders assets/AppIcon.icon
#    per appearance — the same source actool compiles into Assets.car.
# 2. scripts/render-app-icon.swift renders the *compiled* bundle icon through
#    NSWorkspace / IconServices under light and dark NSAppearance.
# Missing tools are reported but never fail the script.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
APP="${1:-$REPO_DIR/dist/Snaplite.app}"
OUT="${2:-$REPO_DIR/dist/icon-renders}"
ICON="$REPO_DIR/assets/AppIcon.icon"
mkdir -p "$OUT"

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
ICTOOL=""
for candidate in \
    "$DEV_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool" \
    /Applications/Xcode*.app/Contents/Applications/Icon\ Composer.app/Contents/Executables/ictool; do
    if [[ -x "$candidate" ]]; then ICTOOL="$candidate"; break; fi
done

if [[ -n "$ICTOOL" ]]; then
    echo "==> ictool: $ICTOOL"
    "$ICTOOL" --help 2>&1 | head -60 || true
    for rendition in Default Dark TintedLight TintedDark ClearLight ClearDark; do
        lower="$(echo "$rendition" | tr '[:upper:]' '[:lower:]')"
        [[ "$lower" == "default" ]] && lower="light"
        dst="$OUT/ictool-$lower-1024.png"
        if "$ICTOOL" "$ICON" --export-image --output-file "$dst" \
                --platform macOS --rendition "$rendition" \
                --width 512 --height 512 --scale 2 2>&1 \
            || "$ICTOOL" "$ICON" --export-preview macOS "$rendition" 512 512 2 "$dst" 2>&1; then
            [[ -f "$dst" ]] && echo "wrote $dst"
        else
            echo "WARN: ictool could not render $rendition" >&2
        fi
    done
else
    echo "WARN: ictool (Icon Composer) not found; skipping source renders" >&2
fi

if [[ -d "$APP" ]]; then
    echo "==> Rendering compiled bundle icon via NSWorkspace..."
    swift "$SCRIPT_DIR/render-app-icon.swift" "$APP" "$OUT" 1024 light -AppleInterfaceStyle Light \
        || echo "WARN: render-app-icon.swift (light) failed" >&2
    # IconServices renders out-of-process using the *system* appearance. On the
    # ephemeral GitHub Actions VM only, flip the CI user's global appearance to
    # Dark for the dark render (and restore it); locally nothing is changed.
    FLIPPED=0
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        defaults write -g AppleInterfaceStyle Dark && FLIPPED=1
        killall iconservicesagent 2>/dev/null || true
        sleep 2
    fi
    swift "$SCRIPT_DIR/render-app-icon.swift" "$APP" "$OUT" 1024 dark -AppleInterfaceStyle Dark \
        || echo "WARN: render-app-icon.swift (dark) failed" >&2
    if [[ "$FLIPPED" == "1" ]]; then
        defaults delete -g AppleInterfaceStyle 2>/dev/null || true
        killall iconservicesagent 2>/dev/null || true
    fi
    if cmp -s "$OUT/compiled-light-1024.png" "$OUT/compiled-dark-1024.png"; then
        echo "NOTE: compiled light/dark renders are identical (IconServices ignored the appearance);" \
             "see ictool-*.png for per-appearance renders of the same .icon source."
    fi
else
    echo "WARN: $APP not found; skipping compiled icon renders" >&2
fi

ls -l "$OUT" 2>/dev/null || true
