#!/bin/bash
# Setup script for Jarvis Voice Coding Assistant

set -e

echo "🚀 Setting up Jarvis Voice Coding Assistant..."
echo

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required"
    exit 1
fi

echo "✅ Python found"

# Check and install dependencies for macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v brew &> /dev/null; then
        echo "⚠️  Homebrew not found. Install from: https://brew.sh"
        echo "   Then run this script again"
        exit 1
    fi

    echo "📦 Installing system dependencies via Homebrew..."
    brew install portaudio cmake || {
        echo "⚠️  Failed to install dependencies"
        exit 1
    }
fi

# Install Python dependencies
echo "📦 Installing Python dependencies..."
pip3 install pynput || {
    echo "❌ Failed to install pynput"
    exit 1
}

# PyAudio with portaudio support
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "📦 Installing PyAudio..."
    CFLAGS="-I$(brew --prefix portaudio)/include" LDFLAGS="-L$(brew --prefix portaudio)/lib" pip3 install pyaudio || {
        echo "❌ Failed to install PyAudio"
        exit 1
    }
else
    pip3 install pyaudio || {
        echo "❌ Failed to install PyAudio"
        exit 1
    }
fi

echo "✅ Python dependencies installed"

# Clone and build whisper.cpp
echo "📥 Setting up whisper.cpp..."

if [ ! -d "whisper.cpp" ]; then
    git clone https://github.com/ggerganov/whisper.cpp.git
    cd whisper.cpp

    # Build whisper.cpp with cmake
    echo "🔨 Building whisper.cpp..."
    cmake -B build
    cmake --build build --config Release

    cd ..
else
    echo "✅ whisper.cpp already exists"
fi

# Download Whisper model
echo "📥 Downloading Whisper model (base.en - ~150MB)..."

if [ ! -f "whisper.cpp/models/ggml-base.en.bin" ]; then
    cd whisper.cpp
    bash ./models/download-ggml-model.sh base.en
    cd ..
else
    echo "✅ Model already downloaded"
fi

# Make scripts executable
chmod +x jarvis.py

echo
echo "✅ Setup complete!"
echo
echo "🎤 Run Jarvis with: ./jarvis.py"
echo "   Or: python3 jarvis.py [working-directory]"
echo
