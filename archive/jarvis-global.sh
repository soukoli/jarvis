#!/bin/bash
# Launcher for Jarvis Global App

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting Jarvis Global..."
echo "   System-wide voice assistant"
echo "   Will appear in menu bar"
echo

# Check dependencies
if ! python3 -c "import rumps" 2>/dev/null; then
    echo "📦 Installing rumps (menu bar support)..."
    pip3 install rumps
fi

# Fix notification center plist if needed
PYTHON_BIN_DIR=$(python3 -c "import sys; print(sys.prefix + '/bin')")
PLIST_FILE="$PYTHON_BIN_DIR/Info.plist"

if [ ! -f "$PLIST_FILE" ]; then
    echo "🔧 Setting up notification center..."
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string "com.jarvis.voice"' "$PLIST_FILE" 2>/dev/null
    echo "   ✅ Done"
fi

echo "🎤 Launching..."
echo "   Press \` (backtick) anywhere to start/stop recording"
echo "   Transcription will be typed into active window"
echo

python3 jarvis_global.py
