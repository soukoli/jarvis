#!/usr/bin/env python3
"""
Session integration - Sends voice commands to the CURRENT Claude session
"""
import os
import sys
import time

class SessionIntegration:
    """
    Integrates with the current Claude Code session by writing
    prompts that can be picked up by the running session
    """
    def __init__(self, session_file=".jarvis_prompt.txt"):
        self.session_file = session_file

    def send_to_session(self, prompt):
        """
        Write prompt to a file for the current session to pick up

        Args:
            prompt: The text prompt to send to Claude

        Returns:
            True (always, since we're just writing to file)
        """
        print(f"\n📝 Transcribed: {prompt}")
        print()
        print("=" * 60)
        print("🤖 SEND THIS TO CLAUDE:")
        print("=" * 60)
        print()
        print(f"   {prompt}")
        print()
        print("=" * 60)
        print()
        print("💡 Copy/paste the above into your Claude chat, or:")
        print(f"   1. Jarvis saved it to: {self.session_file}")
        print(f"   2. In Claude, type: $(cat {self.session_file})")
        print()

        # Write to file for easy access
        with open(self.session_file, 'w') as f:
            f.write(prompt)

        return True

    def execute(self, prompt):
        """Alias for send_to_session for compatibility"""
        return self.send_to_session(prompt)

    def is_available(self):
        """Always available"""
        return True


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        integration = SessionIntegration()
        integration.send_to_session(" ".join(sys.argv[1:]))
