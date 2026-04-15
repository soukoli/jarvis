#!/usr/bin/env zsh
# Jarvis Voice Assistant - Simple launcher

cd "$(dirname "$0")"

# Detect Python (mise first, then fallbacks)
PYTHON=""
if command -v mise &>/dev/null; then
    PYTHON=$(mise which python 2>/dev/null)
fi
[ -z "$PYTHON" ] && PYTHON="$HOME/.local/share/mise/installs/python/3.12.12/bin/python3"
[ ! -f "$PYTHON" ] && PYTHON=$(which python3 2>/dev/null)

if [ -z "$PYTHON" ] || [ ! -f "$PYTHON" ]; then
    echo "❌ Python not found"
    exit 1
fi

echo "🚀 Starting Jarvis..."
exec $PYTHON jarvis.py

