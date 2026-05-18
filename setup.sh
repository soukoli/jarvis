#!/bin/bash
# Jarvis Voice Assistant - One-click setup
set -e

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  🎤 Jarvis Setup                                  ║"
echo "║  Think out loud. Let your voice do the typing.    ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check Apple Silicon
if [[ $(uname -m) == "arm64" ]]; then
    echo "✓ Apple Silicon detected (GPU acceleration enabled)"
else
    echo "⚠️  Not Apple Silicon - will use CPU mode (slower)"
fi

# Check Python
if ! command -v python3 &>/dev/null; then
    echo "❌ Python 3 not found. Install: brew install python"
    exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "✓ Python $PYTHON_VERSION"

# Check Homebrew
if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew not found. Install: https://brew.sh"
    exit 1
fi
echo "✓ Homebrew"

echo ""

# Step 1: System dependencies
echo "[1/4] Installing system dependencies..."
brew list portaudio &>/dev/null || brew install portaudio
echo "  ✓ portaudio"

# Step 2: Python dependencies
echo "[2/4] Installing Python packages..."
pip3 install --quiet \
    pynput \
    rumps \
    pyaudio \
    setproctitle \
    numpy \
    torch \
    torchaudio \
    mlx-whisper \
    faster-whisper \
    silero-vad
echo "  ✓ All packages installed"

# Step 3: Download model
echo "[3/4] Downloading Whisper model (~1.5GB, one-time)..."
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('mlx-community/whisper-large-v3-turbo', local_dir_use_symlinks=True)
print('  ✓ Model downloaded')
" 2>/dev/null || {
    echo "  ⚠️  Model download failed (will retry on first run)"
}

# Step 4: Verify
echo "[4/4] Verifying installation..."
python3 -c "
import mlx_whisper, silero_vad, pyaudio, pynput, rumps, numpy, torch
print('  ✓ All imports OK')
" || {
    echo "❌ Verification failed. Check errors above."
    exit 1
}

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✅ Setup complete!                               ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "  1. Grant Input Monitoring permission:"
echo "     System Settings → Privacy & Security → Input Monitoring"
echo "     → Add Terminal (or your terminal app)"
echo "     → Restart Terminal"
echo ""
echo "  2. Run Jarvis:"
echo "     ./run.sh"
echo ""
echo "  3. Use:"
echo "     Cmd+;  → Start speaking"
echo "     Cmd+'  → Stop & transcribe"
echo "     Cmd+V  → Paste anywhere"
echo ""
