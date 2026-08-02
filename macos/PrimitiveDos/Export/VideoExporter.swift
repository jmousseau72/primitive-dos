// Video export: replays a session's shape history into an AVAssetWriter so
// the artwork draws itself. One master BGRA bitmap context accumulates
// shapes (O(new shapes) per frame, like the live preview); each frame is
// row-copied into a pool pixel buffer and appended with exact CMTime.

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

enum VideoExportFormat: String, CaseIterable, Identifiable, Sendable {
    case h264, hevc, prores

    var id: String { rawValue }

    var label: String {
        switch self {
        case .h264: "H.264 (MP4)"
        case .hevc: "HEVC (MP4)"
        case .prores: "ProRes 422 (MOV)"
        }
    }

    var codec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .prores: .proRes422
        }
    }

    var fileType: AVFileType {
        switch self {
        case .h264, .hevc: .mp4
        case .prores: .mov
        }
    }

    var fileExtension: String {
        switch self {
        case .h264, .hevc: "mp4"
        case .prores: "mov"
        }
    }

    /// Rough output size in bytes for the sheet's estimate line.
    func estimatedBytes(width: Int, height: Int, fps: Int, seconds: Double) -> Int {
        switch self {
        case .h264, .prores, .hevc:
            let bps: Double
            if self == .prores {
                // ProRes 422 is fixed-quality; ~122 Mbps at 1080p30, scales
                // with pixel rate.
                bps = Double(width * height * fps) / (1920 * 1080 * 30) * 122_000_000
            } else {
                bps = Double(bitrate(width: width, height: height, fps: fps))
            }
            return Int(bps * seconds / 8)
        }
    }

    /// Generous bitrate: this content has hard vector edges that punish
    /// starved encoders with ringing.
    func bitrate(width: Int, height: Int, fps: Int) -> Int {
        let bpp = self == .hevc ? 0.09 : 0.16
        let raw = Double(width * height * fps) * bpp
        return Int(min(max(raw, 4_000_000), 80_000_000))
    }
}

enum VideoSizePreset: String, CaseIterable, Identifiable, Sendable {
    case native, fit4K, fit1080p

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: "Native"
        case .fit4K: "4K"
        case .fit1080p: "1080p"
        }
    }

    /// Shapes are vectors, so fitting UP-scales small models crisply. Both
    /// dimensions floor to even (4:2:0 chroma requires it).
    func renderSize(modelW: Int, modelH: Int) -> (width: Int, height: Int) {
        var w = Double(modelW)
        var h = Double(modelH)
        let box: Double? = switch self {
        case .native: nil
        case .fit4K: 3840
        case .fit1080p: 1920
        }
        if let box {
            let scale = box / max(w, h)
            w *= scale
            h *= scale
        }
        return (max(2, Int(w) & ~1), max(2, Int(h) & ~1))
    }
}

enum PacingCurve: String, CaseIterable, Identifiable, Sendable {
    case easeIn, linear, scoreWeighted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easeIn: "Slow start"
        case .linear: "Linear"
        case .scoreWeighted: "Even progress"
        }
    }
}

struct VideoExportSettings: Sendable {
    var format: VideoExportFormat = .h264
    var size: VideoSizePreset = .fit4K
    var fps = 30
    var duration = 10.0
    var holdSeconds = 2.0
    var pacing: PacingCurve = .easeIn
}

enum VideoExportError: LocalizedError {
    case setup(String)
    case writer(String)

    var errorDescription: String? {
        switch self {
        case .setup(let m): "Video export setup failed: \(m)"
        case .writer(let m): "Video export failed: \(m)"
        }
    }
}

enum Pacing {
    /// Cumulative shape targets per active frame: monotone, each in 0...n,
    /// last exactly n. Frame i uses t = (i+1)/N, so a background-only first
    /// frame can fall out of easeIn naturally — that is intentional.
    static func cumulativeTargets(
        shapeCount n: Int,
        activeFrames N: Int,
        curve: PacingCurve,
        scores: [Double]
    ) -> [Int] {
        guard n > 0, N > 0 else { return Array(repeating: max(0, n), count: max(1, N)) }

        var targets = [Int]()
        targets.reserveCapacity(N)

        switch effectiveCurve(curve, shapeCount: n, scores: scores) {
        case .linear:
            for i in 0..<N {
                let t = Double(i + 1) / Double(N)
                targets.append(Int((t * Double(n)).rounded()))
            }
        case .easeIn:
            for i in 0..<N {
                let t = Double(i + 1) / Double(N)
                targets.append(Int((pow(t, 2.2) * Double(n)).rounded()))
            }
        case .scoreWeighted:
            // Equal score-improvement per frame. Shape 0's improvement is
            // unobservable (the pre-shape score isn't persisted); weight it
            // like the largest measured improvement — bounded and safe.
            var improvements = [Double](repeating: 0, count: n)
            for j in 1..<n {
                improvements[j] = max(0, scores[j - 1] - scores[j])
            }
            improvements[0] = improvements.max() ?? 1
            var cumulative = [Double]()
            cumulative.reserveCapacity(n)
            var sum = 0.0
            for imp in improvements {
                sum += imp
                cumulative.append(sum)
            }
            let total = sum
            for i in 0..<N {
                let want = Double(i + 1) / Double(N) * total
                targets.append(firstIndex(atLeast: want, in: cumulative) + 1)
            }
        }

        // Belt and braces: monotone, clamped, complete.
        for i in targets.indices {
            targets[i] = min(max(targets[i], i > 0 ? targets[i - 1] : 0), n)
        }
        targets[N - 1] = n
        return targets
    }

    private static func effectiveCurve(_ curve: PacingCurve, shapeCount n: Int, scores: [Double]) -> PacingCurve {
        guard curve == .scoreWeighted else { return curve }
        guard scores.count >= n, n > 1, scores.allSatisfy(\.isFinite) else { return .easeIn }
        var improves = false
        for j in 1..<n where scores[j - 1] > scores[j] {
            improves = true
            break
        }
        return improves ? .scoreWeighted : .easeIn
    }

    private static func firstIndex(atLeast value: Double, in sorted: [Double]) -> Int {
        var lo = 0
        var hi = sorted.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] >= value {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return lo
    }
}

enum VideoExporter {
    /// Encodes the shape history to a movie file. Runs off the main actor
    /// (nonisolated async); every AVFoundation object stays local. Progress
    /// lands on the main actor; cancellation deletes the partial file.
    static func export(
        data: ShapeDataPayload,
        settings: VideoExportSettings,
        to url: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        let n = data.shapes.count
        guard n > 0 else { throw VideoExportError.setup("no shapes to export") }

        let (vw, vh) = settings.size.renderSize(modelW: data.width, modelH: data.height)
        let fps = settings.fps
        let activeFrames = max(1, Int((settings.duration * Double(fps)).rounded()))
        let holdFrames = max(0, Int((settings.holdSeconds * Double(fps)).rounded()))
        let totalFrames = activeFrames + holdFrames
        let targets = Pacing.cumulativeTargets(
            shapeCount: n,
            activeFrames: activeFrames,
            curve: settings.pacing,
            scores: data.shapes.map { $0.s ?? 0 }
        )

        // Master context: BGRA little-endian to byte-match the pixel-buffer
        // pool (deliberately different from PreviewRenderer's RGBA).
        guard
            let srgb = CGColorSpace(name: CGColorSpace.sRGB),
            let master = CGContext(
                data: nil,
                width: vw,
                height: vh,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            let bg = ShapeDrawing.cgColor(data.background)
        else { throw VideoExportError.setup("could not create render context") }

        master.setFillColor(bg)
        master.fill(CGRect(x: 0, y: 0, width: vw, height: vh))
        let u = min(Double(vw) / Double(data.width), Double(vh) / Double(data.height))
        master.translateBy(x: 0, y: CGFloat(vh))
        master.scaleBy(x: 1, y: -1)
        master.translateBy(
            x: (CGFloat(vw) - CGFloat(data.width) * u) / 2,
            y: (CGFloat(vh) - CGFloat(data.height) * u) / 2
        )
        master.scaleBy(x: u, y: u)
        master.scaleBy(x: data.scale, y: data.scale)
        master.translateBy(x: 0.5, y: 0.5)
        master.setShouldAntialias(true)

        // Writer + input + adaptor.
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: settings.format.fileType)
        writer.shouldOptimizeForNetworkUse = true

        var output: [String: Any] = [
            AVVideoCodecKey: settings.format.codec,
            AVVideoWidthKey: vw,
            AVVideoHeightKey: vh,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        switch settings.format {
        case .h264:
            output[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: settings.format.bitrate(width: vw, height: vh, fps: fps),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoExpectedSourceFrameRateKey: fps,
            ]
        case .hevc:
            output[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: settings.format.bitrate(width: vw, height: vh, fps: fps),
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoExpectedSourceFrameRateKey: fps,
            ]
        case .prores:
            // ProRes takes NO compression properties — a bitrate key raises
            // an uncatchable exception at input creation.
            break
        }
        guard writer.canApply(outputSettings: output, forMediaType: .video) else {
            throw VideoExportError.setup("output settings rejected for \(settings.format.label)")
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: output)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: vw,
                kCVPixelBufferHeightKey as String: vh,
            ]
        )
        guard writer.canAdd(input) else {
            throw VideoExportError.setup("could not add video input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw VideoExportError.writer(writer.error?.localizedDescription ?? "could not start writing")
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            throw VideoExportError.setup("no pixel buffer pool (settings invalid?)")
        }

        func cleanupPartial() {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }

        var cursor = 0
        let timescale = CMTimeScale(fps)
        do {
            for frame in 0..<totalFrames {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(10))
                }
                try Task.checkCancellation()

                let target = frame < activeFrames ? targets[frame] : n
                while cursor < target {
                    ShapeDrawing.draw(data.shapes[cursor].record, in: master)
                    cursor += 1
                }

                var pbOut: CVPixelBuffer?
                guard
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut) == kCVReturnSuccess,
                    let pb = pbOut
                else { throw VideoExportError.writer("pixel buffer allocation failed") }

                CVPixelBufferLockBaseAddress(pb, [])
                if let src = master.data, let dst = CVPixelBufferGetBaseAddress(pb) {
                    let srcStride = master.bytesPerRow
                    let dstStride = CVPixelBufferGetBytesPerRow(pb)
                    let rowBytes = vw * 4
                    for row in 0..<vh {
                        memcpy(dst + row * dstStride, src + row * srcStride, rowBytes)
                    }
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
                CVBufferSetAttachment(pb, kCVImageBufferCGColorSpaceKey, srgb, .shouldPropagate)

                guard adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: timescale)) else {
                    throw VideoExportError.writer(writer.error?.localizedDescription ?? "frame append failed")
                }

                if frame % 3 == 0 || frame == totalFrames - 1 {
                    let fraction = Double(frame + 1) / Double(totalFrames)
                    await progress(fraction)
                }
            }
        } catch {
            cleanupPartial()
            throw error
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            let message = writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)"
            try? FileManager.default.removeItem(at: url)
            throw VideoExportError.writer(message)
        }
    }
}
