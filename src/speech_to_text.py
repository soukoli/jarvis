#!/usr/bin/env python3
"""Speech-to-text using whisper.cpp"""
import os
import subprocess
from typing import Optional


class WhisperSTT:
    """Local speech-to-text"""

    def __init__(
        self,
        model_path: Optional[str] = None,
        whisper_bin: Optional[str] = None
    ):
        # Calculate absolute paths relative to this script's location
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        self.whisper_bin = whisper_bin or os.path.join(
            base_dir, "whisper.cpp/build/bin/whisper-cli"
        )
        self.model_path = model_path or os.path.join(
            base_dir, "whisper.cpp/models/ggml-base.en.bin"
        )

    def transcribe(self, audio_file: str) -> Optional[str]:
        """Transcribe audio to text"""
        if not os.path.exists(self.whisper_bin):
            print(f"Whisper not found at {self.whisper_bin}", flush=True)
            return None

        if not os.path.exists(self.model_path):
            print(f"Model not found at {self.model_path}", flush=True)
            return None

        try:
            result = subprocess.run(
                [self.whisper_bin, "-m", self.model_path, "-f", audio_file, "-t", "4", "-nt"],
                capture_output=True,
                text=True,
                timeout=30
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
