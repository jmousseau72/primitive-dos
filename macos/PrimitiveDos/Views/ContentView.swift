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
                switch state.phase {
                case .running:
                    Button("Pause", systemImage: "pause.fill") { state.pause() }
                    Button("Stop", systemImage: "stop.fill") { state.stop() }
                case .paused:
                    Button("Resume", systemImage: "play.fill") { state.resume() }
                    Button("Stop", systemImage: "stop.fill") { state.stop() }
                default:
                    Button(state.phase == .done ? "Restart" : "Start", systemImage: "play.fill") {
                        state.start()
                    }
                    .disabled(!state.canStart)
                }
            }

            ToolbarItemGroup {
                Button("Underlay", systemImage: state.underlayVisible ? "eye.fill" : "eye") {
                    state.underlayVisible.toggle()
                }
                .disabled(state.phase == .empty)
                .help("Toggle the source-image underlay")

                Button("Export", systemImage: "square.and.arrow.up") {
                    state.runExport()
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { state.errorMessage != nil },
            set: { presented in
                if !presented { state.errorMessage = nil }
            }
        )
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
