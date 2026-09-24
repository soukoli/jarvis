#!/usr/bin/env zsh
# Rasterize App/Design/jarvis-mark.svg into AppIcon.appiconset (all macOS sizes).
# Uses AppKit's SVG support via a small Swift script; no third-party tools.
set -euo pipefail
cd "$(dirname "$0")/.."
ASSETS=App/Assets.xcassets
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/render.swift" <<'EOF'
import AppKit
let args = CommandLine.arguments
guard args.count == 4, let px = Int(args[3]) else { fputs("usage: render <in.svg> <out.png> <px>\n", stderr); exit(2) }
guard let image = NSImage(contentsOfFile: args[1]) else { fputs("cannot read \(args[1])\n", stderr); exit(1) }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: args[2]))
EOF
swiftc -O -o "$TMP/render" "$TMP/render.swift" 2>/dev/null

render() { "$TMP/render" "$1" "$2" "$3"; }

# App icon (macOS sizes)
ICON=$ASSETS/AppIcon.appiconset
for px in 16 32 64 128 256 512 1024; do render App/Design/jarvis-mark.svg "$ICON/icon_$px.png" $px; done
cat > "$ICON/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

echo "rendered: $(ls $ICON/*.png | wc -l | tr -d ' ') app icon sizes"
