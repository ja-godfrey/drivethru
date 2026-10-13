#!/usr/bin/swift
// Assemble the two demo panes and captions into 1280x800 PNG frames.
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("compose-teaser: \(message)\n".utf8))
    exit(1)
}

var options: [String: String] = [:]
let args = Array(CommandLine.arguments.dropFirst())
guard args.count % 2 == 0 else { fail("expected --option value pairs") }
for i in stride(from: 0, to: args.count, by: 2) { options[args[i]] = args[i + 1] }
guard let browserDir = options["--browser-dir"], let pickerDir = options["--picker-dir"],
      let accountBrowserDir = options["--account-browser-dir"], let accountsDir = options["--accounts-dir"],
      let outputDir = options["--output-dir"],
      let count = Int(options["--frames"] ?? "300"), count > 0,
      let fps = Double(options["--fps"] ?? "15"), fps > 0 else {
    fail("--browser-dir DIR --picker-dir DIR --account-browser-dir DIR --accounts-dir DIR --output-dir DIR [--frames 300 --fps 15]")
}
let width = 1280, height = 800
let manager = FileManager.default
try manager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
func loadFrames(_ directory: String) throws -> [NSImage] {
    let paths = try manager.contentsOfDirectory(atPath: directory)
        .filter { $0.hasPrefix("frame-") && $0.hasSuffix(".png") }.sorted()
    guard !paths.isEmpty else { fail("no picker frames in \(directory)") }
    return paths.map { path in
        guard let image = NSImage(contentsOfFile: "\(directory)/\(path)") else { fail("cannot read \(path)") }
        return image
    }
}
let pickerImages = try loadFrames(pickerDir)
let accountImages = try loadFrames(accountsDir)
let accountStart = 11.0
func completionTime(_ directory: String) throws -> Double {
    let value = try String(contentsOfFile: "\(directory)/complete-time.txt", encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let time = Double(value), time.isFinite, time > 0 else { fail("invalid completion time in \(directory)") }
    return time
}
let doneTime = try completionTime(pickerDir)
let accountDoneTime = try completionTime(accountsDir)
let nativeDoneTime = try completionTime(browserDir)
let nativeAccountDoneTime = try completionTime(accountBrowserDir)
guard doneTime < accountStart, nativeDoneTime < accountStart,
      accountDoneTime < Double(count) / fps - accountStart,
      nativeAccountDoneTime < Double(count) / fps - accountStart else { fail("a workflow is longer than its scene") }

func color(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: alpha)
}
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(height) - top - h, width: w, height: h)
}
func text(_ string: String, _ x: CGFloat, _ top: CGFloat, size: CGFloat,
          ink: UInt32 = 0xf2f5fc, weight: NSFont.Weight = .regular,
          mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(ink)]
    let bounds = (string as NSString).size(withAttributes: attributes)
    guard x + bounds.width <= CGFloat(width) - 20 else { fail("text exceeds canvas: \(string)") }
    (string as NSString).draw(at: NSPoint(x: x, y: CGFloat(height) - top - bounds.height),
                             withAttributes: attributes)
}
func rounded(_ bounds: NSRect, radius: CGFloat, fill: UInt32,
             stroke: UInt32? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    color(fill).setFill(); path.fill()
    if let stroke = stroke { color(stroke).setStroke(); path.lineWidth = lineWidth; path.stroke() }
}
func image(_ value: NSImage, in bounds: NSRect) {
    value.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
}
func timer(_ elapsed: Double, stopped: Bool, x: CGFloat, tint: UInt32) {
    rounded(rect(x, 146, 142, 52), radius: 10, fill: stopped ? 0x25372f : 0x111827)
    text("DEMO TIME", x + 13, 150, size: 10, ink: 0xb6c1d4, weight: .semibold)
    text(String(format: "%04.1fs", elapsed), x + 13, 163, size: 25,
         ink: stopped ? tint : 0xf2f5fc, weight: .semibold, mono: true)
}

for frame in 0..<count {
    try autoreleasepool {
        let t = Double(frame) / fps
        let isAccounts = t >= accountStart
        let sceneFrame = isAccounts ? frame - Int(accountStart * fps) : frame
        let sceneTime = Double(sceneFrame) / fps
        let sceneBrowserDir = isAccounts ? accountBrowserDir : browserDir
        let sceneImages = isAccounts ? accountImages : pickerImages
        let rightDone = isAccounts ? accountDoneTime : doneTime
        let leftDone = isAccounts ? nativeAccountDoneTime : nativeDoneTime
        let isDone = sceneTime >= rightDone
        let bothDone = isDone && sceneTime >= leftDone
        guard let browser = NSImage(contentsOfFile: String(format: "%@/frame-%04d.png", sceneBrowserDir, sceneFrame)),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fail("cannot render frame \(frame)") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.shouldAntialias = true
        context.imageInterpolation = .high
        color(0x0d1220).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()

        let action = !isAccounts ? "copy links" :
            sceneTime < 2.4 ? "search all accounts" :
            sceneTime < 4.2 ? "filter by account" : "open links"
        let titlePrefix = "Drivethru is a better way to "
        let titleFont = NSFont.systemFont(ofSize: 40, weight: .bold)
        let actionX = 28 + (titlePrefix as NSString).size(withAttributes: [.font: titleFont]).width
        text(titlePrefix, 28, 48, size: 40, weight: .bold)
        text(action, actionX, 48, size: 40, ink: 0xa6f1d2, weight: .bold)

        rounded(rect(28, 136, 600, 447), radius: 14, fill: 0x192236, stroke: 0x344157)
        rounded(rect(652, 136, 600, 447), radius: 14, fill: 0x152a29, stroke: 0x3e8071)
        text("google native workflow", 48, 153, size: 27, ink: 0xffcf7c, weight: .bold)
        text("drivethru workflow", 672, 153, size: 27, ink: 0xa6f1d2, weight: .bold)
        timer(min(sceneTime, leftDone), stopped: sceneTime >= leftDone, x: 468, tint: 0xffcf7c)
        timer(min(sceneTime, rightDone), stopped: isDone, x: 1092, tint: 0xa6f1d2)

        image(browser, in: rect(28, 208, 600, 375))
        image(sceneImages[min(sceneFrame, sceneImages.count - 1)], in: rect(652, 208, 600, 375))

        if bothDone {
            // Calculate the speed ratio from the same tenths shown by the frozen clocks.
            let leftDisplayed = (leftDone * 10).rounded() / 10
            let rightDisplayed = (rightDone * 10).rounded() / 10
            let speedup = leftDisplayed / rightDisplayed
            let comparison = String(format: "%.1f× %@ in this demo",
                                    speedup >= 1 ? speedup : 1 / speedup,
                                    speedup >= 1 ? "faster" : "slower")
            rounded(rect(677, 515, 550, 47), radius: 10, fill: 0xa6f1d2)
            text(comparison, 696, 525, size: 25, ink: 0x132722, weight: .bold)
        }

        text("To install drivethru, open Terminal and type:", 28, 629, size: 27, weight: .medium)
        rounded(rect(28, 685, 1224, 68), radius: 10, fill: 0x192236)
        let command = "brew install ja-godfrey/tap/drivethru"
        text(command, 51, 703, size: 28, ink: 0xa6f1d2, mono: true)
        if Int(t * 2) % 2 == 0 {
            let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
            let cursorX = 53 + (command as NSString).size(withAttributes: [.font: font]).width
            color(0xa6f1d2).setFill(); rect(cursorX, 706, 13, 31).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fail("PNG encoding failed") }
        try data.write(to: URL(fileURLWithPath: String(format: "%@/frame-%04d.png", outputDir, frame)))
    }
}
print("Composed \(count) frames at \(Int(fps)) fps (\(Double(count) / fps)s)")
print(String(format: "Demo clocks: copy %.1fs → %.1fs; accounts %.1fs → %.1fs", nativeDoneTime, doneTime, nativeAccountDoneTime, accountDoneTime))
