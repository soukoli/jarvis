<div align="center">

# Jarvis

### Think out loud. Let your voice do the typing.

Speak your thoughts naturally. Get instant text on your clipboard. Paste anywhere.

Local. Private. GPU-accelerated. No cloud, no subscription, no limits.

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple)](https://support.apple.com/en-us/111902)
[![Offline](https://img.shields.io/badge/100%25-Offline-green)](.)
[![License](https://img.shields.io/badge/license-MIT-blue)](#license)
[![Python](https://img.shields.io/badge/Python-3.13-yellow?logo=python)](https://python.org)

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
    (splits speech          (Apple GPU, chunks are
     into chunks)            transcribed while you talk)
```

1. Press **Cmd+;** to start recording
2. Speak naturally in Czech, English or any of the 12 supported languages
3. Press **Cmd+'** to stop
4. Wait for the "ding" sound
5. Press **Cmd+V** to paste your transcribed text

Speech is transcribed chunk by chunk *while you speak*, so when you press stop the text is usually already there.

---

## Features

| | Feature | Description |
|---|---------|-------------|
| ⚡ | **GPU-Accelerated** | MLX Whisper on Apple Silicon (Metal). faster-whisper CPU fallback on Intel |
| 🎯 | **Streaming VAD** | Silero VAD cuts speech at natural pauses; each chunk is transcribed immediately |
| 🤖 | **Model Switcher** | Pick between 4 Whisper models from the menu (accuracy vs speed) |
| 🌍 | **Multilingual** | Czech, English + 10 more languages, or auto-detect |
| 🔒 | **100% Offline** | Everything runs locally. Your voice never leaves your Mac |
| 🧹 | **Anti-Hallucination** | Filters known Whisper artifacts, loops and near-duplicate chunks |
| 🛡️ | **Permission Guard** | Detects missing Microphone / Accessibility permission and shows how to fix it |
| 🎤 | **Menu Bar App** | Lives in your menu bar, always one hotkey away |
| ⌨️ | **Global Hotkeys** | Works from any app, any context. Keys are configurable |
| 🔊 | **Audio Feedback** | Optional spoken language announcement on start, "ding" when ready |

---

## Quick Start

### Prerequisites

- macOS with **Apple Silicon** (M1/M2/M3/M4)
- Python 3.13 (the launcher prefers a [mise](https://mise.jdx.dev) install, then falls back to `python3`)
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

On first run, the Whisper model (~1.5GB) downloads automatically. After that, startup takes a few seconds while the model warms up in the background.

---

## Setup Details

The `setup.sh` script:

1. Installs system dependencies (portaudio via Homebrew)
2. Installs pinned Python packages from `requirements.txt` (mlx-whisper, silero-vad, torch, pyaudio, pynput, rumps, pyobjc, ...)
3. Downloads the MLX Whisper large-v3-turbo model (~1.5GB, one-time)
4. Verifies the installation

### Permissions

Jarvis runs inside the terminal that launched it, so macOS permissions are granted to **that terminal app** (Terminal, iTerm, ...). Two are needed:

| Permission | Why | Where |
|---|---|---|
| **Microphone** | Recording. Without it PyAudio opens the stream but delivers silence | System Settings → Privacy & Security → Microphone |
| **Accessibility** (and on newer macOS also **Input Monitoring**) | Global hotkeys via pynput | System Settings → Privacy & Security → Accessibility / Input Monitoring |

Restart the terminal after changing permissions.

Jarvis checks both at startup. If something is missing, the menu bar icon turns into **⚠️**, a notification appears, and the first menu item opens a dialog with an "Open System Settings" button. Use **🔄 Recheck permissions** after fixing them. Menu bar buttons work even without Accessibility - only the hotkeys need it.

---

## Usage

### Hotkeys

| Key | Action |
|-----|--------|
| **Cmd+;** | Start recording |
| **Cmd+'** | Stop & transcribe |
| **Cmd+.** | Cancel anytime |

The three keys are configurable in `~/.jarvis_config.json` (`hotkey_start`, `hotkey_stop`, `hotkey_cancel`); the Cmd modifier is fixed.

### Menu Bar

Click the icon to access:

- **Permission status** and recheck
- **Start / Stop / Cancel** (same as the hotkeys)
- **Transcription Language** with flag indicator, or auto-detect
- **Whisper Model** switcher (see table below). Takes effect on the next recording
- **Streaming Mode** toggle (see note below)
- **Completion Sound** and **Language Announcement** toggles
- About, Quit

### Whisper Models

| Menu option | Hugging Face repo | Size | Notes |
|---|---|---|---|
| large-v3-turbo | `mlx-community/whisper-large-v3-turbo` | 1.5 GB | Default. Best accuracy for Czech |
| large-v3-turbo-q4 | `mlx-community/whisper-large-v3-turbo-q4` | ~380 MB | 4-bit, nearly the same accuracy, faster |
| medium | `mlx-community/whisper-medium-mlx-4bit` | ~500 MB | Faster, slightly lower accuracy |
| small | `mlx-community/whisper-small-mlx-q4` | ~150 MB | Fastest, good for short inputs |

Models download on first use and are cached in `~/.cache/huggingface/hub`.

### Icon States

| Icon | State |
|------|-------|
| 🎤 + flag | Ready |
| ⚠️ + flag | Ready, but a permission is missing (click the menu) |
| 🔴 + flag | Recording |
| 🧠 + flag | Transcribing |

### Configuration

Settings are saved to `~/.jarvis_config.json` whenever you change them in the menu:

```json
{
  "completion_sound": true,
  "language_announcement": false,
  "streaming_mode": true,
  "device_name": "MacBook Pro Microphone",
  "language": "cs",
  "model_size": "large-v3-turbo",
  "hotkey_start": ";",
  "hotkey_stop": "'",
  "hotkey_cancel": "."
}
```

`device_name` pins a microphone. If that device is not present, Jarvis falls back to a close name match, then the macOS default input.

### Troubleshooting: "No transcription result"

Run the diagnostics script. It reports permission status, all input devices, the configured device and a 3-second level test:

```bash
python3 diagnose.py
```

An RMS of exactly 0.000 means the microphone permission is denied for your terminal.

### Streaming Mode off (batch mode)

With **Streaming Mode** unchecked, Jarvis records a WAV file and transcribes it in one go with the whisper.cpp CLI. This path is a legacy fallback: `setup.sh` does **not** build whisper.cpp or download a `ggml-*.bin` model, so on a fresh install batch mode prints "Whisper not found" and produces nothing. Keep Streaming Mode on unless you have built `whisper.cpp/` yourself.

---

## Architecture

```
jarvis/
├── jarvis.py               # App entry point: menu bar UI, hotkeys, permission checks
├── src/
│   ├── streaming_stt.py    # MLX Whisper + Silero VAD streaming engine, model switcher
│   ├── speech_to_text.py   # Batch fallback via whisper.cpp CLI (not installed by setup.sh)
│   └── voice_capture.py    # Batch WAV recorder (used only with Streaming Mode off)
├── diagnose.py             # Microphone / permission diagnostics
├── requirements.txt        # Pinned, verified Python dependencies
├── setup.sh                # One-click installer
├── run.sh                  # Launcher
└── AGENTS.md / CLAUDE.md   # Guide for AI coding agents working on this repo
```

### Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Inference | MLX Whisper (large-v3-turbo default) | Apple Silicon GPU via Metal |
| CPU fallback | faster-whisper (CTranslate2) | Intel Macs / no MLX |
| VAD | Silero VAD | Lightweight, accurate voice detection |
| Audio | PyAudio | Low-level mic access, 16kHz mono |
| UI | rumps | Native macOS menu bar integration |
| Hotkeys | pynput | System-wide keyboard capture |
| Permissions | pyobjc (AVFoundation, ApplicationServices) | Query TCC status without prompting |

### Pipeline

1. PyAudio delivers 32 ms frames (512 samples at 16 kHz).
2. Silero VAD scores each frame. Speech frames are buffered; 600 ms of silence closes a chunk (minimum 250 ms of speech).
3. Each chunk is transcribed on a background thread, indexed so results assemble in order regardless of finish time.
4. Chunks matching known hallucination patterns, repetitive loops, or near-duplicates of the previous chunk are dropped.
5. On stop, remaining audio is flushed, pending chunks are awaited (up to 15 s), the text is joined and copied to the clipboard with `pbcopy`.

### Performance (indicative, M-series, large-v3-turbo)

| Metric | Value |
|--------|-------|
| Inference speed | ~2 s per 5 s chunk |
| Model warm-up | background, at startup |
| Supported languages | 12 + auto-detect |

---

## Who Is This For?

- **Developers** who want to dictate commit messages, code comments, or chat with AI assistants
- **Writers** who think faster than they type
- **Multitaskers** who want to keep hands on other tasks while capturing thoughts
- **Anyone** who values privacy and doesn't want their voice sent to the cloud

---

## FAQ

**Q: Does it work without internet?**
A: Yes. 100% offline after the initial model download.

**Q: Which languages are supported?**
A: Czech, English, German, Spanish, French, Italian, Polish, Portuguese, Russian, Slovak, Ukrainian + auto-detect.

**Q: How accurate is it?**
A: Whisper large-v3-turbo achieves roughly 5-8% word error rate on clean speech. Comparable to cloud services.

**Q: Does it work on Intel Macs?**
A: It falls back to CPU mode (faster-whisper). Works but several times slower, and only the `large-v3-turbo`, `medium` and `small` model options are valid there.

**Q: Can I use it with [any app]?**
A: If you can press Cmd+V in it, yes. It copies to the clipboard - universal.

**Q: The icon shows ⚠️. What now?**
A: Click it. The dialog lists what is missing and opens the right System Settings pane.

---

## Development

See [AGENTS.md](AGENTS.md) for layout, runtime constraints (notably the torch/torchaudio pin), the verification checklist and the current list of known gaps.

---

## License

MIT

---

<div align="center">

*Built for people who think faster than they type.*

</div>
