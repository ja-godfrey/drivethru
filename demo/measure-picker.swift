#!/usr/bin/swift
// Locate a visible result marker in an actual picker recording. The reported
// timestamp follows ffmpeg's fps filter: round input PTS to the output frame
// grid and retain the last input frame mapped to each output timestamp.
// This measures a demo result panel, not a browser load or a product benchmark.
import AVFoundation
import Foundation
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("measure-picker: \(message)\n".utf8))
    exit(1)
}

let usage = "Usage: swift demo/measure-picker.swift --input FILE --marker TEXT [--fps 15]"
let args = Array(CommandLine.arguments.dropFirst())
let allowed = Set(["--input", "--marker", "--fps"])
var options: [String: String] = [:]
var argumentIndex = 0
while argumentIndex < args.count {
    let key = args[argumentIndex]
    guard allowed.contains(key), argumentIndex + 1 < args.count,
          options[key] == nil else { fail(usage) }
    options[key] = args[argumentIndex + 1]
    argumentIndex += 2
}
guard let input = options["--input"], !input.isEmpty,
      let marker = options["--marker"], !marker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let fps = Int32(options["--fps"] ?? "15"), (1...120).contains(fps) else { fail(usage) }
guard FileManager.default.fileExists(atPath: input) else { fail("input does not exist: \(input)") }

// Vision may normalize letter case or whitespace. Require the complete line
// to match, rather than accepting an unrelated line containing the phrase.
func normalized(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").uppercased()
}
let expected = normalized(marker)
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]
request.usesLanguageCorrection = false
request.customWords = [marker]

func containsMarker(_ sample: CMSampleBuffer) throws -> Bool {
    guard let image = CMSampleBufferGetImageBuffer(sample) else {
        fail("decoded frame has no image buffer")
    }
    return try autoreleasepool {
        let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).contains { observation in
            guard let candidate = observation.topCandidates(1).first else { return false }
            return normalized(candidate.string) == expected
        }
    }
}

do {
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        fail("input has no video track")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { fail("cannot decode the video track") }
    reader.add(output)
    guard reader.startReading() else {
        fail(reader.error?.localizedDescription ?? "cannot start reading the video")
    }

    var pending: CMSampleBuffer?
    var pendingTick: Int64 = 0
    while let sample = output.copyNextSampleBuffer() {
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard time.isNumeric else { fail("video contains an invalid frame timestamp") }
        let tick = CMTimeConvertScale(time, timescale: fps, method: .roundHalfAwayFromZero).value
        if let previous = pending, tick != pendingTick {
            guard tick > pendingTick else { fail("video timestamps are not increasing") }
            if try containsMarker(previous) {
                reader.cancelReading()
                print(String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"),
                             Double(pendingTick) / Double(fps)))
                exit(0)
            }
        }
        pending = sample
        pendingTick = tick
    }
    guard reader.status == .completed else {
        fail(reader.error?.localizedDescription ?? "video decoding failed")
    }
    if let last = pending, try containsMarker(last) {
        print(String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"),
                     Double(pendingTick) / Double(fps)))
        exit(0)
    }
    fail("marker was not found: \(marker)")
} catch {
    fail(error.localizedDescription)
}
