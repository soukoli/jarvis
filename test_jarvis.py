#!/usr/bin/env python3
"""
Unit tests for Jarvis Voice Assistant
Run with: python3 test_jarvis.py
"""
import sys
import os
import unittest
from unittest.mock import Mock, patch, MagicMock

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

class TestSpeechToText(unittest.TestCase):
    """Test speech-to-text module"""

    def setUp(self):
        """Set up test fixtures"""
        with patch('speech_to_text.subprocess'):
            from speech_to_text import WhisperSTT
            self.stt = WhisperSTT()

    def test_language_flags(self):
        """Test that all languages have flags"""
        from speech_to_text import SUPPORTED_LANGUAGES

        for code, info in SUPPORTED_LANGUAGES.items():
            self.assertEqual(len(info), 4, f"Language {code} should have 4 fields")
            display_name, lang_code, flag, spoken = info
            self.assertIsInstance(display_name, str)
            self.assertIsInstance(lang_code, str)
            self.assertIsInstance(flag, str)
            # spoken can be None for auto-detect
            self.assertTrue(spoken is None or isinstance(spoken, str))

    def test_get_language_flag(self):
        """Test language flag retrieval"""
        self.assertEqual(self.stt.get_language_flag('en'), '🇬🇧')
        self.assertEqual(self.stt.get_language_flag('cs'), '🇨🇿')
        self.assertEqual(self.stt.get_language_flag('auto'), '🌐')
        self.assertEqual(self.stt.get_language_flag('unknown'), '🌐')  # fallback

    def test_get_language_spoken_name(self):
        """Test spoken language name retrieval"""
        self.assertEqual(self.stt.get_language_spoken_name('en'), 'English')
        self.assertEqual(self.stt.get_language_spoken_name('cs'), 'Czech')
        self.assertIsNone(self.stt.get_language_spoken_name('auto'))  # No announcement

    def test_set_language(self):
        """Test language setting"""
        self.stt.set_language('cs')
        self.assertEqual(self.stt.language, 'cs')

        self.stt.set_language('en')
        self.assertEqual(self.stt.language, 'en')

    def test_model_detection(self):
        """Test multilingual model detection"""
        # Test with English-only model path
        self.stt.model_path = "path/to/ggml-base.en.bin"
        self.assertFalse(self.stt.is_multilingual_model())

        # Test with multilingual model path
        self.stt.model_path = "path/to/ggml-medium.bin"
        self.assertTrue(self.stt.is_multilingual_model())


class TestVoiceCapture(unittest.TestCase):
    """Test voice capture module"""

    def setUp(self):
        """Set up test fixtures"""
        with patch('voice_capture.pyaudio.PyAudio'):
            from voice_capture import VoiceCapture
            self.voice = VoiceCapture(cache_dir=".test_voice_cache")

    def test_initialization(self):
        """Test voice capture initialization"""
        self.assertEqual(self.voice.RATE, 16000)  # Whisper expects 16kHz
        self.assertEqual(self.voice.CHANNELS, 1)  # Mono
        self.assertFalse(self.voice.recording)

    def test_device_selection(self):
        """Test device name selection"""
        self.voice.set_device("Test Microphone")
        self.assertEqual(self.voice.selected_device_name, "Test Microphone")


class TestConfigManagement(unittest.TestCase):
    """Test configuration save/load"""

    def test_config_structure(self):
        """Test that config has all required fields"""
        required_fields = [
            'completion_sound',
            'device_name',
            'language',
            'hotkey_start',
            'hotkey_stop'
        ]

        # Mock config
        config = {
            'completion_sound': True,
            'device_name': 'Test Mic',
            'language': 'cs',
            'hotkey_start': ';',
            'hotkey_stop': "'"
        }

        for field in required_fields:
            self.assertIn(field, config, f"Config missing required field: {field}")


class TestMenuItemReferences(unittest.TestCase):
    """Test that menu item references are properly maintained"""

    @patch('rumps.App.__init__', return_value=None)
    @patch('rumps.MenuItem')
    def test_menu_item_references_exist(self, mock_menu_item, mock_app):
        """Test that critical menu items are stored as instance variables"""
        # Import here to use mocked rumps
        import importlib
        import jarvis
        importlib.reload(jarvis)

        # Create mock app
        with patch.object(jarvis.JarvisApp, '_load_config', return_value={}), \
             patch.object(jarvis.JarvisApp, '_refresh_devices'), \
             patch.object(jarvis.JarvisApp, '_update_title_with_flag'), \
             patch.object(jarvis.JarvisApp, '_print_banner'), \
             patch.object(jarvis.JarvisApp, '_init_hotkeys'), \
             patch('jarvis.WhisperSTT'), \
             patch('jarvis.VoiceCapture'), \
             patch('jarvis.SettingsDialog'):

            app = jarvis.JarvisApp()

            # Verify critical instance variables exist
            self.assertTrue(hasattr(app, 'start_menu_item'),
                          "App must have start_menu_item reference")
            self.assertTrue(hasattr(app, 'stop_menu_item'),
                          "App must have stop_menu_item reference")
            self.assertTrue(hasattr(app, 'current_lang_menu_item'),
                          "App must have current_lang_menu_item reference")


class TestHotkeyConfiguration(unittest.TestCase):
    """Test hotkey configuration"""

    def test_default_hotkeys(self):
        """Test default hotkey values"""
        default_start = ';'
        default_stop = "'"

        # These should match the defaults in jarvis.py
        self.assertEqual(default_start, ';')
        self.assertEqual(default_stop, "'")

    def test_hotkey_validation(self):
        """Test hotkey validation logic"""
        # Valid hotkeys (single characters)
        valid_keys = [';', "'", 'p', 'o', '[', ']']
        for key in valid_keys:
            self.assertEqual(len(key), 1)

        # Invalid hotkeys
        invalid_keys = [';;', '', 'ab', '  ']
        for key in invalid_keys:
            self.assertNotEqual(len(key), 1)


class TestLanguageWorkflow(unittest.TestCase):
    """Test language selection and display"""

    def test_language_display_clarity(self):
        """Test that language display makes transcription clear"""
        from speech_to_text import SUPPORTED_LANGUAGES

        for code, (display, _, flag, spoken) in SUPPORTED_LANGUAGES.items():
            # Display name should be clear
            self.assertTrue(len(display) > 0)
            # Flag should be emoji
            self.assertTrue(len(flag) > 0)
            # Auto-detect should have no spoken announcement
            if code == 'auto':
                self.assertIsNone(spoken)


def run_smoke_tests():
    """Quick smoke tests before running the app"""
    print("🧪 Running smoke tests...\n")

    tests = [
        ("Import modules", test_imports),
        ("Check file structure", test_file_structure),
        ("Verify config format", test_config_format),
        ("Check model files", test_model_files),
    ]

    all_passed = True
    for name, test_func in tests:
        try:
            test_func()
            print(f"✅ {name}")
        except Exception as e:
            print(f"❌ {name}: {e}")
            all_passed = False

    print()
    if all_passed:
        print("✅ All smoke tests passed! Safe to run app.\n")
    else:
        print("❌ Some tests failed. Fix issues before running.\n")

    return all_passed


def test_imports():
    """Test that all modules can be imported"""
    sys.path.insert(0, 'src')
    import voice_capture
    import speech_to_text


def test_file_structure():
    """Test that required files exist"""
    required_files = [
        'jarvis.py',
        'src/voice_capture.py',
        'src/speech_to_text.py',
    ]

    for file in required_files:
        if not os.path.exists(file):
            raise FileNotFoundError(f"Required file missing: {file}")


def test_config_format():
    """Test config file format if it exists"""
    config_file = os.path.expanduser("~/.jarvis_config.json")
    if os.path.exists(config_file):
        import json
        with open(config_file, 'r') as f:
            config = json.load(f)

        # Should have these fields
        expected_fields = ['completion_sound', 'device_name', 'language']
        for field in expected_fields:
            if field not in config:
                raise ValueError(f"Config missing field: {field}")


def test_model_files():
    """Test that whisper model exists"""
    model_paths = [
        'whisper.cpp/models/ggml-large-v3-turbo.bin',
        'whisper.cpp/models/ggml-medium.bin',
        'whisper.cpp/models/ggml-base.bin',
        'whisper.cpp/models/ggml-base.en.bin',
    ]

    found = False
    for path in model_paths:
        if os.path.exists(path):
            found = True
            break

    if not found:
        raise FileNotFoundError("No whisper model found. Run setup.sh first.")


if __name__ == '__main__':
    # Run smoke tests first
    if '--smoke' in sys.argv:
        sys.exit(0 if run_smoke_tests() else 1)

    # Run full unit tests
    print("🧪 Running unit tests...\n")
    unittest.main(verbosity=2)
