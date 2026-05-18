<div align="center">

# Jarvis

### Think out loud. Let your voice do the typing.

Speak your thoughts naturally. Get instant text on your clipboard. Paste anywhere.

Local. Private. GPU-accelerated. No cloud, no subscription, no limits.

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple)](https://support.apple.com/en-us/111902)
[![Offline](https://img.shields.io/badge/100%25-Offline-green)](.)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.12+-yellow?logo=python)](https://python.org)

</div>

---

## Why Voice?

You **think 3x faster** than you type. Every time you reach for the keyboard, you lose context. Your brain is already three sentences ahead, but your fingers are still on the first word.

**Jarvis changes that.**

- **Preserve the full depth of your thought.** Speaking captures nuances, context, and connections that get lost when you slow down to type.
- **Perfect for people with vivid imagination.** If you think in rich context and big pictures, voice lets you externalize that without compression.
- **Keep your hands free.** Code in your IDE while dictating a message. Browse documentation while describing a bug. Multitask naturally.
- **Works everywhere.** Email, Slack, VS Code, terminal, browser - if you can paste, you can use Jarvis.
- **No learning curve.** You already know how to talk.

> *"The bottleneck isn't your thinking. It's the keyboard between your brain and the screen."*

---

## How It Works

```
        Cmd+;                    Cmd+'                    Cmd+V
          |                        |                        |
    Start speaking      Stop & transcribe            Paste anywhere
          |                        |                        |
    [🔴 Recording]        [🧠 Processing]          [📋 Ready]
          |                        |
          v                        v
    Silero VAD              MLX Whisper
    (detects speech)        (Apple GPU, ~2s)
```

1. Press **Cmd+;** to start recording
2. Speak naturally in Czech or English
3. Press **Cmd+'** to stop
4. Wait for the "ding" sound
5. Press **Cmd+V** to paste your transcribed text

That's it. No accounts, no internet, no waiting.

---

## Features

| | Feature | Description |
|---|---------|-------------|
| ⚡ | **GPU-Accelerated** | MLX Whisper on Apple Silicon - 3.6x faster than CPU |
| 🎯 | **Streaming VAD** | Processes speech in real-time chunks, not after recording |
| 🌍 | **Multilingual** | Czech, English + 10 more languages |
| 🔒 | **100% Offline** | Everything runs locally. Your voice never leaves your Mac |
| 🧹 | **Anti-Hallucination** | Filters out Whisper artifacts automatically |
| 🎤 | **Menu Bar App** | Lives in your menu bar, always one hotkey away |
| ⌨️ | **Global Hotkeys** | Works from any app, any context |
| 🔊 | **Audio Feedback** | Sound notification when transcription is ready |

---

## Quick Start

### Prerequisites

- macOS with **Apple Silicon** (M1/M2/M3/M4)
- Python 3.12+
- [Homebrew](https://brew.sh)

### Install

```bash
git clone https://github.com/soukoli/jarvis.git
cd jarvis
./setup.sh
```

### Run

```bash
./run.sh
```

On first run, the Whisper model (~1.5GB) downloads automatically. After that, startup takes ~2 seconds.

---

## Setup Details

The `setup.sh` script handles everything:

1. Installs system dependencies (portaudio via Homebrew)
2. Installs Python packages (mlx-whisper, silero-vad, torch, pyaudio, pynput, rumps)
3. Downloads the MLX Whisper large-v3-turbo model (~1.5GB, one-time)
4. Verifies the installation

### Permissions

After setup, grant **Input Monitoring** permission for global hotkeys:

1. Open **System Settings**
2. Go to **Privacy & Security** → **Input Monitoring**
3. Add **Terminal** (or your terminal app)
4. Restart Terminal

Without this permission, menu bar buttons still work - only global hotkeys require it.

---

## Usage

### Hotkeys

| Key | Action |
|-----|--------|
| **Cmd+;** | Start recording |
| **Cmd+'** | Stop & transcribe |
| **Cmd+.** | Cancel anytime |

### Menu Bar

Click the microphone icon to access:
- Language selection (with flag indicator)
- Streaming mode toggle
- Sound & announcement settings

### Icon States

| Icon | State |
|------|-------|
| 🎤 + flag | Ready |
| 🔴 + flag | Recording |
| 🧠 + flag | Transcribing |

---

## Architecture

```
jarvis/
├── jarvis.py               # App entry point (menu bar UI, hotkeys)
├── src/
│   ├── streaming_stt.py    # MLX Whisper + Silero VAD streaming engine
│   ├── speech_to_text.py   # Batch mode fallback (whisper.cpp)
│   └── voice_capture.py    # Batch audio recording fallback
├── setup.sh                # One-click installer
└── run.sh                  # Launcher
```

### Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Inference | MLX Whisper large-v3-turbo | Apple Silicon GPU, 3.6x faster than CPU |
| VAD | Silero VAD | Lightweight, accurate voice detection |
| Audio | PyAudio | Low-level mic access, 16kHz mono |
| UI | rumps | Native macOS menu bar integration |
| Hotkeys | pynput | System-wide keyboard capture |

### Performance

| Metric | Value |
|--------|-------|
| Inference speed | ~1.9s per 5s audio |
| Engine | Apple Silicon GPU (Metal) |
| Model | Whisper large-v3-turbo |
| First load | ~2s (from disk cache) |
| Supported languages | 12 (Czech, English, German, Spanish, French, ...) |

---

## Who Is This For?

- **Developers** who want to dictate commit messages, code comments, or chat with AI assistants
- **Writers** who think faster than they type
- **Multitaskers** who want to keep hands on other tasks while capturing thoughts
- **Anyone** who values privacy and doesn't want their voice sent to the cloud

---

## FAQ

**Q: Does it work without internet?**
A: Yes. 100% offline after initial model download.

**Q: Which languages are supported?**
A: Czech, English, German, Spanish, French, Italian, Polish, Portuguese, Russian, Slovak, Ukrainian + auto-detect.

**Q: How accurate is it?**
A: Whisper large-v3-turbo achieves ~5-8% word error rate on clean speech. Comparable to cloud services.

**Q: Does it work on Intel Macs?**
A: It falls back to CPU mode (faster-whisper). Works but ~3.6x slower.

**Q: Can I use it with [any app]?**
A: If you can press Cmd+V in it, yes. It copies to clipboard - universal.

---

## License

MIT

---

<div align="center">

*Built for people who think faster than they type.*

</div>
