import AppKit
import SwiftUI

@main
struct PrimitiveDosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .task {
                    state.startEventPump()
                    appDelegate.state = state
                }
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") {
                    state.openImagePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(state.isBusy)

                Button("Clear Image") {
                    state.clearImage()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state.phase == .empty || state.isBusy)

                Divider()

                Button("Import Presets…") {
                    state.importPresets()
                }
                Button("Export Presets…") {
                    state.exportPresets()
                }
            }
            CommandGroup(after: .saveItem) {
                Button("Save Document…") {
                    state.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!state.sessionStarted)

                Button("Export…") {
                    state.runExport()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!state.canExport)

                Button("Export Video…") {
                    state.showVideoExportSheet = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!state.canExportVideo)

                Button(state.phase == .paused ? "Resume" : "Pause") {
                    state.phase == .paused ? state.resume() : state.pause()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!state.isBusy)

                Button("Continue Rendering") {
                    state.continueRender()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!state.canContinue)

                Button("Stop Render") {
                    state.stop()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!state.isBusy)
            }
            CommandGroup(before: .toolbar) {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance.rawValue)
                    }
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Cancels any active render and closes the engine's event stream on quit;
/// receives Finder open requests for .prim documents and images; guards
/// unsaved work on the way out.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var state: AppState?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let state, !state.confirmDiscardOrSave() {
            return .terminateCancel
        }
        state?.shutdown()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let state, let url = urls.first else { return }
        Task { await state.open(url: url) }
    }
}
