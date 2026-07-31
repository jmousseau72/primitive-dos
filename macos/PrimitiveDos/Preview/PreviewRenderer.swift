// Persistent incremental rasterizer for the live preview. Shapes are
// append-only, so each batch draws ONLY the new shapes into one long-lived
// CGBitmapContext and snapshots it — per-frame cost is O(new shapes), never
// O(total), which keeps 120k-shape runs as cheap as 100-shape runs.
//
// The context is transparent: the background color and the source underlay
// are separate SwiftUI layers beneath the shapes image, so the underlay
// toggle never touches the raster (source-over compositing is associative,
// making this pixel-equivalent to the engine's bg-filled canvas).

import CoreGraphics
import Foundation
import ImageIO

actor PreviewRenderer {
    private var ctx: CGContext?

    private static let maxDim: CGFloat = 2048

    /// Creates the backing context for a new render. The CTM replicates
    /// Model.SVG()'s `<g transform="scale(S) translate(0.5 0.5)">` on top of
    /// a top-left origin flip and the preview downscale — set once, so every
    /// ShapeRecord draws in raw shape-space coordinates.
    func begin(_ started: StartedPayload) -> CGImage? {
        let w = CGFloat(started.width)
        let h = CGFloat(started.height)
        let previewScale = min(1, Self.maxDim / max(w, h))
        let pw = max(1, Int(w * previewScale))
        let ph = max(1, Int(h * previewScale))

        guard let context = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(ph))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: previewScale, y: previewScale)
        context.scaleBy(x: started.scale, y: started.scale)
        context.translateBy(x: 0.5, y: 0.5)
        context.setShouldAntialias(true)

        ctx = context
        return context.makeImage()
    }

    func append(_ shapes: [ShapeRecord]) -> CGImage? {
        guard let ctx else { return nil }
        for shape in shapes {
            ShapeDrawing.draw(shape, in: ctx)
        }
        return ctx.makeImage()
    }

    /// Raster-fallback branch (previewMode "raster"). Native renders never
    /// trigger it — EmitShapeData disables the WKWebView-motivated flip —
    /// but the bridge contract keeps it total.
    func applySnapshot(jpegBase64: String) -> CGImage? {
        guard
            let data = Data(base64Encoded: jpegBase64),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func reset() {
        ctx = nil
    }
}
