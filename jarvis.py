#!/usr/bin/env python3
"""
Jarvis - Voice assistant with menu bar controls
Reliable start/stop with both hotkeys AND menu buttons
"""
import os
import sys
import time
import threading
import subprocess
from typing import Optional
from pynput import keyboard
from pynput.keyboard import Controller
import rumps

# Import modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))
from voice_capture import VoiceCapture
from speech_to_text import WhisperSTT


class JarvisApp(rumps.App):
    """Voice assistant menu bar app"""

    def __init__(self):
        super().__init__("🎤 Jarvis", quit_button=None)

        self.voice = VoiceCapture()
        self.stt = WhisperSTT()
        self.keyboard_controller = Controller()
        self.recording = False
        self.processing = False

        # Hotkeys
        self.start_combo = ("<cmd>", ";")
        self.stop_combo = ("<cmd>", "'")
        self.cmd_pressed = False
        self.last_key_time = 0

        # Build menu
        self.menu = [
            rumps.MenuItem("▶️  Start Recording", callback=self.menu_start_recording),
            rumps.MenuItem("⏹️  Stop Recording", callback=self.menu_stop_recording),
            None,
            "Hotkeys:",
            "  Cmd+; = Start",
            "  Cmd+' = Stop",
            None,
            rumps.MenuItem("🧪 Test Microphone", callback=self.test_mic),
            rumps.MenuItem("ℹ️  About", callback=self.show_about),
            None,
            rumps.MenuItem("Quit Jarvis", callback=self.quit_app),
        ]

        # Disable stop initially
        self.menu["⏹️  Stop Recording"].set_callback(None)

        self._init_hotkeys()
        print("\n✅ Jarvis ready!")
        print("   Menu bar: Click 🎤 icon")
        print("   Hotkey: Cmd+; to start")
        print()

    def _notify(self, title: str, message: str):
        """Safe notification"""
        try:
            rumps.notification(title, "", message)
        except Exception as e:
            print(f"📢 {title}: {message}")

    def _init_hotkeys(self):
        """Initialize global hotkey listener"""
        def on_press(key):
            # Debounce
            now = time.time()
            if now - self.last_key_time < 0.5:
                return

            # Track Cmd
            if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
                self.cmd_pressed = True
                return

            # Check hotkeys
            if self.cmd_pressed:
                try:
                    char = key.char if hasattr(key, 'char') else None
                    print(f"🔑 Key pressed with Cmd: {repr(char)}")
                    if char == ";":
                        self.last_key_time = now  # Update time before action
                        print(f"🎯 Hotkey: Cmd+; (recording={self.recording}, processing={self.processing})")
                        if not self.recording and not self.processing:
                            print("   → Starting recording")
                            rumps.timer(0.1)(self.menu_start_recording)()
                        else:
                            print("   → Blocked (already active)")
                    elif char == "'":
                        self.last_key_time = now  # Update time before action
                        print(f"🎯 Hotkey: Cmd+' (recording={self.recording}, processing={self.processing})")
                        if self.recording:
                            print("   → Stopping recording")
                            rumps.timer(0.1)(self.menu_stop_recording)()
                        else:
                            print("   → Blocked (not recording)")
                except AttributeError:
                    pass

        def on_release(key):
            if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
                self.cmd_pressed = False

        self.listener = keyboard.Listener(
            on_press=on_press,
            on_release=on_release
        )
        self.listener.start()

    def menu_start_recording(self, _=None):
        """Start recording (from menu or hotkey)"""
        if self.recording or self.processing:
            print("⚠️  Already active")
            return

        self.recording = True
        self.title = "🔴 Recording"

        # Update menu
        self.menu["▶️  Start Recording"].set_callback(None)  # Disable
        self.menu["⏹️  Stop Recording"].set_callback(self.menu_stop_recording)  # Enable

        self._notify("🎤 Recording", "Speak now... (Cmd+' or click Stop)")
        self.voice.start_recording()
        print("🔴 Recording started...")

    def menu_stop_recording(self, _=None):
        """Stop recording (from menu or hotkey)"""
        if not self.recording:
            print("⚠️  Not recording")
            return

        self.recording = False
        self.processing = True
        self.title = "🧠 Processing"

        # Update menu
        self.menu["▶️  Start Recording"].set_callback(None)  # Disable
        self.menu["⏹️  Stop Recording"].set_callback(None)  # Disable

        print("⏹️  Stopped, processing...")
        audio_file = self.voice.stop_recording()

        if audio_file:
            threading.Thread(target=self._transcribe_and_type, args=(audio_file,), daemon=True).start()
        else:
            self._notify("❌ Error", "No audio captured")
            self._reset_state()

    def _transcribe_and_type(self, audio_file: str):
        """Transcribe and type at cursor"""
        text = self.stt.transcribe(audio_file)

        if not text:
            self._notify("❌ No Speech", "Try again")
            self._reset_state()
            return

        print(f"✅ Transcribed: {text}")
        print(f"🖊️  Typing: {repr(text)}")

        # Type using pynput with key presses (most reliable)
        time.sleep(0.5)  # Give time for window focus
        try:
            from pynput.keyboard import Key
            for char in text:
                if char == '\n':
                    self.keyboard_controller.press(Key.enter)
                    self.keyboard_controller.release(Key.enter)
                else:
                    self.keyboard_controller.type(char)
                time.sleep(0.02)  # Slight delay between characters
            print("✅ Typing complete!")
        except Exception as e:
            print(f"❌ Typing failed: {e}")
            import traceback
            traceback.print_exc()

        self._notify("✅ Done!", text[:60])

        # Reset state
        print("🔄 Resetting state...")
        self._reset_state()
        print("✅ State reset complete")

        # Cleanup
        try:
            os.remove(audio_file)
        except:
            pass

    def _reset_state(self):
        """Reset to ready state"""
        print(f"🔄 _reset_state called (recording={self.recording}, processing={self.processing})")
        self.recording = False
        self.processing = False
        self.title = "🎤 Jarvis"
        self.menu["▶️  Start Recording"].set_callback(self.menu_start_recording)
        self.menu["⏹️  Stop Recording"].set_callback(None)
        print(f"✅ State reset done (recording={self.recording}, processing={self.processing})")

    def test_mic(self, _):
        """Test microphone"""
        self._notify("🧪 Testing", "Recording 3 seconds...")

        def test():
            self.voice.start_recording()
            time.sleep(3)
            audio = self.voice.stop_recording()
            if audio:
                text = self.stt.transcribe(audio)
                msg = text if text else "No speech detected"
                self._notify("🧪 Test Result", msg)
                print(f"Test: {msg}")
                try:
                    os.remove(audio)
                except:
                    pass
            else:
                self._notify("❌ Test Failed", "No audio captured")

        threading.Thread(target=test, daemon=True).start()

    def show_about(self, _):
        """Show about dialog"""
        rumps.alert(
            title="About Jarvis",
            message=(
                "🎤 Jarvis Voice Coding Assistant\n\n"
                "A voice-controlled assistant that integrates with Claude Code.\n\n"
                "Features:\n"
                "• Local speech recognition (whisper.cpp)\n"
                "• Global hotkeys (works everywhere)\n"
                "• Auto-types at cursor position\n"
                "• 100% private & free\n\n"
                "Controls:\n"
                "• Cmd+; = Start recording\n"
                "• Cmd+' = Stop recording\n"
                "• Or use menu buttons\n\n"
                "Perfect for voice-coding with Claude!"
            ),
            ok="Got it!",
            cancel=None
        )

    def quit_app(self, _):
        """Quit Jarvis"""
        if self.listener:
            self.listener.stop()
        self.voice.cleanup()
        rumps.quit_application()


if __name__ == "__main__":
    try:
        import rumps
    except ImportError:
        print("❌ Install: pip3 install rumps")
        sys.exit(1)

    app = JarvisApp()
    app.run()
