#!/usr/bin/env python3
"""Speech-to-text using whisper.cpp"""
import os
import subprocess
from typing import Optional, List

# Supported languages with their Whisper codes, flags, and spoken names
SUPPORTED_LANGUAGES = {
    "auto": ("Auto-detect", "auto", "🌐", None),  # No announcement for auto-detect
    "en": ("English", "en", "🇬🇧", "English"),
    "cs": ("Czech / Čeština", "cs", "🇨🇿", "Czech"),
    "de": ("German / Deutsch", "de", "🇩🇪", "German"),
    "es": ("Spanish / Español", "es", "🇪🇸", "Spanish"),
    "fr": ("French / Français", "fr", "🇫🇷", "French"),
    "it": ("Italian / Italiano", "it", "🇮🇹", "Italian"),
    "pl": ("Polish / Polski", "pl", "🇵🇱", "Polish"),
    "pt": ("Portuguese / Português", "pt", "🇵🇹", "Portuguese"),
    "ru": ("Russian / Русский", "ru", "🇷🇺", "Russian"),
    "sk": ("Slovak / Slovenčina", "sk", "🇸🇰", "Slovak"),
    "uk": ("Ukrainian / Українська", "uk", "🇺🇦", "Ukrainian"),
}

# Language flag emoji mapping
LANGUAGE_FLAGS = {code: info[2] for code, info in SUPPORTED_LANGUAGES.items()}

# Language spoken name mapping (for text-to-speech announcement)
LANGUAGE_SPOKEN_NAMES = {code: info[3] for code, info in SUPPORTED_LANGUAGES.items()}


class WhisperSTT:
    """Local speech-to-text"""

    def __init__(
        self,
        model_path: Optional[str] = None,
        whisper_bin: Optional[str] = None,
        language: str = "auto"
    ):
        # Calculate absolute paths relative to this script's location
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        self.whisper_bin = whisper_bin or os.path.join(
            base_dir, "whisper.cpp/build/bin/whisper-cli"
        )

        # Model priority for best multilingual support:
        # 1. large-v3-turbo (best quality/speed balance for Czech)
        # 2. large-v3 (highest quality but slower)
        # 3. medium (good quality, decent speed)
        # 4. base (fallback for multilingual)
        # 5. base.en (English only, last resort)
        model_priority = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-base.bin",
            "ggml-base.en.bin"
        ]

        default_model = None
        for model_name in model_priority:
            model_path = os.path.join(base_dir, f"whisper.cpp/models/{model_name}")
            if os.path.exists(model_path):
                default_model = model_path
                break

        if not default_model:
            # Really no model found - use medium as target
            default_model = os.path.join(base_dir, "whisper.cpp/models/ggml-medium.bin")

        self.model_path = model_path or default_model
        self.language = language
        self.base_dir = base_dir

    def set_language(self, lang_code: str):
        """Set the transcription language"""
        if lang_code in SUPPORTED_LANGUAGES:
            self.language = lang_code
            print(f"Language set to: {SUPPORTED_LANGUAGES[lang_code][0]}")
        else:
            print(f"Unsupported language: {lang_code}")

    def get_available_languages(self) -> List[tuple]:
        """Return list of (code, display_name) tuples"""
        return [(code, info[0]) for code, info in SUPPORTED_LANGUAGES.items()]

    def get_language_flag(self, lang_code: str) -> str:
        """Get flag emoji for language code"""
        return LANGUAGE_FLAGS.get(lang_code, "🌐")

    def get_language_spoken_name(self, lang_code: str) -> str:
        """Get spoken name for language code (used for TTS announcement)
        Returns None if no announcement should be made (e.g., auto-detect)"""
        return LANGUAGE_SPOKEN_NAMES.get(lang_code, None)

    def is_multilingual_model(self) -> bool:
        """Check if current model supports multiple languages"""
        return ".en." not in self.model_path

    def get_model_info(self) -> str:
        """Return info about current model"""
        model_name = os.path.basename(self.model_path)
        is_multilingual = self.is_multilingual_model()
        return f"{model_name} ({'multilingual' if is_multilingual else 'English only'})"

    def transcribe(self, audio_file: str) -> Optional[str]:
        """Transcribe audio to text"""
        if not os.path.exists(self.whisper_bin):
            print(f"Whisper not found at {self.whisper_bin}", flush=True)
            return None

        if not os.path.exists(self.model_path):
            print(f"Model not found at {self.model_path}", flush=True)
            return None

        # Build command
        cmd = [
            self.whisper_bin,
            "-m", self.model_path,
            "-f", audio_file,
            "-t", "4",              # 4 threads
            "-nt",                  # No timestamps
            "-bo", "5",             # Best of 5 candidates (improves accuracy)
            "-bs", "5",             # Beam size 5 (improves accuracy)
        ]

        # Add language flag for multilingual models
        # CRITICAL: Only add -l flag if NOT auto-detect
        # For auto-detect, whisper needs to detect the language itself
        if self.is_multilingual_model():
            if self.language != "auto":
                cmd.extend(["-l", self.language])
                print(f"Transcribing with language: {self.language}", flush=True)
            else:
                # For auto-detect, don't pass any language flag
                # This allows Whisper to properly detect the spoken language
                print(f"Transcribing with auto-detect (no language constraint)", flush=True)
        else:
            print(f"Using English-only model", flush=True)

        # Debug: print full command
        print(f"Whisper command: {' '.join(cmd)}", flush=True)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60  # Longer timeout for larger models
            )

            if result.returncode != 0:
                print(f"Whisper failed: {result.stderr[:200]}", flush=True)
                return None

            text = result.stdout.strip().replace("[BLANK_AUDIO]", "").strip()
            return text if text else None

        except subprocess.TimeoutExpired:
            print(f"Whisper timeout", flush=True)
            return None
        except Exception as e:
            print(f"Whisper error: {e}", flush=True)
            return None
