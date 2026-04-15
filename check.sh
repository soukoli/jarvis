#!/bin/bash
# Pre-flight checks before running Jarvis
# Run this to catch issues early

set -e

cd "$(dirname "$0")"

echo "🔍 Jarvis Pre-Flight Checks"
echo "=========================="
echo ""

# 1. Check Python version
echo "1. Checking Python version..."
python3 --version || { echo "❌ Python 3 not found"; exit 1; }
echo "   ✅ Python 3 found"
echo ""

# 2. Check Python dependencies
echo "2. Checking Python dependencies..."
python3 -c "import pynput" 2>/dev/null || { echo "❌ pynput not installed. Run: pip3 install pynput"; exit 1; }
python3 -c "import rumps" 2>/dev/null || { echo "❌ rumps not installed. Run: pip3 install rumps"; exit 1; }
python3 -c "import pyaudio" 2>/dev/null || { echo "❌ pyaudio not installed. Run: pip3 install pyaudio"; exit 1; }
echo "   ✅ All dependencies installed"
echo ""

# 3. Check file structure
echo "3. Checking file structure..."
for file in "jarvis.py" "src/voice_capture.py" "src/speech_to_text.py" "src/settings_dialog.py"; do
    if [ ! -f "$file" ]; then
        echo "   ❌ Missing file: $file"
        exit 1
    fi
done
echo "   ✅ All files present"
echo ""

# 4. Check Python syntax
echo "4. Checking Python syntax..."
python3 -m py_compile jarvis.py src/*.py || { echo "❌ Syntax errors found"; exit 1; }
echo "   ✅ No syntax errors"
echo ""

# 5. Check whisper.cpp
echo "5. Checking whisper.cpp..."
if [ ! -f "whisper.cpp/build/bin/whisper-cli" ]; then
    echo "   ❌ whisper-cli not built. Run: ./setup.sh"
    exit 1
fi
echo "   ✅ whisper-cli built"
echo ""

# 6. Check models
echo "6. Checking whisper models..."
model_found=false
for model in whisper.cpp/models/ggml-*.bin; do
    # Skip test models
    if [[ ! "$model" =~ "for-tests" ]]; then
        if [ -f "$model" ]; then
            model_name=$(basename "$model")
            size=$(du -h "$model" | cut -f1)
            echo "   ✅ Found: $model_name ($size)"
            model_found=true
            break
        fi
    fi
done

if [ "$model_found" = false ]; then
    echo "   ❌ No whisper model found"
    echo "   Run: cd whisper.cpp/models && bash download-ggml-model.sh medium"
    exit 1
fi
echo ""

# 7. Run smoke tests
echo "7. Running smoke tests..."
python3 test_jarvis.py --smoke || { echo "❌ Smoke tests failed"; exit 1; }
echo ""

# 8. Check config file
echo "8. Checking config file..."
if [ -f "$HOME/.jarvis_config.json" ]; then
    echo "   ✅ Config exists"
    python3 -c "import json; json.load(open('$HOME/.jarvis_config.json'))" || {
        echo "   ⚠️  Config file corrupted, will be recreated"
    }
else
    echo "   ℹ️  No config yet (will be created on first run)"
fi
echo ""

echo "=========================="
echo "✅ All checks passed!"
echo ""
echo "Ready to run: ./run.sh"
echo ""
