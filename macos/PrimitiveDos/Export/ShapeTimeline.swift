// Interactive timeline over a session's shape history. Forward scrubbing
// draws incrementally; backward scrubbing restores the nearest of 16 evenly
// spaced checkpoint images and draws forward from there — so any position
// renders in at most n/16 shape draws.
//
// The scrub preview is capped at 1024px (it's a preview affordance);
// exporting a frame re-renders the prefix at full model resolution.

import CoreGraphics
import Foundation

actor ShapeTimeline {
    private let data: ShapeDataPayload
    private var ctx: CGContext?
    private var cursor = 0
    private var checkpoints: [Int: CGImage] = [:]
    private let checkpointStride: Int

    var shapeCount: Int { data.shapes.count }

    init(data: ShapeDataPayload) {
        self.data = data
        let n = max(1, data.shapes.count)
        self.checkpointStride = max(1, n / 16)
    }

    /// Builds the preview context and checkpoint cache in one forward pass.
    /// O(n) draw work, done once on activation.
    func prepare() {
        let context = Self.makeContext(
            modelW: data.width,
            modelH: data.height,
            scale: data.scale,
            maxDim: 1024
        )
        ctx = context
        cursor = 0
        checkpoints = [:]
        guard let context else { return }
        for (i, shape) in data.shapes.enumerated() {
            ShapeDrawing.draw(shape.record, in: context)
            cursor = i + 1
            if cursor % checkpointStride == 0 || cursor == data.shapes.count {
                if let image = context.makeImage() {
                    checkpoints[cursor] = image
                }
            }
        }
    }

    /// Renders the preview at an arbitrary position, restoring the nearest
    /// checkpoint at or below it when moving backward.
    func frame(at position: Int) -> CGImage? {
        guard let ctx else { return nil }
        let target = min(max(0, position), data.shapes.count)

        if target < cursor {
            // Backward: restore nearest checkpoint ≤ target, or blank.
            let base = checkpoints.keys.filter { $0 <= target }.max() ?? 0
            ctx.saveGState()
            ctx.concatenate(ctx.ctm.inverted()) // device space
            ctx.clear(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
            if base > 0, let image = checkpoints[base] {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
            }
            ctx.restoreGState()
            cursor = base
        }
        while cursor < target {
            ShapeDrawing.draw(data.shapes[cursor].record, in: ctx)
            cursor += 1
        }
        return ctx.makeImage()
    }

    /// Full-resolution render of the prefix, for "Export This Frame".
    func renderFull(at position: Int, background: Bool = true) -> CGImage? {
        guard let context = Self.makeContext(
            modelW: data.width,
            modelH: data.height,
            scale: data.scale,
            maxDim: nil,
            background: background ? data.background : nil
        ) else { return nil }
        let target = min(max(0, position), data.shapes.count)
        for i in 0..<target {
            ShapeDrawing.draw(data.shapes[i].record, in: context)
        }
        return context.makeImage()
    }

    var backgroundHex: String { data.background }

    /// SVG document of the prefix — same output the Go engine would produce
    /// for these shapes.
    func svgDocument(at position: Int, includeBackground: Bool = true) -> String {
        let target = min(max(0, position), data.shapes.count)
        return SVGAssembler.svg(
            shapes: data.shapes[0..<target],
            width: data.width,
            height: data.height,
            scale: data.scale,
            background: data.background,
            includeBackground: includeBackground
        )
    }

    /// Full-resolution composite: background color, then the source image at
    /// reduced opacity, then the shape prefix on top — the "sketch over the
    /// photo" effect, baked into one image.
    func renderComposite(
        at position: Int,
        source: CGImage,
        sourceOpacity: Double
    ) -> CGImage? {
        let pw = data.width
        let ph = data.height
        guard let context = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        if let bg = ShapeDrawing.cgColor(data.background) {
            context.setFillColor(bg)
            context.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        }
        context.saveGState()
        context.setAlpha(CGFloat(min(max(sourceOpacity, 0), 1)))
        context.draw(source, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        context.restoreGState()

        context.translateBy(x: 0, y: CGFloat(ph))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: data.scale, y: data.scale)
        context.translateBy(x: 0.5, y: 0.5)
        context.setShouldAntialias(true)
        let target = min(max(0, position), data.shapes.count)
        for i in 0..<target {
            ShapeDrawing.draw(data.shapes[i].record, in: context)
        }
        return context.makeImage()
    }

    /// Shared context recipe: same transform stack as the preview/video.
    private static func makeContext(
        modelW: Int,
        modelH: Int,
        scale: Double,
        maxDim: CGFloat?,
        background: String? = nil
    ) -> CGContext? {
        let w = CGFloat(modelW)
        let h = CGFloat(modelH)
        let fit = maxDim.map { min(1, $0 / max(w, h)) } ?? 1
        let pw = max(1, Int(w * fit))
        let ph = max(1, Int(h * fit))
        guard let context = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        if let background, let bg = ShapeDrawing.cgColor(background) {
            context.setFillColor(bg)
            context.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        }
        context.translateBy(x: 0, y: CGFloat(ph))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: fit, y: fit)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0.5, y: 0.5)
        context.setShouldAntialias(true)
        return context
    }
}
