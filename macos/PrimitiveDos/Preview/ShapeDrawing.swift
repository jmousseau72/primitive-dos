// Draws ShapeRecords (internal/session/shapedata.go) into a CGContext whose
// CTM is already in model shape-space. Each case mirrors the corresponding
// Shape.SVG()/Draw() in internal/primitive exactly.

import CoreGraphics
import Foundation

enum ShapeDrawing {
    static func draw(_ rec: ShapeRecord, in ctx: CGContext) {
        guard let color = cgColor(rec.c) else { return }
        let p = rec.p
        switch rec.t {
        case "tri":
            guard p.count >= 6 else { return }
            ctx.setFillColor(color)
            ctx.move(to: CGPoint(x: p[0], y: p[1]))
            ctx.addLine(to: CGPoint(x: p[2], y: p[3]))
            ctx.addLine(to: CGPoint(x: p[4], y: p[5]))
            ctx.closePath()
            ctx.fillPath()

        case "rect":
            guard p.count >= 4 else { return }
            // Raw corners; normalize like Rectangle.bounds(), then the
            // engine's inclusive-pixel +1 sizing.
            let x1 = min(p[0], p[2]), x2 = max(p[0], p[2])
            let y1 = min(p[1], p[3]), y2 = max(p[1], p[3])
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: x1, y: y1, width: x2 - x1 + 1, height: y2 - y1 + 1))

        case "rrect":
            guard p.count >= 5 else { return }
            ctx.saveGState()
            ctx.translateBy(x: p[0], y: p[1])
            ctx.rotate(by: p[4] * .pi / 180)
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: -p[2] / 2, y: -p[3] / 2, width: p[2], height: p[3]))
            ctx.restoreGState()

        case "ell":
            guard p.count >= 4 else { return }
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: p[0] - p[2], y: p[1] - p[3], width: p[2] * 2, height: p[3] * 2))

        case "rell":
            guard p.count >= 5 else { return }
            ctx.saveGState()
            ctx.translateBy(x: p[0], y: p[1])
            ctx.rotate(by: p[4] * .pi / 180)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: -p[2], y: -p[3], width: p[2] * 2, height: p[3] * 2))
            ctx.restoreGState()

        case "quad":
            guard p.count >= 6 else { return }
            ctx.setStrokeColor(color)
            // Width is in shape-space; the CTM scales it, matching the
            // engine's q.Width * scale. Round caps match gg's rasterizer.
            ctx.setLineWidth(rec.w ?? 0.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: p[0], y: p[1]))
            ctx.addQuadCurve(to: CGPoint(x: p[4], y: p[5]), control: CGPoint(x: p[2], y: p[3]))
            ctx.strokePath()

        case "poly":
            guard p.count >= 6 else { return }
            ctx.setFillColor(color)
            ctx.move(to: CGPoint(x: p[0], y: p[1]))
            var i = 2
            while i + 1 < p.count {
                ctx.addLine(to: CGPoint(x: p[i], y: p[i + 1]))
                i += 2
            }
            ctx.closePath()
            ctx.fillPath()

        default:
            break
        }
    }

    /// Parses "rrggbbaa" (see makeShapeRecord) or "#rrggbb" (started-payload
    /// background) into a CGColor.
    static func cgColor(_ hex: String) -> CGColor? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let bits = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((bits >> 24) & 0xff) / 255
            g = CGFloat((bits >> 16) & 0xff) / 255
            b = CGFloat((bits >> 8) & 0xff) / 255
            a = CGFloat(bits & 0xff) / 255
        } else {
            r = CGFloat((bits >> 16) & 0xff) / 255
            g = CGFloat((bits >> 8) & 0xff) / 255
            b = CGFloat(bits & 0xff) / 255
            a = 1
        }
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
