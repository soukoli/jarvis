#!/usr/bin/env python3
"""
Claude Code CLI integration - executes commands via claude CLI
"""
import subprocess
import os
import shutil

class ClaudeExecutor:
    def __init__(self, working_dir=None):
        self.working_dir = working_dir or os.getcwd()

        # Find claude CLI (try multiple names)
        self.claude_cmd = None
        for cmd in ["claude", "claude-code"]:
            if shutil.which(cmd):
                self.claude_cmd = cmd
                break

    def is_available(self):
        """Check if Claude CLI is available"""
        return self.claude_cmd is not None

    def execute(self, prompt):
        """
        Execute a prompt via Claude Code CLI

        Args:
            prompt: The text prompt to send to Claude

        Returns:
            True if successful, False otherwise
        """
        if not self.is_available():
            print("❌ Claude CLI not found in PATH")
            print("   Searched for: claude, claude-code")
            print("   Make sure Claude Code CLI is installed")
            return False

        try:
            print(f"\n🤖 Executing: {prompt}\n")
            print("-" * 50)

            # Execute claude with the prompt
            result = subprocess.run(
                [self.claude_cmd, prompt],
                cwd=self.working_dir,
                capture_output=False,  # Show output in real-time
                text=True
            )

            print("-" * 50)
            return result.returncode == 0

        except Exception as e:
            print(f"❌ Error executing Claude: {e}")
            return False

    def execute_direct(self, prompt):
        """
        Execute and return output (for testing)
        """
        if not self.is_available():
            return "Error: Claude CLI not found"

        try:
            result = subprocess.run(
                [self.claude_cmd, prompt],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
                timeout=300  # 5 min timeout
            )
            return result.stdout
        except Exception as e:
            return f"Error: {e}"


if __name__ == "__main__":
    # Test Claude integration
    import sys
    if len(sys.argv) > 1:
        executor = ClaudeExecutor()
        if executor.is_available():
            print(f"✅ Found: {executor.claude_cmd}")
            executor.execute(" ".join(sys.argv[1:]))
        else:
            print("❌ Claude CLI not available")

