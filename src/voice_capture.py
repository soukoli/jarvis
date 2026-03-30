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

        # Find and log available input devices
        self._log_audio_devices()

    def _log_audio_devices(self):
        """Log all available audio input devices"""
        try:
            print("🎤 Available microphones:", flush=True)
            default_input_idx = self.audio.get_default_input_device_info()['index']

            for i in range(self.audio.get_device_count()):
                info = self.audio.get_device_info_by_index(i)
                if info['maxInputChannels'] > 0:
                    is_default = " (DEFAULT)" if i == default_input_idx else ""
                    print(f"  [{i}] {info['name']}{is_default}", flush=True)
        except Exception as e:
            print(f"⚠️  Could not list devices: {e}", flush=True)

    def _get_best_input_device(self) -> Optional[int]:
        """Find the best microphone - prefer built-in over AirPods/Bluetooth"""
        try:
            # Preference order: Built-in MacBook mic > USB > Others > AirPods
            built_in = None
            usb = None
            default = self.audio.get_default_input_device_info()['index']

            for i in range(self.audio.get_device_count()):
                info = self.audio.get_device_info_by_index(i)
                if info['maxInputChannels'] > 0:
                    name = info['name'].lower()
                    if 'macbook' in name and 'microphone' in name:
                        return i  # Best option
                    elif 'usb' in name or 'dell' in name or 'logitech' in name:
                        usb = i
                    elif built_in is None and 'airpods' not in name and 'iphone' not in name:
                        built_in = i

            # Return preference order
            return built_in or usb or default
        except:
            return None

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
            print("⚠️  Already recording", flush=True)
            return

        self.recording = True
        self.frames = []

        # Get best input device
        device_index = self._get_best_input_device()
        device_name = "default"
        if device_index is not None:
            try:
                device_name = self.audio.get_device_info_by_index(device_index)['name']
                print(f"🎤 Recording from: {device_name}", flush=True)
            except:
                pass

        self.stream = self.audio.open(
            format=self.FORMAT,
            channels=self.CHANNELS,
            rate=self.RATE,
            input=True,
            input_device_index=device_index,
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
            print("⚠️  Not recording")
            return None

        self.recording = False
        if self.thread:
            self.thread.join(timeout=1)

        if self.stream:
            self.stream.stop_stream()
            self.stream.close()

        if not self.frames:
            return None

        # Check if audio has actual signal (not just silence)
        import array
        audio_data = b''.join(self.frames)
        samples = array.array('h', audio_data)
        max_amplitude = max(abs(s) for s in samples) if samples else 0
        print(f"🔊 Max amplitude: {max_amplitude} (silence if <100)", flush=True)

        # Save
        filename = os.path.join(self.cache_dir, f"voice_{int(time.time() * 1000)}.wav")
        with wave.open(filename, 'wb') as wf:
            wf.setnchannels(self.CHANNELS)
            wf.setsampwidth(self.audio.get_sample_size(self.FORMAT))
            wf.setframerate(self.RATE)
            wf.writeframes(b''.join(self.frames))

        size_kb = os.path.getsize(filename) / 1024
        print(f"💾 Saved ({size_kb:.1f}KB)", flush=True)
        return filename

    def cleanup(self):
        """Release resources"""
        if self.stream:
            self.stream.close()
        self.audio.terminate()
