#!/usr/bin/env python3
"""
Cache management utility for Jarvis
"""
import os
import sys
from datetime import datetime

CACHE_DIR = ".voice_cache"

def get_cache_stats():
    """Get cache statistics"""
    if not os.path.exists(CACHE_DIR):
        return 0, 0, []

    files = [
        f for f in os.listdir(CACHE_DIR)
        if f.endswith('.wav')
    ]

    file_info = []
    total_size = 0

    for f in files:
        path = os.path.join(CACHE_DIR, f)
        size = os.path.getsize(path)
        mtime = os.path.getmtime(path)
        total_size += size
        file_info.append((f, size, mtime))

    # Sort by time (newest first)
    file_info.sort(key=lambda x: x[2], reverse=True)

    return len(files), total_size, file_info


def show_cache():
    """Display cache contents"""
    count, total_size, files = get_cache_stats()

    print("=" * 60)
    print("🗂️  Jarvis Voice Cache")
    print("=" * 60)

    if count == 0:
        print("\n📭 Cache is empty\n")
        return

    print(f"\n📊 Total: {count} files, {total_size / 1024:.1f}KB\n")
    print(f"{'Filename':<25} {'Size':<12} {'Age':<15}")
    print("-" * 60)

    for filename, size, mtime in files:
        age_seconds = time.time() - mtime
        if age_seconds < 60:
            age_str = f"{int(age_seconds)}s ago"
        elif age_seconds < 3600:
            age_str = f"{int(age_seconds / 60)}m ago"
        else:
            age_str = f"{int(age_seconds / 3600)}h ago"

        print(f"{filename:<25} {size / 1024:>8.1f}KB   {age_str:<15}")

    print()


def clean_cache(keep_last=5):
    """Clean cache, keeping only recent recordings"""
    count, total_size, files = get_cache_stats()

    if count == 0:
        print("📭 Cache already empty")
        return

    to_delete = files[keep_last:]

    if not to_delete:
        print(f"✅ Cache is clean (only {count} files, keeping {keep_last})")
        return

    print(f"🧹 Removing {len(to_delete)} old recordings...")

    deleted_size = 0
    for filename, size, _ in to_delete:
        path = os.path.join(CACHE_DIR, filename)
        try:
            os.remove(path)
            deleted_size += size
            print(f"  ✓ Deleted {filename}")
        except Exception as e:
            print(f"  ✗ Failed to delete {filename}: {e}")

    print(f"\n✅ Freed {deleted_size / 1024:.1f}KB")
    print(f"   Kept {keep_last} most recent recordings")


def clear_all():
    """Delete all cached recordings"""
    count, total_size, files = get_cache_stats()

    if count == 0:
        print("📭 Cache already empty")
        return

    print(f"⚠️  This will delete ALL {count} recordings ({total_size / 1024:.1f}KB)")
    response = input("Continue? (y/n): ")

    if response.lower() != 'y':
        print("Cancelled")
        return

    print("\n🧹 Clearing cache...")

    for filename, _, _ in files:
        path = os.path.join(CACHE_DIR, filename)
        try:
            os.remove(path)
            print(f"  ✓ Deleted {filename}")
        except Exception as e:
            print(f"  ✗ Failed: {e}")

    # Remove directory if empty
    try:
        if not os.listdir(CACHE_DIR):
            os.rmdir(CACHE_DIR)
            print(f"\n✅ Cache directory removed")
    except:
        pass

    print("\n✅ Cache cleared")


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 cache.py show          # Show cache contents")
        print("  python3 cache.py clean         # Keep last 5 recordings")
        print("  python3 cache.py clean 10      # Keep last 10 recordings")
        print("  python3 cache.py clear         # Delete everything")
        sys.exit(1)

    command = sys.argv[1]

    if command == "show":
        show_cache()
    elif command == "clean":
        keep = int(sys.argv[2]) if len(sys.argv) > 2 else 5
        clean_cache(keep)
    elif command == "clear":
        clear_all()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
