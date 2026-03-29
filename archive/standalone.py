#!/usr/bin/env python3
"""
Standalone mode - Voice-to-text only (no Claude execution)
Useful for testing the STT pipeline
"""
import sys
import os
from voice_capture import HoldToTalk
from speech_to_text import WhisperSTT

def main():
    print("=" * 50)
    print("🎤 Jarvis - Voice-to-Text Test Mode")
    print("=" * 50)
    print("Testing speech recognition only")
    print("(Claude integration disabled)")
    print("Recordings cached in .voice_cache/")
    print()

    # Use backtick by default (better than space)
    trigger_key = "`"
    if len(sys.argv) > 1 and sys.argv[1] == "--ctrl":
        trigger_key = ("<ctrl>", "r")

    stt = WhisperSTT()

    def process_audio(audio_file):
        """Process audio and show transcription"""
        text = stt.transcribe(audio_file)

        if text:
            print(f"\n✨ Transcribed: \"{text}\"\n")
            print(f"💾 Cached: {audio_file}\n")
        else:
            print("\n⚠️  No speech detected\n")
            # Delete failed recordings
            try:
                os.remove(audio_file)
            except:
                pass

    hold_to_talk = HoldToTalk(trigger_key=trigger_key)
    hold_to_talk.start(process_audio)


if __name__ == "__main__":
    main()
