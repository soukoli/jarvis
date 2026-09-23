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
from typing import Optional, List, Dict, Callable
from collections import deque

import pyaudio
import torch

# Lazy imports for heavy libraries
_whisper_model = None
_vad_model = None
_model_load_lock = threading.Lock()   # Protects _whisper_model initialization

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
    if len(cleaned) < 3:
        return True

    words = cleaned.lower().split()

    # Too few unique words relative to total (ratio-based — catches "elected elected elected...")
    if len(words) >= 6 and len(set(words)) / len(words) < 0.35:
        return True

    # Legacy strict check for very short repetitive text
    if len(words) >= 4 and len(set(words)) <= 2:
        return True

    # Bigram repetition — catches phrase loops like "I think I think I think"
    bigrams = list(zip(words, words[1:]))
    if len(bigrams) >= 4 and len(set(bigrams)) / len(bigrams) < 0.5:
        return True

    return False


def _is_near_duplicate(a: str, b: str) -> bool:
    """True if two chunks are >80% word overlap (catches Whisper re-emitting same segment)"""
    a_words = set(a.lower().split())
    b_words = set(b.lower().split())
    if not a_words or not b_words or min(len(a_words), len(b_words)) < 4:
        return False
    overlap = len(a_words & b_words) / min(len(a_words), len(b_words))
    return overlap > 0.8


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


# Available models with display info.
# "repo" is the exact Hugging Face repo used by MLX Whisper. Do not derive it
# from the key: e.g. mlx-community/whisper-small does not exist (HTTP 401).
AVAILABLE_MODELS: Dict[str, Dict[str, str]] = {
    "large-v3-turbo": {
        "repo": "mlx-community/whisper-large-v3-turbo",
        "display": "large-v3-turbo — 1.5 GB, nejlepší přesnost",
        "size": "1.5 GB",
        "speed": "~2s",
        "note": "Doporučeno",
    },
    "large-v3-turbo-q4": {
        "repo": "mlx-community/whisper-large-v3-turbo-q4",
        "display": "large-v3-turbo-q4 — 380 MB, rychlý",
        "size": "380 MB",
        "speed": "~1.5s",
        "note": "4-bit kvantizace, skoro stejná přesnost",
    },
    "medium": {
        "repo": "mlx-community/whisper-medium-mlx-4bit",
        "display": "medium — 500 MB, vyvážený",
        "size": "500 MB",
        "speed": "~1s",
        "note": "Rychlejší, mírně nižší přesnost",
    },
    "small": {
        "repo": "mlx-community/whisper-small-mlx-q4",
        "display": "small — 150 MB, nejrychlejší",
        "size": "150 MB",
        "speed": "<1s",
        "note": "Vhodné pro krátké vstupy",
    },
}


def _get_whisper_model(model_size: str = "large-v3-turbo", device: str = "cpu", compute_type: str = "int8"):
    """Lazy-load whisper model (MLX preferred, faster-whisper fallback).
    Returns cached model unless set_model_size() reset it to None.
    Thread-safe: uses _model_load_lock to prevent duplicate loads.
    """
    global _whisper_model
    with _model_load_lock:
        if _whisper_model is None:
            if _USE_MLX:
                print(f"Using MLX Whisper: {model_size} (Apple Silicon GPU)...", flush=True)
                repo = AVAILABLE_MODELS.get(model_size, {}).get(
                    "repo", f"mlx-community/whisper-{model_size}"
                )
                _whisper_model = ("mlx", repo)
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
        self._transcripts: Dict[int, str] = {}   # Keyed by chunk index for ordered assembly
        self._chunk_counter = 0
        self._lock = threading.Lock()
        self._processing_count = 0

        # Device selection
        self._selected_device_name: Optional[str] = None

    def set_language(self, lang_code: str):
        """Set transcription language"""
        if lang_code in SUPPORTED_LANGUAGES:
            self.language = lang_code

    def set_model_size(self, model_size: str):
        """Switch to a different Whisper model. Waits for in-flight transcriptions to finish."""
        global _whisper_model
        if model_size == self.model_size:
            return
        self.model_size = model_size
        # Wait for any running transcription threads before swapping the model
        timeout = time.time() + 10
        while self._processing_count > 0 and time.time() < timeout:
            time.sleep(0.05)
        with _model_load_lock:
            _whisper_model = None   # Force reload on next transcription
        print(f"Model switched to: {model_size} (will load on next recording)", flush=True)

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
        model_info = AVAILABLE_MODELS.get(self.model_size, {})
        size = model_info.get("size", "?")
        return f"{self.model_size} ({backend}, {size})"

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
        """Find device index for selected device.

        Resolution order:
        1. Exact match on configured device name
        2. Case-insensitive substring match (survives renamed BT devices)
        3. macOS default input device
        4. First device with input channels
        """
        audio = pyaudio.PyAudio()
        try:
            if self._selected_device_name:
                target = self._selected_device_name
                target_lower = target.lower()

                # Exact match
                for i in range(audio.get_device_count()):
                    info = audio.get_device_info_by_index(i)
                    if info['maxInputChannels'] > 0 and info['name'] == target:
                        return i

                # Fuzzy match (case-insensitive substring, either direction)
                for i in range(audio.get_device_count()):
                    info = audio.get_device_info_by_index(i)
                    if info['maxInputChannels'] <= 0:
                        continue
                    name_lower = info['name'].lower()
                    if target_lower in name_lower or name_lower in target_lower:
                        print(
                            f"Device '{target}' not found exactly, "
                            f"using close match: '{info['name']}'",
                            flush=True,
                        )
                        return i

                print(
                    f"Warning: Device '{target}' not found, "
                    "falling back to system default input",
                    flush=True,
                )

            # Fallback to macOS system default input device
            try:
                default_info = audio.get_default_input_device_info()
                if default_info.get('maxInputChannels', 0) > 0:
                    print(
                        f"Using default input device: '{default_info['name']}' "
                        f"(index {default_info['index']})",
                        flush=True,
                    )
                    return int(default_info['index'])
            except Exception:
                pass

            # Last resort: first device with input channels
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
        self._transcripts = {}
        self._chunk_counter = 0
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

        # Assemble chunks in order
        with self._lock:
            full_text = " ".join(self._transcripts[k] for k in sorted(self._transcripts) if self._transcripts[k].strip())

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
            self._audio.terminate()
            self._audio = None
            self._recording = False
            return

        try:
            device_info = self._audio.get_device_info_by_index(device_index)
            print(
                f"Using device: {device_info['name']} (index {device_index})",
                flush=True,
            )
        except Exception:
            pass

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

        # Silent-input detection (catches macOS mic permission denial —
        # PyAudio opens the stream but delivers all-zero buffers)
        frames_seen = 0
        silent_frames = 0
        silence_check_frames = int(2.0 * self.sample_rate / self.chunk_size)  # ~2s at 16kHz
        silence_alerted = False

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

                # Silent-input detection: count frames that are literally all zero
                frames_seen += 1
                if not audio_int16.any():
                    silent_frames += 1
                if (not silence_alerted
                        and frames_seen >= silence_check_frames
                        and silent_frames >= silence_check_frames * 0.95):
                    silence_alerted = True
                    print(
                        "⚠️  Microphone is delivering silence (all-zero samples).\n"
                        "   Most likely cause: macOS Microphone permission is DENIED\n"
                        "   for the app that launched Jarvis (Terminal / iTerm / opencode).\n"
                        "   Fix: System Settings → Privacy & Security → Microphone → enable it.",
                        flush=True,
                    )

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
            # Process any remaining speech — always, even if shorter than min_speech_frames
            # (avoids dropping the last word when user stops quickly)
            if speech_buffer:
                chunk_audio = np.concatenate(speech_buffer)
                if len(chunk_audio) >= min_speech_frames:
                    self._transcribe_chunk(chunk_audio)
                else:
                    print(f"  [final chunk too short, skipped] {len(chunk_audio)} frames", flush=True)

            # Cleanup audio
            if self._stream:
                self._stream.stop_stream()
                self._stream.close()
            if self._audio:
                self._audio.terminate()
                self._audio = None

    def _transcribe_chunk(self, audio_data: np.ndarray):
        """Transcribe a chunk of audio in background thread"""
        with self._lock:
            idx = self._chunk_counter
            self._chunk_counter += 1
            self._processing_count += 1   # Under lock: atomic with counter
        try:
            threading.Thread(
                target=self._do_transcribe,
                args=(audio_data, idx),
                daemon=True
            ).start()
        except Exception:
            with self._lock:
                self._processing_count -= 1   # Thread never started, undo increment
            raise

    def _do_transcribe(self, audio_data: np.ndarray, chunk_idx: int):
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
                        # Cross-chunk near-duplicate detection
                        if self._transcripts:
                            last_key = max(self._transcripts.keys())
                            last_text = self._transcripts[last_key]
                            if _is_near_duplicate(chunk_text, last_text):
                                print(f"  [near-duplicate filtered] {chunk_text}", flush=True)
                                return
                        self._transcripts[chunk_idx] = chunk_text

                    if self.on_partial:
                        self.on_partial(chunk_text)

                    print(f"  [chunk {chunk_idx}] {chunk_text}", flush=True)
            elif chunk_text:
                print(f"  [filtered hallucination] {chunk_text}", flush=True)

        except Exception as e:
            print(f"Transcription error: {e}", flush=True)
        finally:
            with self._lock:
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
