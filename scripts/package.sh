#!/usr/bin/env zsh
# Build a Release Jarvis.app and package it as a .dmg and a .pkg in dist/.
#
# Usage: scripts/package.sh [--install]
#   --install   also copy Jarvis.app to /Applications and launch it
#
# Signing: uses $JARVIS_SIGN_IDENTITY (default "-" = ad-hoc). Ad-hoc builds run on this Mac; on
# other Macs Gatekeeper requires right-click → Open the first time (or a Developer ID + notarization,
# see docs/PLAN.md M3). $JARVIS_TEAM sets DEVELOPMENT_TEAM for automatic signing.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/[^0-9]//g')
# Prefer a stable local identity over ad-hoc: TCC (Accessibility, Microphone) binds grants to the
# signing certificate, so a "Jarvis Dev" self-signed cert survives rebuilds. See scripts/make-dev-cert.sh.
IDENTITY="${JARVIS_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Jarvis Dev"'; then IDENTITY="Jarvis Dev"; else IDENTITY="-"; fi
fi
DERIVED="$PWD/DerivedData"
DIST="$PWD/dist"
APP="$DERIVED/Build/Products/Release/Jarvis.app"

echo "▶ Building Jarvis $VERSION ($BUILD), signing identity: $IDENTITY"
rm -rf "$APP"
# Xcode only signs with Apple-issued identities (needs a team), so build ad-hoc and re-sign below.
LOG=$(mktemp)
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="${JARVIS_TEAM:-}" \
  build >"$LOG" 2>&1 || true
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$LOG" | grep -vE "DVTPlugIn|IDESimulator" || true
grep -q "BUILD SUCCEEDED" "$LOG" && [ -d "$APP" ] || { echo "build failed (see $LOG)"; exit 1; }
rm -f "$LOG"

# Re-sign the whole bundle deep so embedded frameworks/xcframeworks carry the same identity.
codesign --force --deep --options runtime --sign "$IDENTITY" --entitlements App/Jarvis.entitlements "$APP"
codesign --verify --deep --strict "$APP" && echo "▶ codesign OK ($(codesign -dv "$APP" 2>&1 | grep -E '^Signature' | cut -d= -f2))"

mkdir -p "$DIST"
rm -f "$DIST"/Jarvis-"$VERSION".{dmg,pkg}

# DMG: drag-to-Applications layout.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Jarvis $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Jarvis-$VERSION.dmg"
rm -rf "$STAGE"
echo "▶ $DIST/Jarvis-$VERSION.dmg"

# PKG: installs into /Applications (what SAP Self Service / Jamf consume).
PKGROOT=$(mktemp -d)
mkdir -p "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/"
pkgbuild --quiet --root "$PKGROOT" --identifier com.sap.jarvis.pkg --version "$VERSION" \
  --install-location / "$DIST/Jarvis-$VERSION.pkg"
rm -rf "$PKGROOT"
echo "▶ $DIST/Jarvis-$VERSION.pkg"

if [[ "${1:-}" == "--install" ]]; then
  # Prefer /Applications. On managed Macs it is admin-only: with temporary admin rights
  # (Privileges app) sudo works; otherwise fall back to ~/Applications, which Spotlight and
  # Launchpad index as well.
  TARGET=/Applications
  SUDO=""
  if [[ ! -w /Applications ]]; then
    if [[ -t 0 ]] && sudo -v -p "Admin password for /Applications (Enter to skip → ~/Applications): " 2>/dev/null; then
      SUDO=sudo
    else
      TARGET="$HOME/Applications"; mkdir -p "$TARGET"
      echo "ℹ️  /Applications is not writable; installing to ~/Applications instead."
      echo "   For /Applications, get admin rights first (Privileges app) and re-run."
    fi
  fi
  pkill -x Jarvis 2>/dev/null || true
  $SUDO rm -rf "$TARGET/Jarvis.app"
  $SUDO cp -R "$APP" "$TARGET/Jarvis.app"
  # Avoid two copies: remove the one in the other location when we can.
  if [[ "$TARGET" == /Applications ]]; then
    rm -rf "$HOME/Applications/Jarvis.app"
  elif [[ -d /Applications/Jarvis.app ]]; then
    echo "⚠️  An older copy remains in /Applications (admin rights needed to remove it)."
  fi
  open "$TARGET/Jarvis.app"
  echo "▶ installed and launched $TARGET/Jarvis.app"
fi
