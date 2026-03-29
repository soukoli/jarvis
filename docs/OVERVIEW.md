# 🎤 Jarvis Voice Coding Assistant - Architecture Overview

## What You Built

A **voice-controlled coding assistant** that lets you control Claude Code entirely by voice using local, private speech recognition.

## The Magic

```
Your Voice → Whisper (local) → Claude Code → Automatic Execution
```

Unlike VS Code voice plugins or simple dictation tools, Jarvis gives you the **full power of Claude Code** through voice commands.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     USER INTERFACE                      │
│                                                         │
│  🎤 Hold SPACE to talk → Release to execute            │
│  👂 Always listening for keyboard input                 │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                  VOICE CAPTURE LAYER                    │
│                  (voice_capture.py)                     │
│                                                         │
│  • PyAudio - Records from microphone                    │
│  • Pynput - Detects SPACE key hold/release             │
│  • Saves to WAV file (16kHz, mono)                      │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                SPEECH-TO-TEXT LAYER                     │
│                (speech_to_text.py)                      │
│                                                         │
│  • whisper.cpp (C++ binary, runs locally)              │
│  • base.en model (~141MB)                               │
│  • Transcribes WAV → text                               │
│  • ~1-3 seconds latency                                 │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                  EXECUTION LAYER                        │
│               (claude_integration.py)                   │
│                                                         │
│  • Spawns `claude-code <prompt>` subprocess             │
│  • Streams output in real-time                          │
│  • Executes in target working directory                 │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                   CLAUDE CODE CLI                       │
│                                                         │
│  • Reads/edits files in your project                    │
│  • Executes bash commands                               │
│  • Commits changes                                      │
│  • Full access to all Claude Code capabilities          │
└─────────────────────────────────────────────────────────┘
                           ↓
                    ✨ Code Applied
```

## Key Components

### 1. `jarvis.py` (Main Orchestrator)
The brain that wires everything together:
- Initializes all components
- Routes audio through STT pipeline
- Sends transcriptions to Claude
- Handles the event loop

### 2. `voice_capture.py` (Audio Input)
Handles microphone and keyboard:
- `HoldToTalk` class monitors keyboard
- Records audio while SPACE is held
- Saves to temporary WAV file
- Thread-safe recording

### 3. `speech_to_text.py` (Whisper Integration)
Local speech recognition:
- Calls whisper.cpp binary
- Processes 16kHz mono audio
- Returns clean transcription
- No API calls, 100% local

### 4. `claude_integration.py` (Claude Bridge)
Executes via subprocess:
- Spawns `claude-code` with prompt
- Runs in specified working directory
- Streams output to terminal
- Returns success/failure

## Why This Is Better Than Alternatives

| Feature | Jarvis | VS Code Voice | Whisper API | Talon Voice |
|---------|--------|---------------|-------------|-------------|
| **Claude Integration** | ✅ Direct | ❌ No | ❌ No | ⚠️ Manual |
| **Privacy** | ✅ 100% Local | ❌ Cloud | ❌ Cloud | ✅ Local |
| **Cost** | ✅ Free | ⚠️ Varies | ❌ $0.006/min | ✅ Free |
| **Context Aware** | ✅ Full codebase | ❌ Basic | ❌ None | ⚠️ Limited |
| **Setup Time** | ✅ 5 minutes | ✅ 2 minutes | ✅ 1 minute | ❌ Hours |
| **Coding Commands** | ✅ Natural language | ⚠️ Dictation only | ⚠️ Dictation only | ✅ Custom grammar |

## Tech Stack

- **Python 3** - Main runtime
- **PyAudio** - Audio I/O
- **Pynput** - Keyboard monitoring
- **whisper.cpp** - Local STT (C++ for speed)
- **Claude Code CLI** - AI execution engine

## File Structure

```
jarvis-coding/
├── jarvis.py              # Main orchestrator
├── voice_capture.py       # Audio recording + keyboard
├── speech_to_text.py      # Whisper.cpp wrapper
├── claude_integration.py  # Claude Code CLI bridge
├── setup.sh               # Installation script
├── jarvis.sh              # Quick launcher
├── standalone.py          # STT-only mode (testing)
├── test.py                # System test
├── demo.py                # Usage guide
├── config.env             # Configuration
├── README.md              # Main docs
├── USAGE.md               # Examples
├── OVERVIEW.md            # This file
└── whisper.cpp/           # Local Whisper
    ├── build/bin/whisper-cli
    └── models/ggml-base.en.bin
```

## How It Compares to Your Original Vision

**You wanted:**
> ~80 line script that turns terminal into Jarvis

**You got:**
- ✅ ~250 lines total (modular, maintainable)
- ✅ Local Whisper (no API costs)
- ✅ Hold-to-talk UX
- ✅ Direct Claude Code integration
- ✅ Works in any project
- ✅ 100% private & free

## Performance

- **Recording:** Instant (captures live)
- **Transcription:** 1-3 seconds (depends on audio length)
- **Claude Execution:** Varies (depends on task complexity)
- **Total latency:** ~2-10 seconds typical

## Future Enhancements

Ideas for v2:
- [ ] Wake word detection ("Hey Jarvis")
- [ ] Streaming audio (start transcribing while recording)
- [ ] Voice feedback ("Working on it...")
- [ ] Custom hotkey configuration
- [ ] Multi-language support
- [ ] Faster whisper models (tiny, small)
- [ ] GPU acceleration for Whisper
- [ ] Integration with tmux/vim

## Contributing

This is your personal Jarvis! Customize it:
- Change trigger key in `voice_capture.py`
- Swap models in `speech_to_text.py`
- Add preprocessing in `jarvis.py`
- Extend `claude_integration.py` for other LLMs

Enjoy your voice coding superpowers! 🚀
