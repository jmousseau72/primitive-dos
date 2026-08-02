import SwiftUI
import UniformTypeIdentifiers

struct PreviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.phase == .empty {
                DropZone()
            } else {
                canvas
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await state.open(url: url) }
            return true
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                // Layered like the web app: background color (or underlay),
                // then the transparent shapes raster on top.
                if state.underlayVisible, let source = state.sourceImage {
                    Image(nsImage: source)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .opacity(state.underlayOpacity)
                        .grayscale(state.underlayColorful ? 0 : 0.5)
                } else if state.transparentBackground {
                    CheckerboardRect()
                } else if let bg = state.started?.background, let color = Color(hex: bg) {
                    ContentAspectRect(color: color)
                }
                if let image = state.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(brushGesture(in: geo.size))
        }
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
        .padding()
    }

    // Maps pointer positions through the aspect-fit letterbox into
    // input-image coordinates for the drawing-mode brush.
    private func brushGesture(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard state.isDrawingRun, let point = imagePoint(for: value.location, in: viewSize) else { return }
                state.brushMoved(to: point, active: true)
            }
            .onEnded { _ in
                guard state.runMode == .draw else { return }
                state.brushMoved(to: .zero, active: false)
            }
    }

    private func imagePoint(for location: CGPoint, in viewSize: CGSize) -> CGPoint? {
        guard let started = state.started, started.width > 0, started.height > 0 else { return nil }
        let aspect = CGFloat(started.width) / CGFloat(started.height)
        var content = CGRect(origin: .zero, size: viewSize)
        if viewSize.width / viewSize.height > aspect {
            content.size.width = viewSize.height * aspect
            content.origin.x = (viewSize.width - content.size.width) / 2
        } else {
            content.size.height = viewSize.width / aspect
            content.origin.y = (viewSize.height - content.size.height) / 2
        }
        let fx = (location.x - content.minX) / content.width
        let fy = (location.y - content.minY) / content.height
        guard (0...1).contains(fx), (0...1).contains(fy) else { return nil }
        return CGPoint(x: fx * CGFloat(started.inputW), y: fy * CGFloat(started.inputH))
    }
}

/// A colored rectangle matching the render's aspect ratio inside the
/// aspect-fit layout, standing in for the SVG background rect.
private struct ContentAspectRect: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .aspectRatio(contentMode: .fit)
    }
}

/// Classic transparency checkerboard, shown when exports will omit the
/// background so the preview reads as "shapes on alpha".
private struct CheckerboardRect: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 0 {
                    context.fill(
                        Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                        with: .color(.gray.opacity(0.25))
                    )
                }
            }
        }
        .background(Color.gray.opacity(0.1))
        .aspectRatio(contentMode: .fit)
    }
}

private struct DropZone: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            DropIcon()
                .frame(width: 64, height: 64)
            Text("Drop an image here")
                .font(.title3.weight(.semibold))
            Text("PNG, JPEG, GIF, BMP, TIFF or WebP")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Browse…") {
                state.openImagePanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(.quaternary)
                .padding(40)
        }
    }
}

/// The shapes mark from the Wails app's drop zone (frontend/index.html):
/// a stroked triangle, a soft filled circle, and a faint rounded square,
/// drawn in the same 24×24 design space.
private struct DropIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24

            var triangle = Path()
            triangle.move(to: CGPoint(x: 12 * s, y: 3 * s))
            triangle.addLine(to: CGPoint(x: 20 * s, y: 17 * s))
            triangle.addLine(to: CGPoint(x: 4 * s, y: 17 * s))
            triangle.closeSubpath()
            context.stroke(
                triangle,
                with: .color(.secondary.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.2 * s, lineJoin: .round)
            )

            let circle = Path(ellipseIn: CGRect(x: 13 * s, y: 4 * s, width: 8 * s, height: 8 * s))
            context.fill(circle, with: .color(.secondary.opacity(0.35)))

            let square = Path(
                roundedRect: CGRect(x: 4 * s, y: 13 * s, width: 7 * s, height: 7 * s),
                cornerRadius: 1 * s
            )
            context.fill(square, with: .color(.secondary.opacity(0.2)))
        }
    }
}
