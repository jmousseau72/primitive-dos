// End-to-end video-export smoke test: renders a small session through the
// bridge, checks pacing math, exports an H.264 movie via VideoExporter (the
// same code the app runs), then verifies the file with AVFoundation.
// Compiled by smoke-video.sh together with the app's non-UI sources.

import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: smoke-video <image> <out.mp4>") }
let imagePath = args[1]
let outURL = URL(fileURLWithPath: args[2])

// 1. Pacing math checks (pure).
do {
    let linear = Pacing.cumulativeTargets(shapeCount: 100, activeFrames: 10, curve: .linear, scores: [])
    precondition(linear.last == 100, "linear must complete")
    precondition(linear == linear.sorted(), "linear must be monotone")

    let ease = Pacing.cumulativeTargets(shapeCount: 1000, activeFrames: 30, curve: .easeIn, scores: [])
    precondition(ease.last == 1000 && ease.first! < 40, "easeIn must start slow, end complete")

    let few = Pacing.cumulativeTargets(shapeCount: 5, activeFrames: 60, curve: .linear, scores: [])
    precondition(few.last == 5 && Set(few).count <= 6, "n<N duplicates frames")

    let scores = (0..<50).map { 0.5 - Double($0) * 0.005 }
    let weighted = Pacing.cumulativeTargets(shapeCount: 50, activeFrames: 20, curve: .scoreWeighted, scores: scores)
    precondition(weighted.last == 50 && weighted == weighted.sorted(), "scoreWeighted monotone + complete")

    let fallback = Pacing.cumulativeTargets(shapeCount: 50, activeFrames: 20, curve: .scoreWeighted, scores: [])
    precondition(fallback.last == 50, "short scores must fall back safely")
    print("pacing ok")
}

// 2. Render a small session through the bridge.
var params = EngineParams()
params.inputPath = imagePath
params.mode = 6
params.shapeCount = 150
params.alpha = 255
params.inputResize = 128
params.outputSize = 512
params.strokeWidth = 1.5
params.runMode = .count
let sessionId = try Engine.startRender(params)

var rendered = false
pump: while true {
    guard let raw = PrimitiveNextEvent() else { fatalError("event stream closed") }
    let data = Data(String(cString: raw).utf8)
    PrimitiveFree(raw)
    guard let event = EngineEvent(json: data) else { continue }
    switch event {
    case .done:
        rendered = true
        break pump
    case .error(let e):
        fatalError("engine error: \(e.message)")
    default:
        break
    }
}
precondition(rendered)
print("render ok")

// 3. Fetch shape history.
let shapeData = try Engine.getShapes(id: sessionId)
precondition(shapeData.shapes.count >= 150, "expected >=150 shapes, got \(shapeData.shapes.count)")
precondition(shapeData.background.hasPrefix("#"), "background format")
print("getShapes ok: \(shapeData.shapes.count) shapes, \(shapeData.width)x\(shapeData.height)")

// 4. Export a short H.264 video.
var settings = VideoExportSettings()
settings.format = .h264
settings.size = .fit1080p
settings.fps = 30
settings.duration = 3
settings.holdSeconds = 1
settings.pacing = .easeIn

try await VideoExporter.export(data: shapeData, settings: settings, to: outURL) { fraction in
    if fraction >= 1 { print("export progress complete") }
}
print("export ok")

// 5. Verify the file with AVFoundation.
let asset = AVURLAsset(url: outURL)
let duration = try await asset.load(.duration).seconds
precondition(abs(duration - 4.0) < 0.2, "duration \(duration) != ~4s")
let track = try await asset.loadTracks(withMediaType: .video)[0]
let size = try await track.load(.naturalSize)
let fps = try await track.load(.nominalFrameRate)
let formats = try await track.load(.formatDescriptions)
let fourcc = CMFormatDescriptionGetMediaSubType(formats[0])
precondition(Int(size.width) % 2 == 0 && Int(size.height) % 2 == 0, "odd dimensions")
precondition(fourcc == kCMVideoCodecType_H264, "unexpected codec fourcc")
precondition(abs(fps - 30) < 0.5, "fps \(fps)")
let bytes = ((try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size]) as? Int) ?? 0
precondition(bytes > 10_000, "suspiciously small file")
print("verify ok: \(Int(size.width))x\(Int(size.height)) @ \(fps)fps, \(duration)s, \(bytes) bytes")

PrimitiveShutdown()
print("VIDEO SMOKE PASS")
