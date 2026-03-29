#!/bin/bash
# Simple launcher for Jarvis

cd "$(dirname "$0")"

# Fix notifications
PYTHON_BIN=$(python3 -c "import sys; print(sys.prefix + '/bin')")
PLIST="$PYTHON_BIN/Info.plist"
[ ! -f "$PLIST" ] && /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string "com.jarvis"' "$PLIST" 2>/dev/null || true

# Check deps
python3 -c "import rumps" 2>/dev/null || pip3 install rumps

cat << 'EOF'

╔════════════════════════════════════════════════════╗
║  🎤 JARVIS VOICE ASSISTANT                        ║
╚════════════════════════════════════════════════════╝

Controls:
  Cmd+;  = START recording (⌘+;)
  Cmd+'  = STOP recording  (⌘+')

Transcription auto-types at cursor! ✨
EOF

python3 jarvis.py
