#!/usr/bin/env zsh
# Build Jarvis.app (Debug by default). Usage: scripts/build.sh [Debug|Release] [--open]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
xcodegen generate --quiet
DERIVED="$PWD/DerivedData"
IDENTITY="${JARVIS_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Jarvis Dev"'; then IDENTITY="Jarvis Dev"; else IDENTITY="-"; fi
fi
APP="$DERIVED/Build/Products/$CONFIG/Jarvis.app"
rm -rf "$APP"
# Xcode only signs with Apple-issued identities (needs a team), so build ad-hoc and re-sign below.
LOG=$(mktemp)
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="${JARVIS_TEAM:-}" \
  build >"$LOG" 2>&1 || true
grep -E "error:|warning: .*App/|BUILD (SUCCEEDED|FAILED)" "$LOG" | grep -vE "DVTPlugIn|IDESimulator" || true
grep -q "BUILD SUCCEEDED" "$LOG" && [ -d "$APP" ] || { echo "build failed (see $LOG)"; exit 1; }
rm -f "$LOG"
# Deep re-sign so embedded frameworks carry the same identity (stable TCC grants).
codesign --force --deep --options runtime --sign "$IDENTITY" --entitlements App/Jarvis.entitlements "$APP" 2>/dev/null || true
echo "signed with: $IDENTITY"
echo "built: $APP"
if [[ "${2:-}" == "--open" ]]; then
  pkill -x Jarvis 2>/dev/null || true
  open "$APP"
fi
