#!/usr/bin/env python3
"""
Streaming Speech-to-Text using faster-whisper + Silero VAD
Processes audio in chunks for near-realtime transcription.

Architecture:
    Mic → PyAudio → VAD (speech detection) → Buffer chunks → faster-whisper → text
    
Benefits over whisper.cpp CLI:
    - Streaming: process while recording, don't wait for full file
    - VAD: smart segmentation by speech pauses (not fixed time)
    - Lower latency: partial results available as you speak
    - In-memory: no temp WAV files on disk
"""
import os
import io
import re
import time
import wave
import threading
import numpy as np
from typing import Optional, List, Callable
from collections import deque

import pyaudio
import torch

# Lazy imports for heavy libraries
_whisper_model = None
_vad_model = None

# Known hallucination patterns (Whisper generates these from training data noise)
_HALLUCINATION_PATTERNS = [
    r"[Tt]itulky\s+(vytvořil|přiložil|přeložil)\s*\w*",
    r"[Jj]ohnn?y\s*X",
    r"[Dd]ěkuji?\s+za\s+pozornost",
    r"[Oo]debírejte",
    r"[Nn]apište\s+do\s+komentářů",
    r"[Dd]alší\s+díl\s+příště",
    r"[Ss]ubtitles?\s+by",
    r"[Ss]ubscribe",
    r"[Tt]hank\s+you\s+for\s+watching",
    r"[Pp]řeklad\s*:",
    r"[Ss]ponzorováno",
    r"[Aa]mara\.org",
    r"[Ww]ww\.\w+\.\w+",  # URLs
]
_HALLUCINATION_RE = re.compile("|".join(_HALLUCINATION_PATTERNS))


def _is_hallucination(text: str) -> bool:
    """Check if text is a known Whisper hallucination"""
    if not text or not text.strip():
        return True
    cleaned = _HALLUCINATION_RE.sub("", text).strip()
    # If after removing hallucination patterns almost nothing remains, it's a hallucination
    if len(cleaned) < 3:
        return True
    # Repetitive text (same word/phrase repeated) is also hallucination
    words = cleaned.split()
    if len(words) >= 4 and len(set(words)) <= 2:
        return True
    return False


def _get_vad_model():
    """Lazy-load Silero VAD model"""
    global _vad_model
    if _vad_model is None:
        import silero_vad
        _vad_model = silero_vad.load_silero_vad()
    return _vad_model


# MLX Whisper is preferred (Apple Silicon GPU), fallback to faster-whisper (CPU)
_USE_MLX = False
try:
    import mlx_whisper as _mlx_whisper
    _USE_MLX = True
except ImportError:
    _mlx_whisper = None


def _get_whisper_model(model_size: str = "large-v3-turbo", device: str = "cpu", compute_type: str = "int8"):
    """Lazy-load whisper model (MLX preferred, faster-whisper fallback)"""
    global _whisper_model
    if _whisper_model is None:
        if _USE_MLX:
            # MLX: just store the model repo path, actual model loads on first transcribe call
            print(f"Using MLX Whisper: {model_size} (Apple Silicon GPU)...", flush=True)
            _whisper_model = ("mlx", f"mlx-community/whisper-{model_size}")
        else:
            from faster_whisper import WhisperModel
            print(f"Loading faster-whisper model: {model_size} ({compute_type})...", flush=True)
            start = time.time()
            _whisper_model = ("faster-whisper", WhisperModel(
                model_size,
                device=device,
                compute_type=compute_type,
                cpu_threads=8
            ))
            print(f"Model loaded in {time.time()-start:.1f}s", flush=True)
    return _whisper_model


# Supported languages
SUPPORTED_LANGUAGES = {
    "auto": ("Auto-detect", "🌐", None),
    "en": ("English", "🇬🇧", "English"),
    "cs": ("Czech / Čeština", "🇨🇿", "Czech"),
    "de": ("German / Deutsch", "🇩🇪", "German"),
    "es": ("Spanish / Español", "🇪🇸", "Spanish"),
    "fr": ("French / Français", "🇫🇷", "French"),
    "it": ("Italian / Italiano", "🇮🇹", "Italian"),
    "pl": ("Polish / Polski", "🇵🇱", "Polish"),
    "pt": ("Portuguese / Português", "🇵🇹", "Portuguese"),
    "ru": ("Russian / Русский", "🇷🇺", "Russian"),
    "sk": ("Slovak / Slovenčina", "🇸🇰", "Slovak"),
    "uk": ("Ukrainian / Українська", "🇺🇦", "Ukrainian"),
}


class StreamingSTT:
    """
    Streaming speech-to-text with VAD-based chunking.
    
    Instead of recording a full file and then transcribing,
    this processes audio in chunks as you speak:
    
    1. Audio flows in from mic continuously
    2. Silero VAD detects speech vs silence
    3. When a speech segment ends (pause detected), that chunk is transcribed
    4. Partial transcripts are accumulated
    5. Final result is all chunks joined together
    """

    def __init__(
        self,
        model_size: str = "large-v3-turbo",
        language: str = "auto",
        # VAD settings
        vad_threshold: float = 0.5,          # Speech probability threshold (higher = stricter)
        min_speech_ms: int = 250,            # Minimum speech duration to process
        min_silence_ms: int = 600,           # Silence duration to trigger chunk end
        # Audio settings
        sample_rate: int = 16000,
        chunk_size: int = 512,               # Samples per VAD frame (32ms at 16kHz)
        # Processing
        on_partial: Optional[Callable[[str], None]] = None,  # Callback for partial results
    ):
        self.model_size = model_size
        self.language = language
        self.vad_threshold = vad_threshold
        self.min_speech_ms = min_speech_ms
        self.min_silence_ms = min_silence_ms
        self.sample_rate = sample_rate
        self.chunk_size = chunk_size
        self.on_partial = on_partial

        # State
        self._recording = False
        self._audio = None
        self._stream = None
        self._thread = None
        self._transcripts: List[str] = []
        self._lock = threading.Lock()
        self._processing_count = 0

        # Device selection
        self._selected_device_name: Optional[str] = None

    def set_language(self, lang_code: str):
        """Set transcription language"""
        if lang_code in SUPPORTED_LANGUAGES:
            self.language = lang_code

    def get_available_languages(self) -> List[tuple]:
        """Return list of (code, display_name) tuples"""
        return [(code, info[0]) for code, info in SUPPORTED_LANGUAGES.items()]

    def get_language_flag(self, lang_code: str) -> str:
        """Get flag emoji for language code"""
        return SUPPORTED_LANGUAGES.get(lang_code, ("", "🌐", None))[1]

    def get_language_spoken_name(self, lang_code: str) -> Optional[str]:
        """Get spoken name for TTS announcement"""
        info = SUPPORTED_LANGUAGES.get(lang_code)
        return info[2] if info else None

    def is_multilingual_model(self) -> bool:
        """Check if model supports multiple languages"""
        return ".en" not in self.model_size

    def get_model_info(self) -> str:
        """Return info about current model"""
        backend = "MLX/Apple GPU" if _USE_MLX else "faster-whisper/CPU"
        return f"{self.model_size} ({backend}, streaming)"

    def set_device(self, device_name: str):
        """Set input device by name"""
        self._selected_device_name = device_name

    def get_input_devices(self) -> List[dict]:
        """Get available input devices"""
        audio = pyaudio.PyAudio()
        devices = []
        try:
            for i in range(audio.get_device_count()):
                info = audio.get_device_info_by_index(i)
                if info['maxInputChannels'] > 0:
                    devices.append({
                        'index': i,
                        'name': info['name'],
                        'channels': info['maxInputChannels'],
                        'default_sample_rate': info['defaultSampleRate']
                    })
        finally:
            audio.terminate()
        return devices

    def _find_device_index(self) -> Optional[int]:
        """Find device index for selected device"""
        audio = pyaudio.PyAudio()
        try:
            if self._selected_device_name:
                for i in range(audio.get_device_count()):
                    info = audio.get_device_info_by_index(i)
                    if info['maxInputChannels'] > 0 and info['name'] == self._selected_device_name:
                        return i
                print(f"Warning: Device '{self._selected_device_name}' not found, using default", flush=True)

            # Fallback to first available
            for i in range(audio.get_device_count()):
                info = audio.get_device_info_by_index(i)
                if info['maxInputChannels'] > 0:
                    return i
        finally:
            audio.terminate()
        return None

    def start_recording(self):
        """Start streaming recording with real-time processing"""
        if self._recording:
            return

        self._recording = True
        self._transcripts = []
        self._processing_count = 0

        # Pre-load models in background (first call only)
        threading.Thread(target=self._preload_models, daemon=True).start()

        # Start audio capture thread
        self._thread = threading.Thread(target=self._capture_and_process, daemon=True)
        self._thread.start()

    def stop_recording(self) -> Optional[str]:
        """Stop recording and return full transcript"""
        if not self._recording:
            return None

        self._recording = False

        # Wait for capture thread to finish
        if self._thread:
            self._thread.join(timeout=3)

        # Wait for any pending transcriptions (longer timeout for cold start)
        timeout = time.time() + 15
        while self._processing_count > 0 and time.time() < timeout:
            time.sleep(0.1)

        # Join all partial transcripts
        with self._lock:
            full_text = " ".join(t for t in self._transcripts if t.strip())

        return full_text.strip() if full_text.strip() else None

    def _preload_models(self):
        """Pre-load heavy models"""
        try:
            _get_vad_model()
            _get_whisper_model(self.model_size)
        except Exception as e:
            print(f"Error preloading models: {e}", flush=True)

    def _capture_and_process(self):
        """Main capture loop: read audio, VAD, chunk, transcribe"""
        import silero_vad

        self._audio = pyaudio.PyAudio()
        device_index = self._find_device_index()

        if device_index is None:
            print("No input device found", flush=True)
            self._recording = False
            return

        try:
            self._stream = self._audio.open(
                format=pyaudio.paInt16,
                channels=1,
                rate=self.sample_rate,
                input=True,
                input_device_index=device_index,
                frames_per_buffer=self.chunk_size
            )
        except Exception as e:
            print(f"Failed to open audio stream: {e}", flush=True)
            self._recording = False
            self._audio.terminate()
            return

        vad = _get_vad_model()

        # State for VAD-based chunking
        speech_buffer = []          # Accumulate speech frames
        silence_frames = 0          # Count consecutive silence frames
        is_speaking = False         # Currently in speech segment
        
        frames_per_ms = self.sample_rate / 1000
        silence_frames_threshold = int(self.min_silence_ms * frames_per_ms / self.chunk_size)
        min_speech_frames = int(self.min_speech_ms * frames_per_ms / self.chunk_size)

        try:
            while self._recording:
                try:
                    raw_data = self._stream.read(self.chunk_size, exception_on_overflow=False)
                except Exception:
                    break

                # Convert to float32 for VAD
                audio_int16 = np.frombuffer(raw_data, dtype=np.int16)
                audio_float = audio_int16.astype(np.float32) / 32768.0

                # Run VAD
                audio_tensor = torch.from_numpy(audio_float)
                speech_prob = vad(audio_tensor, self.sample_rate).item()

                if speech_prob >= self.vad_threshold:
                    # Speech detected
                    is_speaking = True
                    silence_frames = 0
                    speech_buffer.append(audio_int16)
                else:
                    if is_speaking:
                        silence_frames += 1
                        speech_buffer.append(audio_int16)  # Include trailing silence

                        # Check if pause is long enough to trigger chunk end
                        if silence_frames >= silence_frames_threshold:
                            # End of speech segment - process this chunk
                            if len(speech_buffer) >= min_speech_frames:
                                chunk_audio = np.concatenate(speech_buffer)
                                self._transcribe_chunk(chunk_audio)

                            # Reset
                            speech_buffer = []
                            silence_frames = 0
                            is_speaking = False

        finally:
            # Process any remaining speech buffer
            if speech_buffer and len(speech_buffer) >= min_speech_frames:
                chunk_audio = np.concatenate(speech_buffer)
                self._transcribe_chunk(chunk_audio)

            # Cleanup audio
            if self._stream:
                self._stream.stop_stream()
                self._stream.close()
            if self._audio:
                self._audio.terminate()
                self._audio = None

    def _transcribe_chunk(self, audio_data: np.ndarray):
        """Transcribe a chunk of audio in background thread"""
        self._processing_count += 1
        threading.Thread(
            target=self._do_transcribe,
            args=(audio_data,),
            daemon=True
        ).start()

    def _do_transcribe(self, audio_data: np.ndarray):
        """Actually perform transcription of audio chunk"""
        try:
            backend, model = _get_whisper_model(self.model_size)

            # Convert to float32 normalized
            audio_float = audio_data.astype(np.float32) / 32768.0

            if backend == "mlx":
                # MLX Whisper (Apple Silicon GPU)
                kwargs = {
                    "path_or_hf_repo": model,
                    "language": self.language if self.language != "auto" else None,
                    "condition_on_previous_text": False,
                    "no_speech_threshold": 0.6,
                    "compression_ratio_threshold": 2.4,
                    "word_timestamps": False,
                }
                result = _mlx_whisper.transcribe(audio_float, **kwargs)
                chunk_text = result.get("text", "").strip()

            else:
                # faster-whisper (CPU fallback)
                kwargs = {
                    "beam_size": 3,
                    "best_of": 2,
                    "vad_filter": False,
                    "without_timestamps": True,
                    "no_speech_threshold": 0.6,
                    "log_prob_threshold": -1.0,
                    "condition_on_previous_text": False,
                    "suppress_blank": True,
                }
                if self.language != "auto" and self.is_multilingual_model():
                    kwargs["language"] = self.language

                segments, info = model.transcribe(audio_float, **kwargs)

                text_parts = []
                for segment in segments:
                    if segment.no_speech_prob > 0.6:
                        continue
                    if segment.avg_logprob < -1.0:
                        continue
                    txt = segment.text.strip()
                    if txt and txt != "[BLANK_AUDIO]":
                        text_parts.append(txt)

                chunk_text = " ".join(text_parts)

            # Filter hallucinations
            if chunk_text and not _is_hallucination(chunk_text):
                chunk_text = _HALLUCINATION_RE.sub("", chunk_text).strip()
                chunk_text = re.sub(r"\s+", " ", chunk_text)

                if chunk_text:
                    with self._lock:
                        self._transcripts.append(chunk_text)

                    if self.on_partial:
                        self.on_partial(chunk_text)

                    print(f"  [chunk] {chunk_text}", flush=True)
            elif chunk_text:
                print(f"  [filtered hallucination] {chunk_text}", flush=True)

        except Exception as e:
            print(f"Transcription error: {e}", flush=True)
        finally:
            self._processing_count -= 1

    # === Legacy compatibility methods ===

    def transcribe(self, audio_file: str) -> Optional[str]:
        """Legacy: transcribe a WAV file (for backward compat with jarvis.py)"""
        try:
            backend, model = _get_whisper_model(self.model_size)

            if backend == "mlx":
                kwargs = {
                    "path_or_hf_repo": model,
                    "language": self.language if self.language != "auto" else None,
                    "condition_on_previous_text": False,
                    "no_speech_threshold": 0.6,
                    "compression_ratio_threshold": 2.4,
                    "word_timestamps": False,
                }
                result = _mlx_whisper.transcribe(audio_file, **kwargs)
                text = result.get("text", "").strip()
            else:
                kwargs = {
                    "beam_size": 3,
                    "best_of": 2,
                    "vad_filter": True,
                    "without_timestamps": True,
                    "no_speech_threshold": 0.6,
                    "log_prob_threshold": -1.0,
                    "condition_on_previous_text": False,
                    "suppress_blank": True,
                }
                if self.language != "auto" and self.is_multilingual_model():
                    kwargs["language"] = self.language

                segments, info = model.transcribe(audio_file, **kwargs)
                text_parts = []
                for segment in segments:
                    if segment.no_speech_prob > 0.6:
                        continue
                    txt = segment.text.strip()
                    if txt and txt != "[BLANK_AUDIO]":
                        text_parts.append(txt)
                text = " ".join(text_parts)

            if text and not _is_hallucination(text):
                text = _HALLUCINATION_RE.sub("", text).strip()
                text = re.sub(r"\s+", " ", text)
                return text if text else None
            return None

        except Exception as e:
            print(f"Transcription error: {e}", flush=True)
            return None
