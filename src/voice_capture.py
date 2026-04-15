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
        self.audio = None
        self.stream: Optional[pyaudio.Stream] = None
        self.thread: Optional[threading.Thread] = None
        self.selected_device_name: Optional[str] = None

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

    def get_input_devices(self) -> List[dict]:
        """Get list of available input devices"""
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

    def set_device(self, device_name: str):
        """Set the microphone device to use by name"""
        self.selected_device_name = device_name

    def _find_device_index_by_name(self, device_name: str) -> Optional[int]:
        """Find device index by device name"""
        audio = pyaudio.PyAudio()
        try:
            for i in range(audio.get_device_count()):
                info = audio.get_device_info_by_index(i)
                if info['maxInputChannels'] > 0 and info['name'] == device_name:
                    return i
        finally:
            audio.terminate()
        return None

    def _find_valid_input_device(self) -> Optional[int]:
        """Find valid input device - prefer selected device by name, fallback to first available"""
        audio = pyaudio.PyAudio()
        try:
            # If a device name is selected, try to find it by name
            if self.selected_device_name:
                for i in range(audio.get_device_count()):
                    info = audio.get_device_info_by_index(i)
                    if info['maxInputChannels'] > 0 and info['name'] == self.selected_device_name:
                        return i
                # If selected device not found, print warning
                print(f"Warning: Selected device '{self.selected_device_name}' not found, using default")

            # Fallback: find first available input device
            for i in range(audio.get_device_count()):
                info = audio.get_device_info_by_index(i)
                if info['maxInputChannels'] > 0:
                    return i
        finally:
            audio.terminate()
        return None

    def start_recording(self):
        """Start capturing audio"""
        if self.recording:
            print("Already recording", flush=True)
            return

        self.recording = True
        self.frames = []

        # Fresh PyAudio instance each time
        if self.audio:
            try:
                self.audio.terminate()
            except:
                pass

        self.audio = pyaudio.PyAudio()

        # Find valid input device
        device_index = self._find_valid_input_device()
        if device_index is None:
            print("No valid input device found", flush=True)
            self.recording = False
            return

        # Get device info to validate capabilities
        try:
            device_info = self.audio.get_device_info_by_index(device_index)
            print(f"Using device: {device_info['name']} (index {device_index})", flush=True)

            # Adjust channels if device doesn't support mono
            channels = self.CHANNELS
            if device_info['maxInputChannels'] < channels:
                channels = device_info['maxInputChannels']
                print(f"Adjusting channels from {self.CHANNELS} to {channels}", flush=True)

            self.stream = self.audio.open(
                format=self.FORMAT,
                channels=channels,
                rate=self.RATE,
                input=True,
                input_device_index=device_index,
                frames_per_buffer=self.CHUNK
            )
        except Exception as e:
            print(f"Failed to open audio stream: {e}", flush=True)
            if self.selected_device_name:
                print(f"Try selecting a different microphone. Current: {self.selected_device_name}", flush=True)
            self.audio.terminate()
            self.audio = None
            self.recording = False
            return

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

        if self.audio:
            self.audio.terminate()
            self.audio = None

        if not self.frames:
            return None

        # Save
        audio_temp = pyaudio.PyAudio()
        filename = os.path.join(self.cache_dir, f"voice_{int(time.time() * 1000)}.wav")
        with wave.open(filename, 'wb') as wf:
            wf.setnchannels(self.CHANNELS)
            wf.setsampwidth(audio_temp.get_sample_size(self.FORMAT))
            wf.setframerate(self.RATE)
            wf.writeframes(b''.join(self.frames))
        audio_temp.terminate()

        return filename

    def cleanup(self):
        """Release resources"""
        if self.stream:
            try:
                self.stream.close()
            except:
                pass
        if self.audio:
            try:
                self.audio.terminate()
            except:
                pass
