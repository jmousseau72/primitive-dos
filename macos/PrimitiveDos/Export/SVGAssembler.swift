// Assembles an SVG document from shape records, mirroring the Go engine's
// Model.SVG() output element-for-element (internal/primitive/*.go SVG
// methods), so a frame exported at a scrub position matches what a full
// Go-side export of the same prefix would produce.

import Foundation

enum SVGAssembler {
    static func svg(
        shapes: ArraySlice<ScoredShapeRecord>,
        width: Int,
        height: Int,
        scale: Double,
        background: String,
        includeBackground: Bool = true
    ) -> String {
        var lines = [String]()
        lines.reserveCapacity(shapes.count + 4)
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"\(width)\" height=\"\(height)\">")
        if includeBackground {
            let bg = background.hasPrefix("#") ? String(background.dropFirst()) : background
            lines.append("<rect x=\"0\" y=\"0\" width=\"\(width)\" height=\"\(height)\" fill=\"#\(bg)\" />")
        }
        lines.append("<g transform=\"scale(\(fmt(scale))) translate(0.5 0.5)\">")
        for shape in shapes {
            if let element = element(for: shape) {
                lines.append(element)
            }
        }
        lines.append("</g>")
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    private static func element(for shape: ScoredShapeRecord) -> String? {
        let p = shape.p
        guard shape.c.count >= 8 else { return nil }
        let rgb = String(shape.c.prefix(6))
        let alphaHex = String(shape.c.dropFirst(6))
        let alpha = Double(UInt8(alphaHex, radix: 16) ?? 255) / 255
        let attrs = "fill=\"#\(rgb)\" fill-opacity=\"\(fmt(alpha))\""

        switch shape.t {
        case "tri":
            guard p.count >= 6 else { return nil }
            let pts = "\(Int(p[0])),\(Int(p[1])) \(Int(p[2])),\(Int(p[3])) \(Int(p[4])),\(Int(p[5]))"
            return "<polygon \(attrs) points=\"\(pts)\" />"
        case "rect":
            guard p.count >= 4 else { return nil }
            let x1 = Int(min(p[0], p[2])), x2 = Int(max(p[0], p[2]))
            let y1 = Int(min(p[1], p[3])), y2 = Int(max(p[1], p[3]))
            return "<rect \(attrs) x=\"\(x1)\" y=\"\(y1)\" width=\"\(x2 - x1 + 1)\" height=\"\(y2 - y1 + 1)\" />"
        case "rrect":
            guard p.count >= 5 else { return nil }
            return "<g transform=\"translate(\(Int(p[0])) \(Int(p[1]))) rotate(\(Int(p[4]))) scale(\(Int(p[2])) \(Int(p[3])))\"><rect \(attrs) x=\"-0.5\" y=\"-0.5\" width=\"1\" height=\"1\" /></g>"
        case "ell":
            guard p.count >= 4 else { return nil }
            return "<ellipse \(attrs) cx=\"\(Int(p[0]))\" cy=\"\(Int(p[1]))\" rx=\"\(Int(p[2]))\" ry=\"\(Int(p[3]))\" />"
        case "rell":
            guard p.count >= 5 else { return nil }
            return "<g transform=\"translate(\(fmt(p[0])) \(fmt(p[1]))) rotate(\(fmt(p[4]))) scale(\(fmt(p[2])) \(fmt(p[3])))\"><ellipse \(attrs) cx=\"0\" cy=\"0\" rx=\"1\" ry=\"1\" /></g>"
        case "quad":
            guard p.count >= 6 else { return nil }
            // The engine strokes beziers: fill attrs become stroke attrs.
            let strokeAttrs = "stroke=\"#\(rgb)\" stroke-opacity=\"\(fmt(alpha))\""
            let d = "M \(fmt(p[0])) \(fmt(p[1])) Q \(fmt(p[2])) \(fmt(p[3])), \(fmt(p[4])) \(fmt(p[5]))"
            return "<path \(strokeAttrs) fill=\"none\" d=\"\(d)\" stroke-width=\"\(fmt(shape.w ?? 0.5))\" />"
        case "poly":
            guard p.count >= 6, p.count % 2 == 0 else { return nil }
            var pts = [String]()
            var i = 0
            while i + 1 < p.count {
                pts.append("\(fmt(p[i])),\(fmt(p[i + 1]))")
                i += 2
            }
            return "<polygon \(attrs) points=\"\(pts.joined(separator: ","))\" />"
        default:
            return nil
        }
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%f", value)
    }
}
