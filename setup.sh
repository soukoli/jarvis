#!/bin/bash
# Setup dependencies for Jarvis

set -e

echo "🎤 Jarvis Setup"
echo ""

# Check homebrew
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew required: https://brew.sh"
    exit 1
fi

# Install system dependencies
echo "[1/3] Installing system dependencies..."
brew list portaudio &>/dev/null || brew install portaudio
brew list cmake &>/dev/null || brew install cmake

# Install Python dependencies
echo "[2/3] Installing Python dependencies..."
pip3 install --quiet pynput rumps pyaudio setproctitle

# Build whisper.cpp
echo "[3/3] Building whisper.cpp..."
if [ ! -d "whisper.cpp" ]; then
    git clone --quiet https://github.com/ggerganov/whisper.cpp.git
fi

cd whisper.cpp

# Rebuild if binary doesn't work or if we detect it was moved
if [ -f "build/bin/whisper-cli" ]; then
    # Test if binary works
    if ! ./build/bin/whisper-cli --help &>/dev/null; then
        echo "   Detected moved folder - rebuilding..."
        rm -rf build
    fi
fi

# Build if needed
if [ ! -f "build/bin/whisper-cli" ]; then
    echo "   Building whisper.cpp (this may take a minute)..."
    cmake -B build >/dev/null && cmake --build build --config Release >/dev/null
fi

# Download model if needed
[ ! -f "models/ggml-base.en.bin" ] && bash ./models/download-ggml-model.sh base.en
cd ..

echo ""
echo "✅ Setup complete! Run: ./run.sh"
