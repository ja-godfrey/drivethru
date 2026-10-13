#!/usr/bin/swift
// Synthetic Drive folder navigation for the side-by-side teaser.
// This draws a recreation only: no browser, Google service, or clipboard access.
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-folder-scene: \(message)\n".utf8))
    exit(1)
}

let usage = "Usage: swift demo/render-folder-scene.swift --output-dir DIR [--frames 195] [--fps 15]"
var options: [String: String] = [:]
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") { print(usage); exit(0) }
var argumentIndex = 0
while argumentIndex < arguments.count {
    let key = arguments[argumentIndex]
    guard ["--output-dir", "--frames", "--fps"].contains(key),
          argumentIndex + 1 < arguments.count, options[key] == nil else { fail(usage) }
    options[key] = arguments[argumentIndex + 1]
    argumentIndex += 2
}
guard let outputDirectory = options["--output-dir"], !outputDirectory.isEmpty,
      let frameCount = Int(options["--frames"] ?? "195"), (1...3600).contains(frameCount),
      let fps = Double(options["--fps"] ?? "15"), fps.isFinite, fps > 0, fps <= 120 else {
    fail(usage)
}
do {
    try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
} catch { fail("could not create output directory: \(error.localizedDescription)") }

let width = 600
let height = 375
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
// Drawing helpers use top-left coordinates; AppKit's canvas uses bottom-left.
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(height) - y - h, width: w, height: h)
}
func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: CGFloat(height) - y) }
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: UInt32,
         radius: CGFloat = 0, alpha: CGFloat = 1) {
    color(fill, alpha: alpha).setFill()
    NSBezierPath(roundedRect: rect(x, y, w, h), xRadius: radius, yRadius: radius).fill()
}
func label(_ value: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 16,
           weight: NSFont.Weight = .regular, ink: UInt32 = 0x202124) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(ink)
    ]
    let dimensions = (value as NSString).size(withAttributes: attributes)
    (value as NSString).draw(at: point(x, y + dimensions.height), withAttributes: attributes)
}
func stroke(_ points: [(CGFloat, CGFloat)], _ ink: UInt32, lineWidth: CGFloat = 1.5,
            close: Bool = false, fill: UInt32? = nil, alpha: CGFloat = 1) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: point(first.0, first.1))
    for item in points.dropFirst() { path.line(to: point(item.0, item.1)) }
    if close { path.close() }
    if let fill = fill { color(fill, alpha: alpha).setFill(); path.fill() }
    color(ink, alpha: alpha).setStroke()
    path.lineWidth = lineWidth
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    path.stroke()
}
func circle(_ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat, _ fill: UInt32) {
    color(fill).setFill()
    NSBezierPath(ovalIn: rect(x, y, diameter, diameter)).fill()
}
func folder(_ x: CGFloat, _ y: CGFloat, size: CGFloat = 22) {
    let scale = size / 22
    box(x, y + 2 * scale, 10 * scale, 5 * scale, 0x70757a, radius: 1.5 * scale)
    box(x, y + 5 * scale, 22 * scale, 15 * scale, 0x70757a, radius: 2 * scale)
}
func document(_ x: CGFloat, _ y: CGFloat, slides: Bool = false) {
    let shade: UInt32 = slides ? 0xf4b400 : 0x4285f4
    box(x + 3, y, 17, 23, shade, radius: 2)
    if slides {
        box(x + 6, y + 7, 11, 8, 0xffffff, radius: 0.7)
        box(x + 7.5, y + 8.5, 8, 5, shade)
    } else {
        for dy: CGFloat in [7, 11, 15] { box(x + 7, y + dy, 9, 1.5, 0xffffff) }
    }
}
func driveMark(_ x: CGFloat, _ y: CGFloat) {
    stroke([(x + 12, y), (x + 23, y), (x + 11, y + 21), (x, y + 21)],
           0x0f9d58, lineWidth: 0, close: true, fill: 0x0f9d58)
    stroke([(x + 23, y), (x + 36, y + 21), (x + 25, y + 21), (x + 12, y)],
           0xf4b400, lineWidth: 0, close: true, fill: 0xf4b400)
    stroke([(x, y + 21), (x + 36, y + 21), (x + 30, y + 31), (x + 6, y + 31)],
           0x4285f4, lineWidth: 0, close: true, fill: 0x4285f4)
}

struct Item { let name: String; let kind: String }
let scenes: [[Item]] = [
    [Item(name: "Finance", kind: "folder"), Item(name: "Projects", kind: "folder"), Item(name: "Team notes", kind: "document")],
    [Item(name: "2026", kind: "folder"), Item(name: "Archive", kind: "folder"), Item(name: "Ideas", kind: "folder")],
    [Item(name: "Q1", kind: "folder"), Item(name: "Q2", kind: "folder"), Item(name: "Q3", kind: "folder"), Item(name: "Q4", kind: "folder")],
    [Item(name: "Planning", kind: "folder"), Item(name: "Board", kind: "folder"), Item(name: "Reports", kind: "folder")],
    [Item(name: "Final", kind: "folder"), Item(name: "Drafts", kind: "folder"), Item(name: "Board notes", kind: "document")],
    [Item(name: "Board Deck - Q3 2026", kind: "slides"), Item(name: "Speaker notes", kind: "document"), Item(name: "Agenda", kind: "document")]
]
let breadcrumbs = ["My Drive", "My Drive  ›  Projects", "Projects  ›  2026",
                   "2026  ›  Q3", "Q3  ›  Board", "Board  ›  Final"]
let clickTimes = [0.8, 2.0, 3.2, 4.4, 5.6, 7.0, 8.4, 9.6]
let copyResultTime = 9.78
let clickPoints: [(CGFloat, CGFloat)] = [(242, 225), (221, 183), (218, 267),
                                       (229, 225), (213, 183), (326, 183),
                                       (563, 182), (470, 262)]
// Hold briefly at each target before clicking so viewers can follow the mouse.
var mouseKeys: [(Double, CGFloat, CGFloat)] = [(0, 548, 334)]
for (time, location) in zip(clickTimes, clickPoints) {
    mouseKeys.append((max(0, time - 0.38), location.0, location.1))
    mouseKeys.append((time + 0.22, location.0, location.1))
}
mouseKeys.append((10.35, 548, 309))
func cursor(at time: Double) -> (CGFloat, CGFloat) {
    for index in 1..<mouseKeys.count where time <= mouseKeys[index].0 {
        let from = mouseKeys[index - 1], to = mouseKeys[index]
        let fraction = max(0, min(1, (time - from.0) / (to.0 - from.0)))
        let eased = CGFloat(fraction * fraction * (3 - 2 * fraction))
        return (from.1 + (to.1 - from.1) * eased, from.2 + (to.2 - from.2) * eased)
    }
    return (mouseKeys.last!.1, mouseKeys.last!.2)
}

func renderFrame(at time: Double) {
    let stage = [0.96, 2.16, 3.36, 4.56, 5.76].filter { time >= $0 }.count
    let selected = time >= 7.0
    let menuVisible = time >= 8.4 && time < copyResultTime
    let copied = time >= copyResultTime
    let mouse = cursor(at: time)

    box(0, 0, 600, 375, 0xf8fafd)
    // Familiar browser chrome, without any personal profile or account details.
    box(0, 0, 600, 39, 0xe7eaed)
    for (index, shade): (Int, UInt32) in [0xff5f57, 0xfebc2e, 0x28c840].enumerated() {
        circle(12 + CGFloat(index) * 17, 15, 9, shade)
    }
    stroke([(82, 16), (77, 21), (82, 26)], 0x73777c)
    box(102, 8, 420, 25, 0xffffff, radius: 12)
    label("drive.google.com", 121, 12, size: 13, ink: 0x5f6368)
    circle(561, 13, 15, 0xc0c6cc)

    driveMark(18, 53)
    label("Drive", 63, 55, size: 25, weight: .medium, ink: 0x444746)
    box(145, 51, 433, 37, 0xe9eef6, radius: 18)
    color(0x5f6368).setStroke()
    let glass = NSBezierPath(ovalIn: rect(160, 61, 12, 12))
    glass.lineWidth = 1.8; glass.stroke()
    stroke([(170, 71), (175, 76)], 0x5f6368, lineWidth: 1.8)
    label("Search in Drive", 188, 60, size: 16, ink: 0x686d73)

    box(12, 107, 94, 43, 0xffffff, radius: 13)
    label("+", 23, 109, size: 29, weight: .light)
    label("New", 55, 118, size: 16, weight: .medium)
    box(7, 166, 108, 34, 0xc2e7ff, radius: 17)
    folder(18, 175, size: 16)
    label("My Drive", 40, 173, size: 14, weight: .medium, ink: 0x174ea6)
    label("Shared", 41, 216, size: 14, ink: 0x5f6368)
    label("Recent", 41, 251, size: 14, ink: 0x5f6368)
    label("Starred", 41, 286, size: 14, ink: 0x5f6368)

    box(126, 100, 462, 264, 0xffffff, radius: 15)
    label(breadcrumbs[stage], 145, 111, size: 21, weight: .medium)
    label("Name", 184, 147, size: 12, weight: .medium, ink: 0x5f6368)
    stroke([(141, 165), (574, 165)], 0xe8eaed, lineWidth: 1)

    for (index, item) in scenes[stage].enumerated() {
        let y = CGFloat(166 + index * 42)
        let hovered = mouse.0 > 143 && mouse.0 < 578 && mouse.1 >= y && mouse.1 < y + 41 && !menuVisible && !copied
        let fileSelected = stage == 5 && index == 0 && selected
        if fileSelected { box(139, y + 1, 438, 40, 0xc2e7ff, radius: 5) }
        else if hovered { box(139, y + 1, 438, 40, 0xf1f3f4, radius: 5) }
        if item.kind == "folder" { folder(151, y + 9) }
        else { document(151, y + 8, slides: item.kind == "slides") }
        label(item.name, 184, y + 10, size: item.kind == "slides" ? 18 : 19)
        if fileSelected {
            for dotY: CGFloat in [y + 11, y + 17, y + 23] { circle(561, dotY, 3, 0x3c4043) }
        }
        stroke([(143, y + 41), (575, y + 41)], 0xf0f1f2, lineWidth: 1)
    }

    if menuVisible {
        box(380, 200, 202, 91, 0x202124, radius: 9, alpha: 0.12)
        box(377, 197, 202, 91, 0xffffff, radius: 8)
        if mouse.1 > 242 { box(381, 243, 194, 40, 0xe8f0fe, radius: 4) }
        label("Share", 418, 209, size: 18)
        label("Copy link", 418, 252, size: 18, weight: .medium)
        stroke([(395, 219), (405, 219)], 0x5f6368)
        circle(394, 207, 5, 0x5f6368)
        stroke([(396, 212), (391, 224), (402, 224)], 0x5f6368)
        // Two linked outlines give the copy action a readable icon.
        for dx: CGFloat in [0, 7] {
            color(0x3c4043).setStroke()
            let link = NSBezierPath(roundedRect: rect(391 + dx, 258, 12, 8), xRadius: 4, yRadius: 4)
            link.lineWidth = 1.5; link.stroke()
        }
    }
    if copied {
        box(292, 317, 283, 45, 0x303134, radius: 8)
        stroke([(310, 339), (316, 345), (326, 333)], 0x81c995, lineWidth: 2.5)
        label("Link copied", 340, 328, size: 19, weight: .medium, ink: 0xffffff)
    }

    // Click rings are deliberately larger than the pointer for small embeds.
    for (index, click) in zip(clickTimes, clickPoints).enumerated() {
        let (clickTime, location) = click
        let pulseOffsets = index < 5 ? [0.0, 0.10] : [0.0]
        for offset in pulseOffsets {
            let age = time - clickTime - offset
            if age >= 0 && age < 0.42 {
                let radius = CGFloat(7 + age * 29)
                color(0x1a73e8, alpha: CGFloat(1 - age / 0.42) * 0.8).setStroke()
                let ring = NSBezierPath(ovalIn: rect(location.0 - radius, location.1 - radius, radius * 2, radius * 2))
                ring.lineWidth = 2.5; ring.stroke()
            }
        }
    }
    let mx = mouse.0, my = mouse.1
    stroke([(mx, my), (mx + 1, my + 23), (mx + 7, my + 17),
            (mx + 12, my + 27), (mx + 17, my + 24), (mx + 12, my + 15), (mx + 20, my + 14)],
           0xffffff, lineWidth: 1.5, close: true, fill: 0x202124)
}

for frame in 0..<frameCount {
    autoreleasepool {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fail("could not create bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.shouldAntialias = true
        renderFrame(at: Double(frame) / fps)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fail("could not encode PNG") }
        let path = URL(fileURLWithPath: outputDirectory).appendingPathComponent(String(format: "frame-%04d.png", frame))
        do { try data.write(to: path, options: .atomic) }
        catch { fail("could not write frame \(frame): \(error.localizedDescription)") }
    }
}
try Data(String(format: "%.6f\n", ceil(copyResultTime * fps) / fps).utf8).write(
    to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("complete-time.txt"))
print("Rendered \(frameCount) frames at \(fps) fps into \(outputDirectory)")
