#!/usr/bin/env zsh
# Jarvis Voice Assistant - Simple launcher

cd "$(dirname "$0")"

# Detect Python (mise first, then newest mise install, then PATH)
PYTHON=""
if command -v mise &>/dev/null; then
    PYTHON=$(mise which python 2>/dev/null)
fi
if [ -z "$PYTHON" ] || [ ! -f "$PYTHON" ]; then
    # No mise, or no active version: take the newest installed mise Python.
    for candidate in "$HOME"/.local/share/mise/installs/python/3.*/bin/python3(N); do
        PYTHON="$candidate"
    done
fi
[ -z "$PYTHON" ] || [ ! -f "$PYTHON" ] && PYTHON=$(which python3 2>/dev/null)

if [ -z "$PYTHON" ] || [ ! -f "$PYTHON" ]; then
    echo "❌ Python not found"
    exit 1
fi

# rumps needs an Info.plist with CFBundleIdentifier next to the interpreter,
# otherwise rumps.notification() raises and the app cannot show notifications.
# A bare mise/pyenv Python ships without one, so create it on first run.
PLIST="$(dirname "$(realpath "$PYTHON")")/Info.plist"
if [ ! -f "$PLIST" ]; then
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string "rumps"' "$PLIST" >/dev/null 2>&1 \
        && echo "ℹ️  Created $PLIST for rumps notifications"
fi

echo "🚀 Starting Jarvis (${PYTHON})..."
exec $PYTHON jarvis.py

