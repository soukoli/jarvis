#!/usr/bin/env zsh
# Jarvis Voice Assistant - Terminal launcher

cd "$(dirname "$0")"

# Detect Python (mise first, then fallbacks)
PYTHON=""
if command -v mise &>/dev/null; then
    PYTHON=$(mise which python 2>/dev/null)
fi
[ -z "$PYTHON" ] && PYTHON="$HOME/.local/share/mise/installs/python/3.12.12/bin/python3"
[ ! -f "$PYTHON" ] && PYTHON=$(which python3 2>/dev/null)

# Verify Python exists
if [ -z "$PYTHON" ] || [ ! -f "$PYTHON" ]; then
    echo "❌ Python not found"
    exit 1
fi

# Launch Jarvis
exec $PYTHON jarvis.py

cat << 'EOF'

╔════════════════════════════════════════════════════╗
║  🎤 JARVIS VOICE ASSISTANT                        ║
╚════════════════════════════════════════════════════╝

Controls:
  Cmd+;  = START recording
  Cmd+'  = STOP recording

Feedback:
  🔴 Menu bar → Recording
  🧠 Menu bar → Transcribing (wait!)
  🔊 Sound    → Ready to paste
  🎤 Menu bar → Back to ready

EOF

exec $PYTHON jarvis.py


