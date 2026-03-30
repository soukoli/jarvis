#!/usr/bin/env python3
"""
Jarvis - Voice-to-text assistant for macOS
Records voice, transcribes locally, copies to clipboard
"""
import os
import sys
import time
import threading
import subprocess
from pynput import keyboard
import rumps

# Set process name for macOS System Settings
try:
    import setproctitle
    setproctitle.setproctitle('Jarvis')
except ImportError:
    pass  # Optional - just improves display name

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))
from voice_capture import VoiceCapture
from speech_to_text import WhisperSTT


class JarvisApp(rumps.App):
    """Voice assistant with menu bar UI and global hotkeys"""

    def __init__(self):
        super().__init__("🎤 Jarvis", quit_button=None)

        # Core components
        self.voice = VoiceCapture()
        self.stt = WhisperSTT()

        # State management
        self.recording = False
        self.processing = False
        self._state_lock = threading.Lock()

        # User preferences
        self.completion_sound = True

        # Hotkey tracking
        self.cmd_pressed = False
        self.last_key_time = 0

        # Build menu
        self.menu = [
            rumps.MenuItem("▶️  Start Recording", callback=self.start_recording),
            rumps.MenuItem("⏹️  Stop Recording", callback=None),
            None,
            "Settings:",
            rumps.MenuItem("🔊 Completion Sound", callback=self.toggle_sound),
            None,
            "Hotkeys:",
            "  Cmd+; = Start",
            "  Cmd+' = Stop",
            None,
            rumps.MenuItem("ℹ️  About", callback=self.show_about),
            None,
            rumps.MenuItem("Quit Jarvis", callback=rumps.quit_application)
        ]

        # Set initial checkmarks
        self.menu["🔊 Completion Sound"].state = 1

        self._print_banner()
        self._init_hotkeys()

    def _print_banner(self):
        """Print startup banner"""
        print("\n╔════════════════════════════════════════════════════╗")
        print("║  🎤 JARVIS VOICE ASSISTANT                        ║")
        print("╚════════════════════════════════════════════════════╝\n")
        print("Controls:")
        print("  Cmd+;  = START recording")
        print("  Cmd+'  = STOP recording\n")
        print("Feedback:")
        print("  🔴 Menu bar → Recording")
        print("  🧠 Menu bar → Transcribing (wait!)")
        print("  🔊 Sound    → Ready to paste")
        print("  🎤 Menu bar → Back to ready\n")

    def _init_hotkeys(self):
        """Initialize global hotkey listener"""
        def on_press(key):
            now = time.time()
            if now - self.last_key_time < 0.5:  # Debounce
                return

            # Track Cmd key
            if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
                self.cmd_pressed = True
                return

            # Handle Cmd+key combos
            if self.cmd_pressed:
                try:
                    char = getattr(key, 'char', None)
                    if char == ";":
                        self.last_key_time = now
                        rumps.timer(0.05)(self.start_recording)()
                    elif char == "'":
                        self.last_key_time = now
                        rumps.timer(0.05)(self.stop_recording)()
                except AttributeError:
                    pass

        def on_release(key):
            if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
                self.cmd_pressed = False

        self.listener = keyboard.Listener(on_press=on_press, on_release=on_release)
        self.listener.start()

    def start_recording(self, _=None):
        """Start recording"""
        with self._state_lock:
            if self.recording or self.processing:
                return
            self.recording = True

        print(f"[{time.strftime('%H:%M:%S')}] Recording started", flush=True)
        self.title = "🔴 Recording"
        self.menu["▶️  Start Recording"].set_callback(None)
        self.menu["⏹️  Stop Recording"].set_callback(self.stop_recording)
        self.voice.start_recording()

    def stop_recording(self, _=None):
        """Stop recording and process"""
        with self._state_lock:
            if not self.recording:
                return
            self.recording = False
            self.processing = True

        print(f"[{time.strftime('%H:%M:%S')}] Recording stopped", flush=True)
        self.title = "🧠 Transcribing"
        self.menu["▶️  Start Recording"].set_callback(None)
        self.menu["⏹️  Stop Recording"].set_callback(None)

        audio_file = self.voice.stop_recording()

        if not audio_file:
            self._reset_state()
            return

        print(f"[{time.strftime('%H:%M:%S')}] Transcribing...", flush=True)
        # Process in background thread
        threading.Thread(
            target=self._process_audio,
            args=(audio_file,),
            daemon=True
        ).start()

    def _process_audio(self, audio_file: str):
        """Transcribe audio and copy to clipboard"""
        try:
            # Transcribe
            text = self.stt.transcribe(audio_file)
            if not text or not text.strip():
                print(f"[{time.strftime('%H:%M:%S')}] No transcription result", flush=True)
                return

            # Copy to clipboard
            subprocess.run(['pbcopy'], input=text, text=True, timeout=1, check=True)
            print(f"[{time.strftime('%H:%M:%S')}] Copied: {text[:50]}{'...' if len(text) > 50 else ''}", flush=True)

            # Play completion sound if enabled
            if self.completion_sound:
                try:
                    subprocess.run(['afplay', '/System/Library/Sounds/Glass.aiff'],
                                 timeout=2, check=False, stderr=subprocess.DEVNULL)
                except:
                    pass  # Silently ignore sound errors

        except Exception as e:
            print(f"[{time.strftime('%H:%M:%S')}] Error: {e}", flush=True)
        finally:
            self._reset_state()
            try:
                os.remove(audio_file)
            except:
                pass

    def toggle_sound(self, sender):
        """Toggle completion sound"""
        self.completion_sound = not self.completion_sound
        sender.state = 1 if self.completion_sound else 0

        # Play sound to demonstrate if enabling
        if self.completion_sound:
            subprocess.run(['afplay', '/System/Library/Sounds/Glass.aiff'],
                         timeout=2, check=False)

    def _reset_state(self):
        """Reset to ready state"""
        with self._state_lock:
            self.recording = False
            self.processing = False

        self.title = "🎤 Jarvis"
        self.menu["▶️  Start Recording"].set_callback(self.start_recording)
        self.menu["⏹️  Stop Recording"].set_callback(None)

    def show_about(self, _=None):
        """Show about dialog"""
        rumps.alert(
            title="About Jarvis",
            message=(
                "🎤 Jarvis Voice Assistant v2.0\n\n"
                "Local voice-to-text with clipboard workflow.\n\n"
                "How it works:\n"
                "1. Cmd+; → Recording (🔴)\n"
                "2. Speak clearly\n"
                "3. Cmd+' → Transcribing (🧠)\n"
                "4. Hear 'ding' → Ready!\n"
                "5. Cmd+V → Paste text\n\n"
                "Menu bar shows status:\n"
                "🎤 Ready | 🔴 Recording | 🧠 Transcribing\n\n"
                "Wait for sound before pasting!"
            )
        )


if __name__ == "__main__":
    app = JarvisApp()
    app.run()
