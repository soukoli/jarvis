#!/usr/bin/env python3
"""
Demo script - Shows how to use Jarvis in different modes
"""
import os
import sys

print("""
╔══════════════════════════════════════════════════════════╗
║  🎤 JARVIS - Voice Coding Assistant                     ║
╚══════════════════════════════════════════════════════════╝

Setup complete! Here's how to use Jarvis:

┌─────────────────────────────────────────────────────────┐
│ MODE 1: Full Integration (Recommended)                  │
└─────────────────────────────────────────────────────────┘

Run Jarvis with Claude Code CLI integration:

   ./jarvis.sh

Usage:
  1. Hold SPACE to record
  2. Say: "Claude refactor this function"
  3. Release SPACE
  4. Watch Claude Code execute automatically

Example commands:
  🗣️  "Claude create a React component for login"
  🗣️  "Fix the authentication bug"
  🗣️  "Write tests for the API module"
  🗣️  "Refactor the database connection code"

┌─────────────────────────────────────────────────────────┐
│ MODE 2: Text-Only Mode (Testing)                        │
└─────────────────────────────────────────────────────────┘

If you want to test the speech-to-text pipeline:

   python3 voice_capture.py

This will just show you what Whisper transcribes (no Claude).

┌─────────────────────────────────────────────────────────┐
│ TIPS                                                     │
└─────────────────────────────────────────────────────────┘

• Speak clearly and at normal pace
• Include "Claude" in your command for best results
• Press ESC to quit anytime
• Run from any project directory:
    ./jarvis.sh /path/to/your/project

┌─────────────────────────────────────────────────────────┐
│ TROUBLESHOOTING                                          │
└─────────────────────────────────────────────────────────┘

If recording doesn't work:
  - Check microphone permissions in System Settings
  - Try: python3 -c "import pyaudio; p=pyaudio.PyAudio()"

If Claude commands don't execute:
  - Jarvis outputs the transcribed text
  - You can copy/paste it into Claude Code manually
  - Or use MODE 2 for testing

Ready to start? Run: ./jarvis.sh
""")
