import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showInspector = true
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearance.system.rawValue

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            PreviewView()
            if state.timelineVisible {
                TimelineBar()
                    .padding(.bottom, 6)
            }
            StatsBar()
        }
        .animation(.easeInOut(duration: 0.2), value: state.timelineVisible)
        .frame(minWidth: 560, minHeight: 480)
        .inspector(isPresented: $showInspector) {
            ControlsPanel()
                .inspectorColumnWidth(min: 320, ideal: 350, max: 440)
        }
        // Minimum applies to canvas + inspector together, so the window can
        // never shrink the canvas into a sliver under the panel.
        .frame(minWidth: 920, minHeight: 560)
        .toolbar {
            ToolbarItemGroup {
                Button("Open Image", systemImage: "photo.badge.plus") {
                    state.openImagePanel()
                }
                .disabled(state.isBusy)
                .help("Open an image (⌘O)")

                Button("Clear Image", systemImage: "arrow.3.trianglepath") {
                    state.clearImage()
                }
                .disabled(state.phase == .empty || state.isBusy)
                .help("Clear the image and start fresh (⌘⌫)")
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

                if state.phase == .done {
                    Button("Restart", systemImage: "arrow.counterclockwise") {
                        state.start()
                    }
                    .help("Start over from zero shapes")
                }
            }

            ToolbarItemGroup {
                Button("Underlay", systemImage: state.underlayVisible ? "eye.fill" : "eye") {
                    state.underlayVisible.toggle()
                }
                .disabled(state.phase == .empty)
                .help("Toggle the source-image underlay")

                Button {
                    state.toggleTimeline()
                } label: {
                    if state.timelineLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Timeline", systemImage: state.timelineVisible ? "clock.arrow.circlepath" : "clock")
                    }
                }
                .disabled(!state.canShowTimeline && !state.timelineVisible)
                .help("Scrub through the shape history")

                Button {
                    state.saveDocument()
                } label: {
                    Label {
                        Text("Save Document")
                    } icon: {
                        FloppyIcon()
                            .frame(width: 17, height: 17)
                    }
                }
                .disabled(!state.sessionStarted)
                .help("Save the render as a .prim document (⌘S)")

                Button {
                    state.runExport()
                } label: {
                    Label {
                        Text("Export")
                    } icon: {
                        ExportIcon()
                            .frame(width: 17, height: 17)
                    }
                }
                .disabled(!state.canExport)
                .help("Export images (⌘E)")
            }
        }
        .navigationTitle("Primitive Dos")
        .preferredColorScheme(AppAppearance(rawValue: appearanceMode)?.colorScheme)
        .background(WindowAccessor { window in
            state.installCloseGuard(on: window)
        })
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .sheet(isPresented: $state.showVideoExportSheet) {
            ExportVideoSheet()
        }
        .overlay(alignment: .center) {
            if let fraction = state.videoExportFraction {
                VStack(spacing: 12) {
                    Text("Exporting video…")
                        .font(.callout.weight(.semibold))
                    ProgressView(value: fraction)
                        .frame(width: 220)
                    Button("Cancel") {
                        state.cancelVideoExport()
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: .rect(cornerRadius: 14))
                .shadow(radius: 16, y: 4)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                ToastView(message: toast)
                    .padding(.bottom, 52)
                    // id: restarts the dismiss timer for each new message —
                    // without it a second toast inherits the first one's
                    // timer and never clears.
                    .task(id: toast) {
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
            // Continue keeps every shape and adds more with the current
            // settings (even a different mode); Restart is its own button.
            ("Continue", "play.fill", state.canContinue, { state.continueRender() })
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

/// Hands the hosting NSWindow to SwiftUI code (for the close-button guard).
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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

/// Export glyph: a panel with a right-pointing arrow, escaping a second
/// panel behind it — matching the mark Jason picked. 24×24 design space.
struct ExportIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24
            let stroke = StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round)

            let front = Path(
                roundedRect: CGRect(x: 3 * s, y: 8 * s, width: 12.5 * s, height: 13 * s),
                cornerRadius: 2 * s
            )
            let back = Path(
                roundedRect: CGRect(x: 8.5 * s, y: 3 * s, width: 12.5 * s, height: 13 * s),
                cornerRadius: 2 * s
            )

            // Back panel, hidden where the front panel overlaps.
            context.drawLayer { layer in
                layer.clip(to: front.strokedPath(StrokeStyle(lineWidth: 3.2 * s)).union(front), options: .inverse)
                layer.stroke(back, with: .color(.primary), style: stroke)
                var dash = Path()
                dash.move(to: CGPoint(x: 13 * s, y: 6 * s))
                dash.addLine(to: CGPoint(x: 17 * s, y: 6 * s))
                layer.stroke(dash, with: .color(.primary), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
            }

            context.stroke(front, with: .color(.primary), style: stroke)

            var arrow = Path()
            arrow.move(to: CGPoint(x: 6 * s, y: 14.5 * s))
            arrow.addLine(to: CGPoint(x: 12.2 * s, y: 14.5 * s))
            arrow.move(to: CGPoint(x: 9.9 * s, y: 12.1 * s))
            arrow.addLine(to: CGPoint(x: 12.4 * s, y: 14.5 * s))
            arrow.addLine(to: CGPoint(x: 9.9 * s, y: 16.9 * s))
            context.stroke(arrow, with: .color(.primary), style: stroke)
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
