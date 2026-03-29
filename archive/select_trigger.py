#!/usr/bin/env python3
"""
Interactive trigger key selector
"""
from pynput import keyboard

def main():
    print("=" * 60)
    print("🎮 Jarvis Trigger Key Options")
    print("=" * 60)
    print()
    print("Choose your preferred trigger key:")
    print()
    print("1. ` (Backtick) - RECOMMENDED")
    print("   • Top-left of keyboard")
    print("   • Rarely used in coding")
    print("   • Won't interfere with typing")
    print()
    print("2. Ctrl+R")
    print("   • Two-key combo")
    print("   • Won't type anything")
    print("   • May conflict with browser refresh")
    print()
    print("3. Ctrl+Space")
    print("   • Two-key combo")
    print("   • Common and easy to reach")
    print("   • May conflict with IDE autocomplete")
    print()
    print("4. F13 (if you have extended keyboard)")
    print("   • Dedicated key, no conflicts")
    print("   • Requires extended keyboard")
    print()
    print("5. Scroll Lock")
    print("   • Rarely used")
    print("   • Available on most keyboards")
    print()
    print("6. Pause/Break")
    print("   • Rarely used")
    print("   • Available on most keyboards")
    print()
    print("-" * 60)
    print()

    choice = input("Enter choice (1-6) [1]: ").strip() or "1"

    triggers = {
        "1": ("backtick", "` (backtick)"),
        "2": ("ctrl+r", "Ctrl+R"),
        "3": ("ctrl+space", "Ctrl+Space"),
        "4": ("f13", "F13"),
        "5": ("scroll_lock", "Scroll Lock"),
        "6": ("pause", "Pause/Break"),
    }

    if choice not in triggers:
        print("Invalid choice, using backtick")
        choice = "1"

    key_name, display = triggers[choice]

    print()
    print("=" * 60)
    print(f"✅ Selected: {display}")
    print("=" * 60)
    print()
    print("To use this trigger:")
    print()
    print(f"  ./jarvis.sh --trigger {key_name}")
    print()
    print("Or set as default in config.env:")
    print()
    print(f"  TRIGGER_KEY={key_name}")
    print()
    print("Test it now?")
    print()

    test = input("Press Enter to test, or 'n' to skip: ").strip()

    if test.lower() != 'n':
        print()
        print("=" * 60)
        print("🧪 Test Mode - Press ESC to quit")
        print("=" * 60)
        print(f"Hold {display} and see if it works...")
        print()

        pressed = False

        def on_press(key):
            nonlocal pressed
            if not pressed:
                pressed = True
                print(f"✅ Key detected: {key}")

        def on_release(key):
            if key == keyboard.Key.esc:
                print("\n✅ Test complete!")
                return False

        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            listener.join()

    print()
    print("Ready to launch Jarvis with your preferred trigger key!")
    print()


if __name__ == "__main__":
    main()
