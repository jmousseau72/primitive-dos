import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showInspector = true
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearance.system.rawValue

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            PreviewView()
            StatsBar()
        }
        .frame(minWidth: 620, minHeight: 480)
        .inspector(isPresented: $showInspector) {
            ControlsPanel()
                .inspectorColumnWidth(min: 280, ideal: 310, max: 380)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Open Image", systemImage: "photo.badge.plus") {
                    state.openImagePanel()
                }
                .disabled(state.isBusy)
                .help("Open an image (⌘O)")
            }

            ToolbarItemGroup {
                // One play/pause toggle that always reflects the current
                // state, plus a separate, always-present stop button.
                Button(playPause.label, systemImage: playPause.symbol) {
                    playPause.action()
                }
                .disabled(!playPause.enabled)
                .help(playPause.label)

                Button("Stop", systemImage: "stop.fill") {
                    state.stop()
                }
                .disabled(!state.isBusy)
                .help("Stop the render (⌘.) — you can still export")
            }

            ToolbarItemGroup {
                Button("Underlay", systemImage: state.underlayVisible ? "eye.fill" : "eye") {
                    state.underlayVisible.toggle()
                }
                .disabled(state.phase == .empty)
                .help("Toggle the source-image underlay")

                Button {
                    state.runExport()
                } label: {
                    Label {
                        Text("Export")
                    } icon: {
                        FloppyIcon()
                            .frame(width: 17, height: 17)
                    }
                }
                .disabled(!state.canExport)
                .help("Export the current result (⌘E)")
            }
        }
        .navigationTitle("Primitive Dos")
        .preferredColorScheme(AppAppearance(rawValue: appearanceMode)?.colorScheme)
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                ToastView(message: toast)
                    .padding(.bottom, 52)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        if state.toast == toast { state.toast = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
    }

    private var playPause: (label: String, symbol: String, enabled: Bool, action: () -> Void) {
        switch state.phase {
        case .running:
            ("Pause", "pause.fill", true, { state.pause() })
        case .paused:
            ("Resume", "play.fill", true, { state.resume() })
        case .done:
            ("Restart", "play.fill", true, { state.start() })
        case .loaded:
            ("Start", "play.fill", true, { state.start() })
        case .empty:
            ("Start", "play.fill", false, {})
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { state.errorMessage != nil },
            set: { presented in
                if !presented { state.errorMessage = nil }
            }
        )
    }
}

/// A floppy-disk save glyph (SF Symbols has no floppy), drawn in the same
/// 24×24 design space as the drop-zone mark.
struct FloppyIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24
            let stroke = StrokeStyle(lineWidth: 1.6 * s, lineJoin: .round)

            // Body with the clipped top-right corner.
            var body = Path()
            body.move(to: CGPoint(x: 4.5 * s, y: 3 * s))
            body.addLine(to: CGPoint(x: 16.5 * s, y: 3 * s))
            body.addLine(to: CGPoint(x: 21 * s, y: 7.5 * s))
            body.addLine(to: CGPoint(x: 21 * s, y: 19.5 * s))
            body.addQuadCurve(
                to: CGPoint(x: 19.5 * s, y: 21 * s),
                control: CGPoint(x: 21 * s, y: 21 * s)
            )
            body.addLine(to: CGPoint(x: 4.5 * s, y: 21 * s))
            body.addQuadCurve(
                to: CGPoint(x: 3 * s, y: 19.5 * s),
                control: CGPoint(x: 3 * s, y: 21 * s)
            )
            body.addLine(to: CGPoint(x: 3 * s, y: 4.5 * s))
            body.addQuadCurve(
                to: CGPoint(x: 4.5 * s, y: 3 * s),
                control: CGPoint(x: 3 * s, y: 3 * s)
            )
            body.closeSubpath()
            context.stroke(body, with: .color(.primary), style: stroke)

            // Shutter.
            let shutter = Path(CGRect(x: 8 * s, y: 3 * s, width: 8 * s, height: 5.5 * s))
            context.stroke(shutter, with: .color(.primary), style: StrokeStyle(lineWidth: 1.3 * s))

            // Label.
            let label = Path(CGRect(x: 7 * s, y: 13 * s, width: 10 * s, height: 8 * s))
            context.stroke(label, with: .color(.primary), style: StrokeStyle(lineWidth: 1.3 * s))
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: .capsule)
            .shadow(radius: 8, y: 3)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
