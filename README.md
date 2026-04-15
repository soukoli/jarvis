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

1. **Cmd+;** - Start recording (customizable in Settings)
   - Hears: Language name spoken (e.g., "English", "Czech", "German") + beep
   - Sees: 🔴 with language flag in menu bar
2. **Speak clearly** in your selected language
3. **Cmd+'** - Stop recording (customizable in Settings)
   - Sees: 🧠 "Transcribing"
4. **Wait for sound** - "Ding!" means complete
5. **Cmd+V** - Paste transcribed text anywhere

**⚠️ Important:** 
- The selected language is what you **speak** - text is transcribed in that language (not translated)
- Wait for 🧠 to change back to 🎤 and hear the sound before pasting

### Menu Bar - Simple & Clean

Click 🎤 icon:

**Quick Actions:**
- **▶️ Start Recording (Cmd+;)** - Begin capture
- **⏹️ Stop Recording (Cmd+')** - End capture

**Language Selection:**
- **🗣️ Current Language** - Shows active language with flag
- **Change Language...** - Access language picker
  - 🌐 Auto-detect - Works with any language
  - 🇬🇧 English, 🇨🇿 Czech, 🇩🇪 German, 🇪🇸 Spanish, 🇫🇷 French, etc.

**Settings & Info:**
- **🔊 Completion Sound** - Toggle notification (✓ = on)
- **ℹ️ About** - App info
- **Quit Jarvis** - Exit

**Icon States:**
- 🎤 🇬🇧 = Ready (with language flag)
- 🔴 🇨🇿 = Recording in Czech
- 🧠 🇩🇪 = Transcribing German

**When Recording Starts:**
- Voice: Language announced (e.g., "Czech") - silent for auto-detect
- Sound: Notification beep
- Icon: 🔴 with language flag

**When Complete:**
- Icon: 🧠 → 🎤 (back to ready)
- Sound: "Ding" (if enabled)
- Clipboard: Text ready to paste

---

## Permission Setup

**Required:** Input Monitoring (for global hotkeys)

1. Open **System Settings**
2. Go to **Privacy & Security** → **Input Monitoring**
3. Add **Terminal** (or Python)
4. **Quit Terminal** completely (Cmd+Q)
5. Reopen and run `./run.sh`

**Without permission:**
- Hotkeys won't work
- Menu bar buttons still work fine!

---

## Example Usage

**In Claude Code:**
```
Cmd+;  → "Create a React authentication component"
Cmd+'  → [hear "ding"]
Cmd+V  → Text appears in chat
```

**In VS Code:**
```
Cmd+;  → "Add error handling for null values"
Cmd+'  → [wait for "ding"]
Cmd+V  → Text appears at cursor
```

**Anywhere:**
- Browser search
- Email
- Slack
- Documentation

---

## Troubleshooting

**Hotkeys not working?**
1. Grant Input Monitoring permission (see above)
2. Verify: `ps aux | grep Jarvis` (should show process)
3. Restart Terminal and run `./run.sh`

**Poor Czech/multilingual recognition?**
1. Go to **Settings → Download Better Model**
2. Download `large-v3-turbo` (takes 5-10 min)
3. Restart app to use new model
4. See `MULTILINGUAL-IMPROVEMENTS.md` for details

**No transcription or wrong text?**
- Check terminal for microphone device being used
- Select different microphone in **Settings**
- Verify whisper: `./whisper.cpp/build/bin/whisper-cli --version`
- Check logs for "Max amplitude" - should be >100

**Microphone not found after reconnecting?**
- App saves microphone by **name**, not number
- If unplugged, auto-switches to available device
- Select preferred mic again in **Settings** when reconnected

**Library errors after moving folder?**
- Run `./setup.sh` again to rebuild whisper.cpp
- Fixes dynamic library paths

**Want custom hotkeys?**
- Go to **Settings → Change Hotkeys**
- Enter two characters (e.g., `p o` for Cmd+p / Cmd+o)
- Restart app for changes to take effect

---

## Technical Details

| Component | Technology |
|-----------|------------|
| **Menu Bar UI** | rumps |
| **Hotkeys** | pynput (global keyboard listener) |
| **Audio** | pyaudio (16kHz mono WAV) |
| **Transcription** | whisper.cpp (auto-selects best model) |
| **Workflow** | Voice → STT → Clipboard → Manual paste |

**Why clipboard?** macOS blocks keyboard automation for security. Clipboard workflow is reliable and works everywhere.

**Model Priority:**
1. large-v3-turbo (best for Czech/multilingual)
2. large-v3 (highest quality)
3. medium (good quality)
4. base (faster, less accurate)

**Storage:**
- Recordings: `.voice_cache/` (auto-keeps last 5)
- Settings: `~/.jarvis_config.json` (mic, language, hotkeys, sound)

---

## Commands Reference

```bash
./run.sh                     # Run Jarvis (with safety checks)
./run-dev.sh                 # Quick run (no checks, for development)
./check.sh                   # Run pre-flight checks only
python3 test_jarvis.py       # Run unit tests
python3 test_jarvis.py --smoke  # Run quick smoke tests
./download-better-model.sh   # Get large-v3-turbo for better Czech
```

### Development Workflow

**Before running after changes:**
```bash
./check.sh  # Validates everything
```

**Quick testing during development:**
```bash
./run-dev.sh  # Fast, no checks
```

**Run full tests:**
```bash
python3 test_jarvis.py
```

---

**Jarvis v2.1** - Simple, local, reliable voice-to-text for macOS
