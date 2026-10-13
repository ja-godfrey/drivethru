#!/usr/bin/swift
// Recreated Chrome account switching for the teaser. All UI and data are drawn;
// this never opens a browser, reads accounts, or accesses Google's services.
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-account-scene: \(message)\n".utf8))
    exit(1)
}
let usage = "Usage: swift demo/render-account-scene.swift --output-dir DIR [--frames 120] [--fps 15]"
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") { print(usage); exit(0) }
var options: [String: String] = [:]
var argumentIndex = 0
while argumentIndex < arguments.count {
    let key = arguments[argumentIndex]
    guard ["--output-dir", "--frames", "--fps"].contains(key),
          argumentIndex + 1 < arguments.count, options[key] == nil else { fail(usage) }
    options[key] = arguments[argumentIndex + 1]
    argumentIndex += 2
}
guard let outputDirectory = options["--output-dir"], !outputDirectory.isEmpty,
      let frameCount = Int(options["--frames"] ?? "120"), (1...3600).contains(frameCount),
      let fps = Double(options["--fps"] ?? "15"), fps.isFinite, fps > 0, fps <= 120 else { fail(usage) }
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
    path.lineWidth = lineWidth; path.lineJoinStyle = .round; path.lineCapStyle = .round
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
func document(_ x: CGFloat, _ y: CGFloat, sheet: Bool = false) {
    box(x + 3, y, 17, 23, sheet ? 0x0f9d58 : 0x4285f4, radius: 2)
    if sheet {
        for column: CGFloat in [0, 5] {
            for row: CGFloat in [0, 4, 8] { box(x + 6 + column, y + 6 + row, 4, 3, 0xffffff) }
        }
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

let mouseKeys: [(Double, CGFloat, CGFloat)] = [
    (0, 441, 291), (0.48, 525, 20), (1.02, 525, 20),
    (1.66, 402, 177), (2.27, 402, 177), (2.60, 268, 20),
    (4.95, 268, 20), (5.60, 228, 184), (6.23, 228, 184),
    (6.82, 306, 184), (7.43, 306, 184), (7.80, 543, 329)
]
let fileOpenTime = 7.2
let fileOpenDoneTime = fileOpenTime + 0.10 // second click hands the file to Sheets
func cursor(at time: Double) -> (CGFloat, CGFloat) {
    for index in 1..<mouseKeys.count where time <= mouseKeys[index].0 {
        let from = mouseKeys[index - 1], to = mouseKeys[index]
        let fraction = max(0, min(1, (time - from.0) / (to.0 - from.0)))
        let eased = CGFloat(fraction * fraction * (3 - 2 * fraction))
        return (from.1 + (to.1 - from.1) * eased, from.2 + (to.2 - from.2) * eased)
    }
    return (mouseKeys.last!.1, mouseKeys.last!.2)
}

func drawDrive(work: Bool, finance: Bool, selected: Bool, mouse: (CGFloat, CGFloat)) {
    box(0, 39, 600, 336, 0xf8fafd)
    driveMark(18, 53)
    label("Drive", 63, 55, size: 25, weight: .medium, ink: 0x444746)
    box(145, 51, 433, 37, 0xe9eef6, radius: 18)
    color(0x5f6368).setStroke()
    let glass = NSBezierPath(ovalIn: rect(160, 61, 12, 12)); glass.lineWidth = 1.8; glass.stroke()
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
    label(finance ? "My Drive  ›  Finance" : "My Drive", 145, 111, size: 21, weight: .medium)
    label("Name", 184, 147, size: 12, weight: .medium, ink: 0x5f6368)
    stroke([(141, 165), (574, 165)], 0xe8eaed, lineWidth: 1)
    let rows = finance ? [("FY2026 Budget", "sheet"), ("Expense Policy.pdf", "document"), ("Vendor Contracts", "folder")]
        : work ? [("Finance", "folder"), ("Projects", "folder"), ("Team notes", "document")]
        : [("Home", "folder"), ("Travel", "folder"), ("Recipes", "document")]
    for (index, row) in rows.enumerated() {
        let y = CGFloat(166 + index * 42)
        let hovered = mouse.0 > 143 && mouse.0 < 578 && mouse.1 >= y && mouse.1 < y + 41
        if selected && index == 0 { box(139, y + 1, 438, 40, 0xc2e7ff, radius: 5) }
        else if hovered { box(139, y + 1, 438, 40, 0xf1f3f4, radius: 5) }
        if row.1 == "folder" { folder(151, y + 9) }
        else { document(151, y + 8, sheet: row.1 == "sheet") }
        label(row.0, 184, y + 10, size: 19)
        stroke([(143, y + 41), (575, y + 41)], 0xf0f1f2, lineWidth: 1)
    }
}

func drawNewTab() {
    box(0, 39, 600, 336, 0xffffff)
    let letters: [(String, UInt32)] = [("G", 0x4285f4), ("o", 0xea4335), ("o", 0xfbbc05),
                                     ("g", 0x4285f4), ("l", 0x34a853), ("e", 0xea4335)]
    var x: CGFloat = 220
    for (letter, shade) in letters {
        label(letter, x, 127, size: 45, weight: .medium, ink: shade)
        x += (letter as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 45, weight: .medium)]).width
    }
    box(110, 198, 380, 43, 0xf1f3f4, radius: 22)
    label("Search Google or type a URL", 158, 211, size: 16, ink: 0x5f6368)
    label("Work profile", 256, 272, size: 15, weight: .medium, ink: 0x5f6368)
}

func drawSheet() {
    box(0, 39, 600, 336, 0xffffff)
    document(18, 57, sheet: true)
    label("FY2026 Budget", 55, 53, size: 23, weight: .medium)
    label("File    Edit    View    Insert    Format", 56, 85, size: 14, ink: 0x5f6368)
    box(16, 112, 568, 29, 0xeaf1fb, radius: 12)
    label("100%       $     %       123             Arial     10", 35, 119, size: 12, ink: 0x444746)
    box(0, 151, 600, 24, 0xf8f9fa)
    box(0, 175, 31, 156, 0xf8f9fa)
    for (index, letter) in ["A", "B", "C"].enumerated() {
        label(letter, CGFloat(155 + index * 170), 156, size: 12, ink: 0x5f6368)
    }
    for index in 0...5 {
        let y = CGFloat(175 + index * 26)
        stroke([(0, y), (600, y)], 0xe0e3e7, lineWidth: 1)
        if index < 5 { label(String(index + 1), 12, y + 5, size: 12, ink: 0x5f6368) }
    }
    for x: CGFloat in [31, 272, 442] { stroke([(x, 151), (x, 331)], 0xe0e3e7, lineWidth: 1) }
    box(32, 176, 239, 25, 0xe6f4ea)
    label("Department", 41, 181, size: 14, weight: .medium)
    label("Annual budget", 283, 181, size: 14, weight: .medium)
    for (index, row) in [("Operations", "$120,000"), ("Marketing", "$80,000"), ("Engineering", "$250,000")].enumerated() {
        let y = CGFloat(207 + index * 26)
        label(row.0, 41, y, size: 14); label(row.1, 283, y, size: 14)
    }
    box(0, 343, 600, 32, 0xf8f9fa)
    box(55, 343, 126, 32, 0xd3e3fd)
    label("Budget", 85, 351, size: 14, weight: .medium, ink: 0x174ea6)
}

func renderFrame(at time: Double) {
    let work = time >= 2.2
    let profileMenu = time >= 0.8 && time < 2.2
    let newTab = time >= 2.2 && time < 5.25
    let finance = time >= 6.16
    let sheet = time >= fileOpenDoneTime + 0.08
    let mouse = cursor(at: time)
    box(0, 0, 600, 375, 0xffffff)
    if sheet { drawSheet() }
    else if newTab { drawNewTab() }
    else { drawDrive(work: work, finance: finance, selected: time >= fileOpenTime, mouse: mouse) }

    box(0, 0, 600, 39, work ? 0xe3ece8 : 0xe7eaed)
    for (index, shade): (Int, UInt32) in [0xff5f57, 0xfebc2e, 0x28c840].enumerated() {
        circle(12 + CGFloat(index) * 17, 15, 9, shade)
    }
    stroke([(82, 16), (77, 21), (82, 26)], 0x73777c)
    box(102, 7, 365, 26, 0xffffff, radius: 13)
    var address = "drive.google.com"
    if sheet { address = "docs.google.com/spreadsheets" }
    else if newTab {
        if time < 2.85 { address = "Search or enter address" }
        else { address = String("drive.google.com".prefix(max(0, min(16, Int((time - 3.05) / 0.09))))) }
    }
    label(address, 117, 12, size: 13.5, ink: newTab && time < 2.85 ? 0x80868b : 0x3c4043)
    if newTab && time >= 2.85 && time < 4.85 {
        let textWidth = (address as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13.5)]).width
        box(117 + textWidth + 1, 12, 1, 15, 0x202124)
    }
    box(478, 7, 111, 26, work ? 0xcde6d5 : 0xdce5f5, radius: 13)
    circle(484, 11, 18, work ? 0x137333 : 0x5e6cb2)
    label(work ? "W" : "P", 488, 12, size: 12, weight: .semibold, ink: 0xffffff)
    label(work ? "Work" : "Personal", 510, 12, size: 13.5, weight: .medium)
    if time >= 4.85 && time < 5.25 {
        box(0, 38, CGFloat((time - 4.85) / 0.4) * 600, 3, 0x1a73e8)
    }

    if profileMenu {
        box(275, 46, 314, 193, 0x202124, radius: 12, alpha: 0.17)
        box(272, 43, 314, 193, 0xffffff, radius: 11)
        label("Chrome profiles", 290, 55, size: 17, weight: .semibold)
        stroke([(289, 87), (570, 87)], 0xe8eaed, lineWidth: 1)
        box(283, 94, 292, 57, 0xf3f5fa, radius: 8)
        if mouse.1 >= 153 { box(283, 154, 292, 65, 0xe6f4ea, radius: 8) }
        circle(293, 104, 32, 0x5e6cb2)
        label("P", 303, 109, size: 18, weight: .semibold, ink: 0xffffff)
        label("Personal", 338, 100, size: 19, weight: .medium)
        label("you@gmail.com", 338, 124, size: 14, ink: 0x5f6368)
        circle(293, 167, 32, 0x137333)
        label("W", 300, 172, size: 18, weight: .semibold, ink: 0xffffff)
        label("Work", 338, 160, size: 19, weight: .medium)
        label("you@company.com", 338, 186, size: 14, ink: 0x5f6368)
    }

    let clicks: [(Double, CGFloat, CGFloat, Bool)] = [
        (0.8, 525, 20, false), (2.05, 402, 177, false), (2.85, 268, 20, false),
        (6.0, 228, 184, true), (fileOpenTime, 306, 184, true)
    ]
    for (clickTime, x, y, doubleClick) in clicks {
        for offset in doubleClick ? [0.0, 0.10] : [0.0] {
            let age = time - clickTime - offset
            if age >= 0 && age < 0.42 {
                let radius = CGFloat(7 + age * 29)
                color(0x1a73e8, alpha: CGFloat(1 - age / 0.42) * 0.8).setStroke()
                let ring = NSBezierPath(ovalIn: rect(x - radius, y - radius, radius * 2, radius * 2))
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
try Data(String(format: "%.6f\n", ceil(fileOpenDoneTime * fps) / fps).utf8).write(
    to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("complete-time.txt"))
print("Rendered \(frameCount) frames at \(fps) fps into \(outputDirectory)")
