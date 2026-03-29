# 🎤 Jarvis Voice Coding Assistant

System-wide voice assistant that auto-types at your cursor. Perfect for Claude Code!

## Quick Start

```bash
./run.sh
```

Menu bar icon 🎤 appears. Ready to use!

## How To Use

**Method 1: Hotkeys** (fastest)
1. Position cursor in Claude chat
2. **Cmd+;** (⌘+;) → Starts recording 🔴
3. Speak: "Claude create a hello world function"
4. **Cmd+'** (⌘+') → Stops & types text ✨
5. Press Enter → Claude executes!

**Method 2: Menu Buttons** (most reliable)
1. Click 🎤 in menu bar
2. Click **"▶️ Start Recording"**
3. Speak your command
4. Click **"⏹️ Stop Recording"**
5. Text types at cursor!

## Why Two Methods?

- **Hotkeys** = Fast, convenient
- **Menu buttons** = Always works, can't fail

Use menu if hotkeys have focus issues!

## Menu Bar Features

Click 🎤 icon:

```
▶️  Start Recording    Click to start
⏹️  Stop Recording     Click to stop (active when recording)
─────────────────
Hotkeys:
  Cmd+; = Start
  Cmd+' = Stop
─────────────────
🧪 Test Microphone     3-second test
ℹ️  About              App info
─────────────────
Quit Jarvis
```

## Visual Feedback

**Menu bar icon:**
- 🎤 Jarvis - Ready
- 🔴 Recording - Listening to you
- 🧠 Processing - Transcribing

**Notifications:**
- "🎤 Recording" when you start
- "✅ Done!" when text is typed

## Installation

```bash
# First time only
./setup.sh

# Every time
./run.sh
```

## Requirements

- macOS
- Python 3.8+
- Microphone permission
- Accessibility permission (for typing)

## Permissions

macOS will prompt on first run:

**Microphone** → Allow Terminal
- Needed to record voice

**Accessibility** → Allow Terminal
- Needed to type text automatically

Grant both in System Settings → Privacy & Security

## Troubleshooting

**Hotkeys not working?**
- Use menu buttons instead! Click 🎤 → Start Recording
- Menu buttons always work, no focus issues

**No audio captured?**
```bash
python3 debug_keys.py  # Test keyboard
python3 test.py        # Test system
```

**Recording won't stop?**
- Click menu bar 🎤 → "⏹️ Stop Recording"
- Menu button bypasses hotkey issues

**Check logs:**
- Console shows all activity
- Look for "START key pressed" / "STOP key pressed"

## Project Structure

```
jarvis-coding/
├── run.sh              # Launch
├── jarvis.py           # Main app
├── setup.sh            # Install
├── src/
│   ├── voice_capture.py    # Audio
│   └── speech_to_text.py   # Whisper
├── test.py             # Tests
├── cache.py            # Cache manager
├── debug_keys.py       # Debug tool
└── whisper.cpp/        # STT engine
```

## Cache

Recordings stored in `.voice_cache/` (auto-keeps last 5):

```bash
python3 cache.py show   # View
python3 cache.py clean  # Clean
```

## Example Commands

In Claude chat:
- "Claude create a React component"
- "Fix the authentication bug"
- "Write unit tests"
- "Refactor this function"

In VS Code:
- "Add error handling"
- "Create a new function"

Anywhere:
- Natural speech becomes text!

## Why This Is Better

| Feature | Jarvis | Alternatives |
|---------|--------|--------------|
| Price | Free | Paid APIs |
| Privacy | 100% local | Cloud-based |
| Integration | Claude Code | Basic dictation |
| Control | Hotkeys + Menu | Hotkeys only |
| Reliability | Menu fallback | Can get stuck |

## Tips

- **Use menu buttons** if hotkeys act weird (most reliable!)
- Speak clearly at normal pace
- Menu bar shows current state (🎤/🔴/🧠)
- Cmd+; and Cmd+' are next to each other (easy!)

## The Fix

**Problem:** Toggle on single key caused focus/state issues

**Solution:**
- Separate START (Cmd+;) and STOP (Cmd+') keys
- Menu buttons as backup
- Debouncing prevents double-triggers
- State management prevents conflicts

## Development

**Test:**
```bash
python3 test.py
```

**Debug keyboard:**
```bash
python3 debug_keys.py
```

**Clean reinstall:**
```bash
rm -rf whisper.cpp .voice_cache
./setup.sh
```

---

## 🚀 Ready To Use!

```bash
./run.sh
```

Then **either**:
- Press **Cmd+;** to start (hotkey)
- Or click menu **▶️ Start Recording** (always works!)

Speak, then stop with **Cmd+'** or click **⏹️ Stop**.

Text appears at your cursor! ✨
