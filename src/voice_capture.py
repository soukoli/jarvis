#!/usr/bin/env python3
"""
Simple voice capture - just record and save
"""
import os
import time
import threading
from typing import Optional, List
import pyaudio
import wave


class VoiceCapture:
    """Records audio from microphone"""

    def __init__(self, cache_dir: str = ".voice_cache"):
        self.cache_dir = cache_dir
        self.recording = False
        self.frames: List[bytes] = []
        self.audio = pyaudio.PyAudio()
        self.stream: Optional[pyaudio.Stream] = None
        self.thread: Optional[threading.Thread] = None

        os.makedirs(cache_dir, exist_ok=True)
        self._cleanup(keep=5)

        # Audio config
        self.CHUNK = 1024
        self.FORMAT = pyaudio.paInt16
        self.CHANNELS = 1
        self.RATE = 16000

    def _cleanup(self, keep: int = 5):
        """Keep only recent recordings"""
        try:
            files = [
                os.path.join(self.cache_dir, f)
                for f in os.listdir(self.cache_dir)
                if f.endswith('.wav')
            ]
            files.sort(key=os.path.getmtime, reverse=True)
            for f in files[keep:]:
                try:
                    os.remove(f)
                except:
                    pass
        except:
            pass

    def start_recording(self):
        """Start capturing audio"""
        if self.recording:
            print("Already recording", flush=True)
            return

        self.recording = True
        self.frames = []

        self.stream = self.audio.open(
            format=self.FORMAT,
            channels=self.CHANNELS,
            rate=self.RATE,
            input=True,
            frames_per_buffer=self.CHUNK
        )

        def record():
            while self.recording:
                try:
                    data = self.stream.read(self.CHUNK, exception_on_overflow=False)
                    self.frames.append(data)
                except:
                    break

        self.thread = threading.Thread(target=record, daemon=True)
        self.thread.start()

    def stop_recording(self) -> Optional[str]:
        """Stop and save audio file"""
        if not self.recording:
            print("Not recording")
            return None

        self.recording = False
        if self.thread:
            self.thread.join(timeout=1)

        if self.stream:
            self.stream.stop_stream()
            self.stream.close()

        if not self.frames:
            return None

        # Save
        filename = os.path.join(self.cache_dir, f"voice_{int(time.time() * 1000)}.wav")
        with wave.open(filename, 'wb') as wf:
            wf.setnchannels(self.CHANNELS)
            wf.setsampwidth(self.audio.get_sample_size(self.FORMAT))
            wf.setframerate(self.RATE)
            wf.writeframes(b''.join(self.frames))

        return filename

    def cleanup(self):
        """Release resources"""
        if self.stream:
            self.stream.close()
        self.audio.terminate()
