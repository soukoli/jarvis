#!/usr/bin/env python3
"""
Jarvis Global - System-wide voice assistant
Works in ANY application, auto-types transcription
"""
import os
import sys
import time
import threading
from pynput import keyboard
from pynput.keyboard import Controller, Key
import rumps  # For macOS menu bar app
import subprocess

# Import our existing modules
sys.path.insert(0, os.path.dirname(__file__))
from voice_capture import VoiceCapture
from speech_to_text import WhisperSTT


class JarvisGlobal(rumps.App):
    """
    Global voice assistant that runs in menu bar
    """
    def __init__(self):
        super(JarvisGlobal, self).__init__(
            "🎤",
            title="Jarvis",
            quit_button=None
        )

        self.voice_capture = VoiceCapture()
        self.stt = WhisperSTT()
        self.kb = Controller()
        self.is_recording = False
        self.hotkey = "`"  # Default trigger

        # Menu items
        self.menu = [
            rumps.MenuItem("Status: Ready", callback=None),
            rumps.separator,
            rumps.MenuItem("Change Hotkey", callback=self.change_hotkey),
            rumps.MenuItem("Test Microphone", callback=self.test_mic),
            rumps.separator,
            rumps.MenuItem("Quit", callback=self.quit_app)
        ]

        # Start global listener
        self.listener = None
        self.start_listener()

        print("🚀 Jarvis Global started!")
        print(f"   Press {self.hotkey} to toggle recording")
        print("   Icon in menu bar")

    def notify(self, title, subtitle, message):
        """Send notification with error handling"""
        try:
            rumps.notification(title=title, subtitle=subtitle, message=message)
        except Exception as e:
            print(f"📢 {title}: {subtitle} - {message}")
            print(f"   (Notification failed: {e})")

    def start_listener(self):
        """Start global keyboard listener"""
        def on_press(key):
            try:
                # Check if our hotkey was pressed
                if hasattr(key, 'char') and key.char == self.hotkey:
                    self.toggle_recording()
            except:
                pass

        self.listener = keyboard.Listener(on_press=on_press)
        self.listener.start()

    def toggle_recording(self):
        """Toggle recording on/off"""
        if not self.is_recording:
            # Start recording
            self.start_recording()
        else:
            # Stop recording
            self.stop_recording()

    def start_recording(self):
        """Start voice recording"""
        if self.is_recording:
            return

        self.is_recording = True
        self.title = "🔴"  # Red dot while recording
        self.menu["Status: Ready"].title = "Status: 🔴 Recording..."

        # Show notification
        self.notify(
            "Jarvis Listening",
            "Speak now...",
            f"Press {self.hotkey} again to stop"
        )

        # Start recording in background
        self.voice_capture.start_recording()
        print("🔴 Recording started...")

    def stop_recording(self):
        """Stop recording and transcribe"""
        if not self.is_recording:
            return

        self.is_recording = False
        self.title = "🎤"
        self.menu["Status: Ready"].title = "Status: 🧠 Transcribing..."

        print("⏹️  Recording stopped, transcribing...")

        # Stop recording and get file
        audio_file = self.voice_capture.stop_recording()

        if not audio_file:
            self.notify(
                "Jarvis Error",
                "No audio captured",
                "Try again"
            )
            self.menu["Status: Ready"].title = "Status: Ready"
            return

        # Transcribe in background thread
        threading.Thread(target=self.process_audio, args=(audio_file,), daemon=True).start()

    def process_audio(self, audio_file):
        """Process audio file"""
        # Transcribe
        text = self.stt.transcribe(audio_file)

        if not text:
            self.notify(
                "Jarvis Error",
                "No speech detected",
                "Try speaking more clearly"
            )
            self.menu["Status: Ready"].title = "Status: Ready"
            return

        print(f"✅ Transcribed: {text}")

        # Auto-type the text!
        self.auto_type(text)

        # Show success notification
        self.notify(
            "Jarvis Success",
            "Text inserted",
            text[:50] + ("..." if len(text) > 50 else "")
        )

        self.menu["Status: Ready"].title = "Status: Ready"

        # Cleanup
        try:
            os.remove(audio_file)
        except:
            pass

    def auto_type(self, text):
        """Type text into current application"""
        # Small delay to ensure window is focused
        time.sleep(0.3)

        # Type the text character by character
        for char in text:
            self.kb.type(char)
            time.sleep(0.01)  # Small delay between chars

    def change_hotkey(self, _):
        """Change the hotkey"""
        response = rumps.Window(
            title="Change Hotkey",
            message="Enter new hotkey (single character):",
            default_text=self.hotkey,
            ok="Change",
            cancel="Cancel"
        ).run()

        if response.clicked and response.text:
            old_hotkey = self.hotkey
            self.hotkey = response.text[0]
            self.notify(
                "Hotkey Changed",
                f"New hotkey: {self.hotkey}",
                f"Old: {old_hotkey}"
            )

    def test_mic(self, _):
        """Test microphone"""
        self.notify("Testing Microphone", "Recording for 3 seconds...", "Speak now!")

        # Run test in thread to not block UI
        def run_test():
            self.voice_capture.start_recording()
            time.sleep(3)
            audio_file = self.voice_capture.stop_recording()

            if audio_file:
                text = self.stt.transcribe(audio_file)
                if text:
                    self.notify("Microphone Test Success", "You said:", text)
                else:
                    self.notify("Microphone Test Failed", "No speech detected", "Check your microphone")
                try:
                    os.remove(audio_file)
                except:
                    pass
            else:
                self.notify("Microphone Test Failed", "No audio captured", "Check your microphone")

        threading.Thread(target=run_test, daemon=True).start()

    def quit_app(self, _):
        """Quit the app"""
        if self.listener:
            self.listener.stop()
        rumps.quit_application()


if __name__ == "__main__":
    # Check if rumps is installed
    try:
        import rumps
    except ImportError:
        print("❌ rumps not installed")
        print("   Install with: pip3 install rumps")
        sys.exit(1)

    app = JarvisGlobal()
    app.run()
