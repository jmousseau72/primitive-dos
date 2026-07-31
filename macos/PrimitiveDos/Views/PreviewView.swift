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
            Task { await state.loadImage(url: url) }
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
                        .opacity(0.3)
                        .grayscale(0.5)
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

private struct DropZone: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
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
