#!/usr/bin/env python3
"""
Jarvis diagnostics — one-shot health check for microphone input.

Run this when Jarvis says "No transcription result" but you spoke clearly.
Reports:
  1. macOS microphone permission status (AVFoundation)
  2. PyAudio-visible input devices
  3. macOS system default input
  4. Currently configured device (from ~/.jarvis_config.json)
  5. 3-second RMS test on the configured device
  6. 3-second RMS test on the system default (if different)

RMS interpretation:
  0.000        → SILENT — permission denied, or dead driver
  < 0.001      → basically silent
  < 0.01       → very quiet (whisper level)
  > 0.01       → normal speech
"""
import json
import os
import sys
import time

import numpy as np
import pyaudio


CONFIG_PATH = os.path.expanduser("~/.jarvis_config.json")
RATE = 16000
CHUNK = 512
TEST_DURATION = 3.0


def check_permission() -> str:
    try:
        from AVFoundation import AVCaptureDevice, AVMediaTypeAudio
        status = AVCaptureDevice.authorizationStatusForMediaType_(AVMediaTypeAudio)
        return {
            0: 'not_determined',
            1: 'restricted',
            2: 'denied',
            3: 'authorized',
        }.get(int(status), 'unknown')
    except Exception as e:
        return f'unknown ({e.__class__.__name__})'


def list_devices():
    audio = pyaudio.PyAudio()
    devices = []
    default_idx = None
    try:
        try:
            default_info = audio.get_default_input_device_info()
            default_idx = int(default_info['index'])
        except Exception:
            pass
        for i in range(audio.get_device_count()):
            info = audio.get_device_info_by_index(i)
            if info['maxInputChannels'] > 0:
                devices.append({
                    'index': i,
                    'name': info['name'],
                    'channels': info['maxInputChannels'],
                    'rate': info['defaultSampleRate'],
                    'is_default': i == default_idx,
                })
    finally:
        audio.terminate()
    return devices, default_idx


def rms_test(device_index: int, device_name: str) -> dict:
    audio = pyaudio.PyAudio()
    result = {'device_index': device_index, 'device_name': device_name}
    stream = None
    try:
        stream = audio.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=RATE,
            input=True,
            input_device_index=device_index,
            frames_per_buffer=CHUNK,
        )
        frames = []
        start = time.time()
        while time.time() - start < TEST_DURATION:
            data = stream.read(CHUNK, exception_on_overflow=False)
            frames.append(data)
        samples = np.frombuffer(b''.join(frames), dtype=np.int16).astype(np.float32) / 32768.0
        result['samples'] = int(len(samples))
        result['rms'] = float(np.sqrt(np.mean(samples ** 2))) if len(samples) else 0.0
        result['peak'] = float(np.max(np.abs(samples))) if len(samples) else 0.0
        result['all_zero'] = bool(not np.any(samples))
    except Exception as e:
        result['error'] = f'{e.__class__.__name__}: {e}'
    finally:
        if stream is not None:
            try:
                stream.stop_stream()
                stream.close()
            except Exception:
                pass
        audio.terminate()
    return result


def verdict(res: dict) -> str:
    if 'error' in res:
        return f"❌ ERROR: {res['error']}"
    if res.get('all_zero'):
        return "❌ SILENT — all-zero buffers (likely permission denied)"
    rms = res.get('rms', 0.0)
    if rms < 0.001:
        return f"⚠️  Effectively silent (RMS {rms:.5f})"
    if rms < 0.01:
        return f"⚠️  Very quiet (RMS {rms:.5f}) — try speaking louder"
    return f"✅ Audio flowing (RMS {rms:.5f}, peak {res['peak']:.5f})"


def main():
    print("=" * 60)
    print("Jarvis microphone diagnostics")
    print("=" * 60)

    # 1. Permission
    print("\n[1] macOS microphone permission status:")
    perm = check_permission()
    print(f"    {perm}")
    if perm == 'denied':
        print(
            "    ↳ Fix: System Settings → Privacy & Security → Microphone\n"
            "      Enable the app that runs Jarvis (Terminal / iTerm / opencode)"
        )

    # 2. Devices
    print("\n[2] PyAudio input devices:")
    devices, default_idx = list_devices()
    for d in devices:
        marker = " ← macOS default" if d['is_default'] else ""
        print(f"    [{d['index']}] {d['name']}  ({d['channels']}ch, {d['rate']:.0f} Hz){marker}")

    # 3. Config
    print("\n[3] Jarvis config:")
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            cfg = json.load(f)
        configured_name = cfg.get('device_name')
        print(f"    device_name = {configured_name!r}")
        print(f"    language    = {cfg.get('language')!r}")
        print(f"    model_size  = {cfg.get('model_size')!r}")
    else:
        configured_name = None
        print(f"    (no config at {CONFIG_PATH})")

    # 4. Match configured device
    configured_idx = None
    if configured_name:
        for d in devices:
            if d['name'] == configured_name:
                configured_idx = d['index']
                break
        if configured_idx is None:
            print(f"    ⚠️  Configured device {configured_name!r} is NOT in the current device list.")

    # 5. RMS tests
    tested = set()
    if configured_idx is not None:
        print(f"\n[4] RMS test on configured device (idx {configured_idx}):")
        res = rms_test(configured_idx, configured_name)
        print(f"    {verdict(res)}")
        tested.add(configured_idx)

    if default_idx is not None and default_idx not in tested:
        default_name = next((d['name'] for d in devices if d['index'] == default_idx), '?')
        print(f"\n[5] RMS test on system default (idx {default_idx}, {default_name!r}):")
        res = rms_test(default_idx, default_name)
        print(f"    {verdict(res)}")

    print("\n" + "=" * 60)


if __name__ == '__main__':
    main()
