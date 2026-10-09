#!/usr/bin/swift
// Render a caption banner for the recorded demos using stock macOS frameworks.
// Example:
//   swift demo/render-caption.swift --output /tmp/caption.png --width 1360 \
//     --title 'Copy a Drive link' --subtitle 'Search, choose, paste.' --keys 'Enter'
// Multiple keycaps are separated by |, for example --keys 'Tab|Tab|Ctrl-Y'.

import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-caption: \(message)\n".utf8))
    exit(1)
}

let usage = """
Usage: swift demo/render-caption.swift --output FILE --width PIXELS \\
  --title TEXT --subtitle TEXT [--height PIXELS] [--keys 'KEY|KEY']

Writes an opaque PNG banner. Height defaults to 128 pixels. Use ffmpeg vstack
to place it above a VHS recording. This helper does not modify the recording.
"""

var options: [String: String] = [:]
let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") {
    print(usage)
    exit(0)
}
let allowed = Set(["--output", "--width", "--height", "--title", "--subtitle", "--keys"])
var index = 0
while index < args.count {
    let key = args[index]
    guard allowed.contains(key), index + 1 < args.count else { fail(usage) }
    guard options[key] == nil else { fail("duplicate option \(key)") }
    options[key] = args[index + 1]
    index += 2
}
guard let output = options["--output"], !output.isEmpty,
      let widthText = options["--width"], let width = Int(widthText),
      let title = options["--title"], !title.isEmpty,
      let subtitle = options["--subtitle"], !subtitle.isEmpty else { fail(usage) }
guard let height = Int(options["--height"] ?? "128"),
      (640...4096).contains(width), (112...512).contains(height) else {
    fail("width must be 640–4096 and height must be 112–512 pixels")
}

func color(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: 1)
}

let titleFont = NSFont.systemFont(ofSize: 34, weight: .semibold)
let subtitleFont = NSFont.systemFont(ofSize: 22, weight: .regular)
let keyFont = NSFont.monospacedSystemFont(ofSize: 23, weight: .semibold)
let keys = (options["--keys"] ?? "").split(separator: "|").map(String.init)
let keyWidths = keys.map { ceil(($0 as NSString).size(withAttributes: [.font: keyFont]).width) + 32 }
let keysWidth = keyWidths.reduce(0, +) + CGFloat(max(keys.count - 1, 0)) * 12
let textWidth = CGFloat(width) - 64 - (keys.isEmpty ? 0 : keysWidth + 32)
let titleSize = (title as NSString).size(withAttributes: [.font: titleFont])
let subtitleSize = (subtitle as NSString).size(withAttributes: [.font: subtitleFont])
guard titleSize.width <= textWidth, subtitleSize.width <= textWidth else {
    fail("caption text does not fit beside the keycaps; shorten it or increase --width")
}

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fail("could not create the bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true

color(0x11111b).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
color(0x45475a).setFill()
NSRect(x: 0, y: 0, width: width, height: 1).fill()

let titleY = CGFloat(height) - 22 - titleSize.height
(title as NSString).draw(at: NSPoint(x: 32, y: titleY),
                        withAttributes: [.font: titleFont, .foregroundColor: color(0xcdd6f4)])
(subtitle as NSString).draw(at: NSPoint(x: 32, y: 24),
                           withAttributes: [.font: subtitleFont, .foregroundColor: color(0xa6adc8)])

var keyX = CGFloat(width) - 32 - keysWidth
for (key, keyWidth) in zip(keys, keyWidths) {
    let rect = NSRect(x: keyX, y: (CGFloat(height) - 54) / 2, width: keyWidth, height: 54)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    color(0x313244).setFill()
    shape.fill()
    color(0x585b70).setStroke()
    shape.lineWidth = 1
    shape.stroke()
    let size = (key as NSString).size(withAttributes: [.font: keyFont])
    (key as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2,
                                     y: rect.midY - size.height / 2),
                           withAttributes: [.font: keyFont, .foregroundColor: color(0xa6e3a1)])
    keyX += keyWidth + 12
}

NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fail("could not encode the PNG")
}
do {
    try data.write(to: URL(fileURLWithPath: output), options: .atomic)
} catch {
    fail("could not write \(output): \(error.localizedDescription)")
}
