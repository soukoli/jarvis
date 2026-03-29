#!/usr/bin/env python3
"""
Debug mode - Shows all keyboard events to help troubleshoot
"""
from pynput import keyboard

print("=" * 60)
print("🔍 Jarvis Keyboard Debug Mode")
print("=" * 60)
print()
print("Press Cmd+; and watch what gets detected")
print("Press ESC to quit")
print()
print("-" * 60)

cmd_pressed = False

def on_press(key):
    global cmd_pressed

    if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
        cmd_pressed = True
        print(f"✓ Cmd pressed (cmd_pressed = {cmd_pressed})")
        return

    try:
        if hasattr(key, 'char'):
            char = key.char
            print(f"Key pressed: '{char}' | Cmd: {cmd_pressed}")

            if cmd_pressed and char == ';':
                print("🎯 COMBO DETECTED: Cmd+;")
        else:
            print(f"Special key: {key}")
    except:
        print(f"Key: {key}")

def on_release(key):
    global cmd_pressed

    if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
        cmd_pressed = False
        print(f"✓ Cmd released (cmd_pressed = {cmd_pressed})")
        return

    if key == keyboard.Key.esc:
        print("\n✅ Debug complete")
        return False

with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
    listener.join()
