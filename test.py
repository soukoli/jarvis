#!/usr/bin/env python3
"""
Test script for Jarvis components
"""
import os
import sys

def test_imports():
    """Test if all dependencies are installed"""
    print("🧪 Testing imports...")
    try:
        import pyaudio
        print("  ✅ pyaudio")
    except ImportError as e:
        print(f"  ❌ pyaudio: {e}")
        return False

    try:
        from pynput import keyboard
        print("  ✅ pynput")
    except ImportError as e:
        print(f"  ❌ pynput: {e}")
        return False

    try:
        import wave
        print("  ✅ wave")
    except ImportError as e:
        print(f"  ❌ wave: {e}")
        return False

    return True


def test_whisper():
    """Test if whisper.cpp is built"""
    print("\n🧪 Testing whisper.cpp...")

    whisper_cli = "whisper.cpp/build/bin/whisper-cli"
    model = "whisper.cpp/models/ggml-base.en.bin"

    if not os.path.exists(whisper_cli):
        print(f"  ❌ whisper-cli not found at {whisper_cli}")
        return False
    print(f"  ✅ whisper-cli found")

    if not os.path.exists(model):
        print(f"  ❌ Model not found at {model}")
        return False
    print(f"  ✅ Model found")

    return True


def test_claude_cli():
    """Test if claude CLI is available"""
    print("\n🧪 Testing Claude CLI...")
    import subprocess
    import shutil

    # Try both names
    for cmd in ["claude", "claude-code"]:
        if shutil.which(cmd):
            try:
                result = subprocess.run(
                    [cmd, "--version"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                print(f"  ✅ Found: {cmd}")
                return True
            except:
                pass

    print("  ❌ Claude CLI not found in PATH")
    print("     Searched for: claude, claude-code")
    print("     Make sure Claude Code CLI is installed")
    return False


def main():
    print("=" * 50)
    print("🚀 Jarvis System Test")
    print("=" * 50)
    print()

    all_tests_passed = True

    all_tests_passed &= test_imports()
    all_tests_passed &= test_whisper()
    all_tests_passed &= test_claude_cli()

    print("\n" + "=" * 50)
    if all_tests_passed:
        print("✅ All tests passed! Jarvis is ready to run.")
        print("\n🎤 Start with: ./jarvis.sh")
    else:
        print("⚠️  Some tests failed. Please fix the issues above.")
        sys.exit(1)
    print("=" * 50)


if __name__ == "__main__":
    main()
