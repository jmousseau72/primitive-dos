import SwiftUI

/// Options for the "watch it draw itself" video export.
struct ExportVideoSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker("Format", selection: $state.videoSettings.format) {
                    ForEach(VideoExportFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                Picker("Size", selection: $state.videoSettings.size) {
                    ForEach(VideoSizePreset.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                Picker("Frame rate", selection: $state.videoSettings.fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                LabeledContent("Duration") {
                    HStack {
                        Slider(value: $state.videoSettings.duration, in: 2...60)
                            .controlSize(.mini)
                            .frame(width: 140)
                        Text("\(Int(state.videoSettings.duration))s")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                LabeledContent("Hold last frame") {
                    HStack {
                        Slider(value: $state.videoSettings.holdSeconds, in: 0...5)
                            .controlSize(.mini)
                            .frame(width: 140)
                        Text("\(Int(state.videoSettings.holdSeconds))s")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Picker("Pacing", selection: $state.videoSettings.pacing) {
                    ForEach(PacingCurve.allCases) { curve in
                        Text(curve.label).tag(curve)
                    }
                }
                .help("Slow start lingers on the first strokes; Even progress paces by score improvement")

                Text(estimate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Export…") {
                    dismiss()
                    // Let the sheet fully dismiss before the save panel runs.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        state.beginVideoExport()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 380)
        .fixedSize()
    }

    private var estimate: String {
        guard let started = state.started else { return "" }
        let s = state.videoSettings
        let (w, h) = s.size.renderSize(modelW: started.width, modelH: started.height)
        let bytes = s.format.estimatedBytes(width: w, height: h, fps: s.fps, seconds: s.duration + s.holdSeconds)
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return "\(w) × \(h) · about \(size)"
    }
}
