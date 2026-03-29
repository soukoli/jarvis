#!/usr/bin/env python3
"""Speech-to-text using whisper.cpp"""
import os
import subprocess
from typing import Optional


class WhisperSTT:
    """Local speech-to-text"""

    def __init__(
        self,
        model_path: str = "whisper.cpp/models/ggml-base.en.bin",
        whisper_bin: str = "whisper.cpp/build/bin/whisper-cli"
    ):
        self.model_path = model_path
        self.whisper_bin = whisper_bin

    def transcribe(self, audio_file: str) -> Optional[str]:
        """Transcribe audio to text"""
        if not os.path.exists(self.whisper_bin):
            print(f"❌ Whisper not found at {self.whisper_bin}")
            return None

        if not os.path.exists(self.model_path):
            print(f"❌ Model not found at {self.model_path}")
            return None

        try:
            result = subprocess.run(
                [self.whisper_bin, "-m", self.model_path, "-f", audio_file, "-t", "4", "-nt"],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                return None

            text = result.stdout.strip().replace("[BLANK_AUDIO]", "").strip()
            return text if text else None

        except (subprocess.TimeoutExpired, Exception):
            return None
