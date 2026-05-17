# Jarvis Voice Assistant

**Voice-to-text for macOS with Apple Silicon GPU acceleration.** Speak naturally, get instant transcription on clipboard, paste anywhere.

Built with local processing - free, private, fully offline.

---

## Architecture

```
Mic → PyAudio (16kHz mono)
  → Silero VAD (voice activity detection, per-frame)
    → Speech chunks (segmented by pauses)
      → MLX Whisper large-v3-turbo (Apple Silicon GPU inference)
        → Hallucination filter
          → [Smart Cleanup?] → Ollama LLM (optional punctuation)
            → Clipboard
```

| Component | Technology |
|-----------|------------|
| **Menu Bar UI** | rumps |
| **Hotkeys** | pynput (global keyboard listener) |
| **Audio Capture** | PyAudio (16kHz mono) |
| **Voice Activity Detection** | Silero VAD |
| **Transcription** | MLX Whisper large-v3-turbo (Apple Silicon GPU) |
| **Smart Cleanup** | Ollama + llama3.1:8b (optional, local LLM) |
| **Clipboard** | pbcopy / osascript fallback |

---

## Installation

### Quick Start

```bash
# Install system dependencies
brew install portaudio ollama

# Install Python dependencies
pip3 install pynput rumps pyaudio setproctitle faster-whisper \
    silero-vad torch numpy mlx-whisper

# Start Ollama (for Smart Cleanup feature)
brew services start ollama
ollama pull llama3.1:8b

# Run Jarvis
./run.sh
```

### First Run

On first launch, the MLX Whisper model (~1.5GB) will be downloaded from HuggingFace. Subsequent starts load from cache (~2s).

---

## How to Use

1. **Cmd+;** - Start recording
   - Hears: Language name spoken (e.g., "Czech") + beep
   - Sees: Red dot with language flag in menu bar
2. **Speak clearly** in your selected language
3. **Cmd+'** - Stop recording
   - Sees: Brain icon = transcribing
4. **Cmd+.** - Cancel/abort anytime
5. **Wait for "ding"** - text is ready
6. **Cmd+V** - Paste transcribed text anywhere

### Menu Bar Options

- **Streaming Mode** - VAD-based chunk processing (recommended)
- **Smart Cleanup (AI)** - Adds punctuation via local LLM
- **Completion Sound** - Toggle "ding" notification
- **Language Announcement** - Toggle spoken language on start
- **Change Language** - Czech, English, German, Spanish, French, etc.

---

## Modes

### Streaming Mode (default, recommended)

Audio is processed in real-time chunks:
- Silero VAD detects speech segments (pauses > 600ms = segment boundary)
- Each segment is transcribed independently via MLX Whisper
- Results are concatenated and copied to clipboard on stop

**Performance:** ~1.9s inference per 5s audio chunk (Apple Silicon GPU)

### Batch Mode (legacy fallback)

Records full audio to WAV file, then transcribes entire file at once via whisper.cpp CLI. Slower but available as fallback.

---

## Smart Cleanup (Optional)

When enabled, transcribed text goes through a local LLM (Ollama) that:
1. Removes filler words (regex: hmm, vlastne, proste, jako...)
2. Adds punctuation and capitalization (LLM, ~2-3s)

**Does NOT change your words or meaning.** Only cleans up and adds structure.

Requires Ollama running: `brew services start ollama`

---

## Anti-Hallucination

Whisper models can "hallucinate" text (especially on silence/noise). Jarvis filters:
- Known phrases: "Titulky vytvoril JohnyX", "Dekuji za pozornost", "Subscribe", etc.
- High no_speech_prob segments (>0.6)
- Low confidence segments (avg_logprob < -1.0)
- Repetitive text (same words repeated)

Filtered hallucinations are logged as `[filtered hallucination]` in terminal.

---

## Performance

| Metric | Value |
|--------|-------|
| **Inference engine** | MLX Whisper (Apple Silicon GPU, fp16) |
| **Model** | large-v3-turbo (multilingual) |
| **Speed** | ~1.9s per 5s audio chunk |
| **Speedup vs CPU** | 3.6x faster than faster-whisper int8 |
| **VAD latency** | ~32ms per frame |
| **Languages** | Czech, English + 10 others |
| **Fully offline** | Yes (after initial model download) |

---

## File Structure

```
jarvis-coding/
├── jarvis.py               # Main app (GUI, hotkeys, orchestration)
├── src/
│   ├── streaming_stt.py    # Streaming engine (MLX Whisper + Silero VAD)
│   ├── text_refiner.py     # Smart Cleanup (regex + Ollama)
│   ├── speech_to_text.py   # Legacy batch mode (whisper.cpp CLI)
│   └── voice_capture.py    # Legacy batch recording (PyAudio → WAV)
├── run.sh                  # Launcher
├── setup.sh                # Setup script
└── whisper.cpp/            # Legacy whisper.cpp build (in .gitignore)
```

---

## Configuration

Settings stored in `~/.jarvis_config.json`:
- `streaming_mode` - true/false
- `smart_cleanup` - true/false
- `completion_sound` - true/false
- `language_announcement` - true/false
- `language` - "cs", "en", "auto", etc.
- `device_name` - selected microphone
- `hotkey_start`, `hotkey_stop`, `hotkey_cancel`

---

## Permission Setup

**Required:** Input Monitoring (for global hotkeys)

1. Open **System Settings**
2. Go to **Privacy & Security** → **Input Monitoring**
3. Add **Terminal** (or Python)
4. Restart Terminal and run `./run.sh`

---

## Troubleshooting

**Hotkeys not working?**
- Grant Input Monitoring permission (see above)
- Restart Terminal completely (Cmd+Q)

**Hallucinations ("Titulky vytvoril JohnyX")?**
- These are filtered automatically
- If still appearing, check terminal for `[filtered hallucination]` logs

**Slow first transcription?**
- First chunk after app start loads model into GPU memory (~2s)
- Subsequent chunks are fast (~1.9s per 5s audio)

**Smart Cleanup not working?**
- Ensure Ollama is running: `brew services start ollama`
- Check model: `ollama list` (should show llama3.1:8b)

---

## Dependencies

| Package | Purpose |
|---------|---------|
| mlx-whisper | Apple Silicon GPU inference |
| faster-whisper | CPU fallback inference |
| silero-vad | Voice activity detection |
| torch | Silero VAD runtime |
| pyaudio | Microphone capture |
| pynput | Global hotkeys |
| rumps | macOS menu bar UI |
| numpy | Audio processing |

---

**Jarvis v3.0** - Local, private, GPU-accelerated voice-to-text for macOS
