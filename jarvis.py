#!/usr/bin/env python3
"""
Jarvis - Voice-to-text assistant for macOS
Records voice, transcribes locally, copies to clipboard
"""
import os
import sys
import time
import json
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
        # Will be updated with language flag after config is loaded
        super().__init__("🎤", quit_button=None)

        # Config file path
        self.config_file = os.path.expanduser("~/.jarvis_config.json")

        # Core components
        self.voice = VoiceCapture()
        self.stt = WhisperSTT()

        # State management
        self.recording = False
        self.processing = False
        self._state_lock = threading.Lock()

        # User preferences - load from config
        config = self._load_config()
        self.completion_sound = config.get('completion_sound', True)
        self.language_announcement = config.get('language_announcement', True)  # New setting
        self.available_devices = []
        self.current_device_name = config.get('device_name', None)
        self.current_language = config.get('language', 'auto')
        self.hotkey_start = config.get('hotkey_start', ';')
        self.hotkey_stop = config.get('hotkey_stop', "'")
        self.hotkey_cancel = config.get('hotkey_cancel', '.')  # Cancel key

        # Set language in STT engine
        self.stt.set_language(self.current_language)

        # Menu items we need to update later
        self.current_lang_menu_item = None
        self.lang_submenu_items = []

        # Get available input devices
        self._refresh_devices()

        # Apply saved device selection
        if self.current_device_name:
            self.voice.set_device(self.current_device_name)

        # Set initial title with language flag
        self._update_title_with_flag()

        # Hotkey tracking
        self.cmd_pressed = False
        self.last_key_time = 0

        # Build menu - SIMPLIFIED
        lang_submenu = self._build_language_menu()

        # Store reference to current language menu item
        lang_display = self._get_language_display(self.current_language)
        self.current_lang_menu_item = rumps.MenuItem(f"🌍  {lang_display}", callback=None)

        # Create menu items and store references
        self.start_menu_item = rumps.MenuItem(f"▶️  Start Recording (Cmd+{self.hotkey_start})", callback=self.start_recording)
        self.stop_menu_item = rumps.MenuItem(f"⏹️  Stop Recording (Cmd+{self.hotkey_stop})", callback=None)
        self.cancel_menu_item = rumps.MenuItem(f"❌ Cancel (Cmd+{self.hotkey_cancel})", callback=None)
        self.sound_menu_item = rumps.MenuItem("🔊 Completion Sound", callback=self.toggle_sound)
        self.announcement_menu_item = rumps.MenuItem("🗣️ Language Announcement", callback=self.toggle_announcement)

        # Build clean, simple menu
        self.menu = [
            self.start_menu_item,
            self.stop_menu_item,
            self.cancel_menu_item,
            None,
            "🗣️ Transcription Language:",
            self.current_lang_menu_item,
            (rumps.MenuItem("Change Language..."), lang_submenu),
            None,
            self.sound_menu_item,
            self.announcement_menu_item,
            None,
            rumps.MenuItem("ℹ️  About", callback=self.show_about),
            None,
            rumps.MenuItem("Quit Jarvis", callback=rumps.quit_application)
        ]

        # Set initial checkmarks
        self.sound_menu_item.state = 1 if self.completion_sound else 0
        self.announcement_menu_item.state = 1 if self.language_announcement else 0

        self._print_banner()
        self._init_hotkeys()

    def _load_config(self) -> dict:
        """Load configuration from file"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    return json.load(f)
        except Exception as e:
            print(f"Warning: Could not load config: {e}")
        return {}

    def _save_config(self):
        """Save configuration to file"""
        try:
            config = {
                'completion_sound': self.completion_sound,
                'language_announcement': self.language_announcement,
                'device_name': self.current_device_name,
                'language': self.current_language,
                'hotkey_start': self.hotkey_start,
                'hotkey_stop': self.hotkey_stop,
                'hotkey_cancel': self.hotkey_cancel
            }
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
        except Exception as e:
            print(f"Warning: Could not save config: {e}")

    def _print_banner(self):
        """Print startup banner"""
        print("\n╔════════════════════════════════════════════════════╗")
        print("║  🎤 JARVIS VOICE ASSISTANT v2.1                   ║")
        print("╚════════════════════════════════════════════════════╝\n")
        print("Controls:")
        print(f"  Cmd+{self.hotkey_start}  = START recording")
        print(f"  Cmd+{self.hotkey_stop}  = STOP recording")
        print(f"  Cmd+{self.hotkey_cancel}  = CANCEL (abort)")
        print("")
        print("Feedback:")
        print("  🔴 Menu bar → Recording")
        print("  🧠 Menu bar → Transcribing (wait!)")
        print("  🔊 Sound    → Ready to paste")
        print("  🎤 Menu bar → Back to ready\n")
        print(f"Selected language: {self._get_language_display(self.current_language)}")
        print(f"Model: {self.stt.get_model_info()}\n")

    def _refresh_devices(self):
        """Refresh available input devices"""
        try:
            self.available_devices = self.voice.get_input_devices()
            if not self.available_devices:
                print("Warning: No input devices found")
        except Exception as e:
            print(f"Error getting input devices: {e}")
            self.available_devices = []

    def _select_device(self, device):
        """Select a microphone device"""
        self.voice.set_device(device['name'])
        self.current_device_name = device['name']

        # Save to config
        self._save_config()

        print(f"Selected microphone: {device['name']}")

    def _get_language_display(self, lang_code: str) -> str:
        """Get display name for language code"""
        languages = self.stt.get_available_languages()
        for code, name in languages:
            if code == lang_code:
                return name
        return lang_code

    def _build_language_menu(self):
        """Build language selection submenu"""
        lang_items = []
        self.lang_submenu_items = []

        for code, name in self.stt.get_available_languages():
            item = rumps.MenuItem(
                name,
                callback=lambda sender, c=code: self._select_language(c)
            )
            # Mark current language
            if self.current_language == code:
                item.state = 1
            lang_items.append(item)
            self.lang_submenu_items.append((code, item))

        return lang_items

    def _select_language(self, lang_code: str):
        """Select a language"""
        self.current_language = lang_code
        self.stt.set_language(lang_code)

        # Save to config
        self._save_config()

        # Update menu display
        if self.current_lang_menu_item:
            lang_display = self._get_language_display(lang_code)
            self.current_lang_menu_item.title = f"🌍  {lang_display}"

        # Update checkmarks in submenu
        for code, item in self.lang_submenu_items:
            item.state = 1 if code == lang_code else 0

        # Update title with new language flag
        self._update_title_with_flag()

        print(f"Language set to: {lang_display}")

        # Warn if using English-only model for non-English language
        if lang_code not in ("auto", "en") and not self.stt.is_multilingual_model():
            print(f"⚠️  Warning: Current model is English-only. Download a multilingual model for best {lang_code} results.")
            rumps.notification(
                title="⚠️  English-only Model",
                subtitle=f"Selected: {lang_display}",
                message="Go to Settings → Download Better Model for multilingual support"
            )

    def _update_title_with_flag(self, state: str = "ready"):
        """Update menu bar title with current language flag"""
        flag = self.stt.get_language_flag(self.current_language)

        if state == "ready":
            self.title = f"🎤 {flag}"
        elif state == "recording":
            self.title = f"🔴 {flag}"
        elif state == "processing":
            self.title = f"🧠 {flag}"

    def _announce_language(self):
        """Announce the current language with speech and play notification sound"""
        # Skip if announcement is disabled
        if not self.language_announcement:
            return

        try:
            # Get the spoken name for the current language
            spoken_name = self.stt.get_language_spoken_name(self.current_language)

            # Only speak if there's a spoken name (not None for auto-detect)
            if spoken_name:
                # Use macOS 'say' command to speak the language name
                # Run in background so it doesn't block
                subprocess.Popen(
                    ['say', '-v', 'Samantha', '-r', '200', spoken_name],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )

                # Small delay to let speech start
                time.sleep(0.3)

            # Play notification sound (Tink is short and pleasant)
            subprocess.Popen(
                ['afplay', '/System/Library/Sounds/Tink.aiff'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except Exception as e:
            print(f"Warning: Could not announce language: {e}", flush=True)
            # Continue with recording even if announcement fails

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
                    if char == self.hotkey_start:
                        self.last_key_time = now
                        rumps.timer(0.05)(self.start_recording)()
                    elif char == self.hotkey_stop:
                        self.last_key_time = now
                        rumps.timer(0.05)(self.stop_recording)()
                    elif char == self.hotkey_cancel:
                        self.last_key_time = now
                        rumps.timer(0.05)(self.cancel_operation)()
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

        # Announce language and play notification sound
        self._announce_language()

        print(f"[{time.strftime('%H:%M:%S')}] Recording started", flush=True)
        self._update_title_with_flag("recording")
        self.start_menu_item.set_callback(None)
        self.stop_menu_item.set_callback(self.stop_recording)
        self.cancel_menu_item.set_callback(self.cancel_operation)
        self.voice.start_recording()

    def stop_recording(self, _=None):
        """Stop recording and process"""
        with self._state_lock:
            if not self.recording:
                return
            self.recording = False
            self.processing = True

        print(f"[{time.strftime('%H:%M:%S')}] Recording stopped", flush=True)
        self._update_title_with_flag("processing")
        self.start_menu_item.set_callback(None)
        self.stop_menu_item.set_callback(None)
        self.cancel_menu_item.set_callback(self.cancel_operation)

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
        self._save_config()

    def toggle_announcement(self, sender):
        """Toggle language announcement"""
        self.language_announcement = not self.language_announcement
        sender.state = 1 if self.language_announcement else 0
        self._save_config()

    def cancel_operation(self, _=None):
        """Cancel recording or transcription"""
        with self._state_lock:
            if not self.recording and not self.processing:
                return  # Nothing to cancel

            was_recording = self.recording
            was_processing = self.processing

            self.recording = False
            self.processing = False

        # Stop voice recording if active
        if was_recording:
            try:
                self.voice.stop_recording()
                print(f"[{time.strftime('%H:%M:%S')}] Recording cancelled", flush=True)
            except:
                pass

        if was_processing:
            print(f"[{time.strftime('%H:%M:%S')}] Transcription cancelled", flush=True)

        # Show notification
        rumps.notification(
            title="Cancelled",
            subtitle="Operation stopped",
            message="Recording/transcription aborted"
        )

        self._reset_state()

    def _reset_state(self):
        """Reset to ready state"""
        with self._state_lock:
            self.recording = False
            self.processing = False

        self._update_title_with_flag("ready")
        self.start_menu_item.set_callback(self.start_recording)
        self.stop_menu_item.set_callback(None)
        self.cancel_menu_item.set_callback(None)

    def show_about(self, _=None):
        """Show about dialog"""
        rumps.alert(
            title="About Jarvis",
            message=(
                "🎤 Jarvis Voice Assistant v2.1\n\n"
                "Local voice-to-text transcription with clipboard workflow.\n\n"
                "How it works:\n"
                f"1. Cmd+{self.hotkey_start} → Start recording (hear language + beep)\n"
                "2. Speak clearly in your selected language\n"
                f"3. Cmd+{self.hotkey_stop} → Stop & transcribe\n"
                f"4. Cmd+{self.hotkey_cancel} → Cancel/abort anytime\n"
                "5. Hear 'ding' → Text ready on clipboard\n"
                "6. Cmd+V → Paste transcribed text anywhere\n\n"
                "Keyboard shortcuts:\n"
                f"  Cmd+{self.hotkey_start}  = Start recording\n"
                f"  Cmd+{self.hotkey_stop}  = Stop & transcribe\n"
                f"  Cmd+{self.hotkey_cancel}  = Cancel/abort\n\n"
                "Menu bar shows status:\n"
                "🎤 🇬🇧 Ready | 🔴 🇨🇿 Recording | 🧠 🇩🇪 Transcribing\n\n"
                "Important: The flag shows your selected language.\n"
                "Text is transcribed (not translated) in that language."
            )
        )


if __name__ == "__main__":
    app = JarvisApp()
    app.run()
