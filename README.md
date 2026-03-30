# 🎤 Jarvis Voice Assistant

**Voice-to-text for macOS that works everywhere.** Speak naturally, get instant transcription on clipboard, paste anywhere.

Built with local processing (whisper.cpp) - free, private, offline.

---

## Installation

### Quick Start

```bash
# 1. Run setup (installs dependencies and builds whisper.cpp)
./setup.sh

# 2. Run Jarvis
./run.sh
```

**Or manually:**

```bash
# Install system dependencies
brew install portaudio cmake

# Install Python dependencies
pip3 install pynput rumps pyaudio setproctitle

# Build whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build && cmake --build build --config Release
bash ./models/download-ggml-model.sh base.en
cd ..

# Run Jarvis
./run.sh
```

---

## How to Use

1. **Cmd+;** - Start recording (🔴 appears in menu bar)
2. **Speak clearly**
3. **Cmd+'** - Stop recording (🧠 shows "Transcribing")
4. **Wait for sound** - "Ding!" means transcription complete
5. **Cmd+V** - Paste transcribed text

**⚠️ Important:** Watch the menu bar icon! Wait for 🧠 to change back to 🎤 and hear the sound before pasting.

### Menu Bar (Alternative to Hotkeys)

Click 🎤 icon:
- **▶️ Start Recording** - Begin capture
- **⏹️ Stop Recording** - End capture (enabled while recording)

**Settings:**
- **🔊 Completion Sound** - Toggle "ding" when done (✓ = enabled)

**Info:**
- **ℹ️ About** - App info and workflow
- **Quit Jarvis** - Exit app

**Icon states:**
- 🎤 = Ready to record
- 🔴 = Recording your voice
- 🧠 = Transcribing (DO NOT paste yet!)

**When transcription completes:**
- Icon: 🧠 → 🎤 (back to ready)
- Sound: "Ding" plays (if enabled)
- Clipboard: Text is ready to paste

---

## Permission Setup

**Required:** Input Monitoring (for global hotkeys)

1. Open **System Settings**
2. Go to **Privacy & Security** → **Input Monitoring**
3. Add **Terminal** (or Python)
4. **Quit Terminal** completely (Cmd+Q)
5. Reopen and run `./run.sh`

**Without permission:**
- Hotkeys (Cmd+;, Cmd+') won't work
- Menu bar buttons still work fine!

---

## Example Usage

**In Claude Code:**
```
Cmd+;  → "Create a React authentication component"
Cmd+'  → [notification: "Ready to Paste!"]
Cmd+V  → Text appears in chat
Enter  → Claude executes
```

**In VS Code:**
```
Cmd+;  → "Add error handling for null values"
Cmd+'  → [wait for notification]
Cmd+V  → Text appears at cursor
```

**Anywhere:**
- Browser search
- Email
- Slack
- Documentation
- Comments

---

## Troubleshooting

**Hotkeys not working?**
1. Grant Input Monitoring permission (see above)
2. Verify: `ps aux | grep Jarvis` (should show process)
3. Restart Terminal and run `./run.sh`

**No transcription or wrong text?**
- Check terminal output for microphone device being used
- Verify whisper: `./whisper.cpp/build/bin/whisper-cli --version`
- Check logs in terminal for "Max amplitude" - should be >100

**Want to stop?**
- Click 🎤 → Quit Jarvis
- Or press Ctrl+C in terminal

---

## Technical Details

| Component | Technology |
|-----------|------------|
| **Menu Bar UI** | rumps |
| **Hotkeys** | pynput (global keyboard listener) |
| **Audio** | pyaudio (16kHz mono WAV) |
| **Transcription** | whisper.cpp (base.en model, Metal accelerated) |
| **Workflow** | Voice → STT → Clipboard → Manual paste |

**Why clipboard?** macOS blocks keyboard automation for security. Clipboard workflow is reliable and works everywhere.

**Storage:**
- Recordings: `.voice_cache/` (auto-keeps last 5)

---

## Commands Reference

```bash
./run.sh   # Run Jarvis from terminal
```

---

**Jarvis v2.0** - Simple, local, reliable voice-to-text for macOS