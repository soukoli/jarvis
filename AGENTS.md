# Jarvis — agent guide

Local voice-to-text menu bar app for macOS (Apple Silicon). Record with a global
hotkey, transcribe on-device with MLX Whisper, copy the text to the clipboard.
Single-user hobby project; keep changes small and keep the app runnable.

## Layout

| Path | Role |
|---|---|
| `jarvis.py` | Entry point. `JarvisApp(rumps.App)`: menu bar UI, global hotkeys (pynput), state machine (ready → recording → processing), macOS permission checks, config persistence. |
| `src/streaming_stt.py` | Main STT engine. PyAudio → Silero VAD → speech chunks → MLX Whisper (GPU) or faster-whisper (CPU fallback). Hallucination filter, near-duplicate filter, ordered chunk assembly, model switcher. |
| `src/voice_capture.py` | Batch recorder (record to WAV). Used only when Streaming Mode is off. |
| `src/speech_to_text.py` | Batch transcriber via whisper.cpp CLI. Only works if `whisper.cpp/` is built locally with a real `ggml-*.bin` model. **setup.sh does not install it** — see Known gaps. |
| `diagnose.py` | Standalone mic health check: permission status, devices, 3s RMS test. |
| `setup.sh` | Installer: portaudio, `pip install -r requirements.txt`, model download, import check. |
| `run.sh` | Launcher; prefers the mise Python. |
| `requirements.txt` | Pinned, smoke-tested versions. Source of truth for deps. |

User config lives in `~/.jarvis_config.json` (language, model, device, hotkeys, toggles).
Whisper models are cached by Hugging Face Hub in `~/.cache/huggingface/hub`.

## Runtime facts you must respect

- **torch and torchaudio stay at 2.11.0.** torchaudio's latest release is 2.11.0 and
  silero-vad requires it. Bumping torch alone breaks VAD. Check
  `pip index versions torchaudio` before touching torch.
- **MLX model ids are explicit** in `AVAILABLE_MODELS[...]["repo"]`. Do not derive
  `mlx-community/whisper-<key>` from the key: `mlx-community/whisper-small` does not
  exist. Verify a new repo with `curl -sI https://huggingface.co/api/models/<repo>`.
- Python is the shared global mise 3.13 env, not a venv. Other tools (esphome,
  platformio) live there too; avoid unrelated upgrades.
- rumps notifications need `Info.plist` (with `CFBundleIdentifier`) next to the
  interpreter. `run.sh` creates it on first start; `_notify()` in `jarvis.py` keeps
  the app alive if it is still missing.
- `whisper.cpp/`, `.voice_cache/`, `__pycache__/`, `.claude/settings.local.json` are
  git-ignored. Never commit them.
- `origin` has two push URLs (github.com/soukoli/jarvis and github.tools.sap). One
  `git push` lands on both. Work on a feature branch and merge via PR on github.com.

## Verify before you claim it works

The app is a GUI process with global hotkeys; you cannot drive it headlessly. Minimum:

```bash
python3 -m py_compile jarvis.py src/*.py diagnose.py
python3 -c "
import sys; sys.path.insert(0,'src')
import mlx_whisper, silero_vad, pyaudio, pynput, rumps, numpy, torch, torchaudio, faster_whisper
from AVFoundation import AVCaptureDevice
from ApplicationServices import AXIsProcessTrusted
import speech_to_text, streaming_stt, voice_capture
silero_vad.load_silero_vad(); print('OK')"
python3 diagnose.py          # optional, needs a mic; 6s
```

After changing deps: regenerate `requirements.txt` from `pip show`, rerun the block above,
and say in the commit which packages moved.

## Conventions

- Threading: `JarvisApp._state_lock` guards `recording`/`processing`;
  `StreamingSTT._lock` guards `_transcripts`, `_chunk_counter`, `_processing_count`;
  `_model_load_lock` guards the global model cache. Keep increments and decrements of
  a counter under the same lock.
- All console output uses `print(..., flush=True)`; there is no logging module.
- UI strings are English except the model submenu and model-switch notification,
  which are Czech (legacy; harmonize only if asked).
- Hallucination regexes in `_HALLUCINATION_PATTERNS` are Czech/English YouTube-style
  artifacts. Add patterns, don't loosen the structural checks.
- Don't add features to the batch (whisper.cpp) path; it is a fallback slated for
  replacement by `StreamingSTT.transcribe(audio_file)`.

## Known gaps (as of 2026-09-23)

Ordered by user impact. Fix only when asked; keep this list current.

1. **Batch mode is non-functional out of the box.** Streaming Mode off → `WhisperSTT`
   needs `whisper.cpp/build/bin/whisper-cli` + `whisper.cpp/models/ggml-*.bin`; neither
   is installed by setup.sh. Suggested fix: in `_process_audio`, fall back to
   `self.streaming_stt.transcribe(audio_file)` when the binary or model is missing.
2. **Cancel during processing doesn't cancel.** `cancel_operation` flips state, but the
   worker thread in `_process_streaming_result` / `_process_audio` still copies text
   to the clipboard and plays the sound. Needs a generation counter or cancel flag
   checked before `_copy_to_clipboard`.
3. **Permission naming mismatch.** App checks Accessibility (`AXIsProcessTrusted`);
   pynput on recent macOS also needs Input Monitoring. README documents both.
4. **faster-whisper fallback (Intel/CPU)** receives `model_size` keys like
   `large-v3-turbo-q4`, which are not valid faster-whisper model names. Only
   `large-v3-turbo`/`medium`/`small` work there.
5. **Hotkey debounce** returns before Cmd tracking, so a Cmd press within 0.5s of a
   hotkey is missed. Minor.
6. `_announce_language` sleeps 0.3s on the UI thread; batch `voice.stop_recording()`
   joins up to 1s on the UI thread. Minor stalls.
7. `VoiceCapture.stop_recording` writes the WAV header with `self.CHANNELS` even when
   the stream was opened with fewer channels. Edge case.
8. README claims MIT but there is no `LICENSE` file.
