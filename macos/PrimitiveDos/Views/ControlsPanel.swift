import SwiftUI

struct ControlsPanel: View {
    @Environment(AppState.self) private var state
    @State private var newPresetName = ""
    @State private var showSavePreset = false

    // Collapsible sections, remembered across launches.
    @AppStorage("panel.presets") private var presetsExpanded = true
    @AppStorage("panel.run") private var runExpanded = true
    @AppStorage("panel.shapes") private var shapesExpanded = true
    @AppStorage("panel.size") private var sizeExpanded = false
    @AppStorage("panel.color") private var colorExpanded = false
    @AppStorage("panel.advanced") private var advancedExpanded = false
    @AppStorage("panel.export") private var exportExpanded = true

    var body: some View {
        Form {
            group("Presets", isExpanded: $presetsExpanded, locked: true) {
                presetRows
            }
            group("Run", isExpanded: $runExpanded, locked: true) {
                runRows
            }
            group("Shapes", isExpanded: $shapesExpanded, locked: true) {
                shapeRows
            }
            group("Size", isExpanded: $sizeExpanded, locked: true) {
                sizeRows
            }
            group("Color", isExpanded: $colorExpanded, locked: true) {
                colorRows
            }
            group("Advanced", isExpanded: $advancedExpanded, locked: true) {
                advancedRows
            }
            // Export formats stay live: exporting mid-run is supported.
            group("Export formats", isExpanded: $exportExpanded, locked: false) {
                @Bindable var state = state
                FormatToggles(formats: $state.exportFormats, options: ["png", "jpg", "svg", "gif"])
            }
        }
        .formStyle(.grouped)
    }

    /// One collapsible sidebar group. The disclosure chevron always works;
    /// when `locked` and a render is running, the rows inside dim and
    /// disable.
    private func group(
        _ title: String,
        isExpanded: Binding<Bool>,
        locked: Bool,
        @ViewBuilder rows: @escaping () -> some View
    ) -> some View {
        let dimmed = locked && state.isBusy
        return Section {
            DisclosureGroup(isExpanded: isExpanded) {
                rows()
                    .disabled(dimmed)
                    .opacity(dimmed ? 0.45 : 1)
            } label: {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(dimmed ? .secondary : .primary)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var presetRows: some View {
        @Bindable var state = state
        Picker("Preset", selection: $state.selectedPreset) {
            Text("Choose…").tag("")
            let builtIn = state.presets.filter(\.builtIn)
            let custom = state.presets.filter { !$0.builtIn }
            Section("Built-in") {
                ForEach(builtIn) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            if !custom.isEmpty {
                Section("Custom") {
                    ForEach(custom) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
            }
        }
        .labelsHidden()
        .onChange(of: state.selectedPreset) {
            if !state.selectedPreset.isEmpty {
                state.applyPreset(named: state.selectedPreset)
            }
        }
        HStack {
            Button("Save as Preset…") {
                showSavePreset = true
            }
            .popover(isPresented: $showSavePreset, arrowEdge: .bottom) {
                HStack {
                    TextField("Preset name", text: $newPresetName)
                        .frame(width: 180)
                        .onSubmit(savePreset)
                    Button("Save", action: savePreset)
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
            Spacer()
            if let current = state.presets.first(where: { $0.name == state.selectedPreset }), !current.builtIn {
                Button("Delete", role: .destructive) {
                    state.deletePreset(named: current.name)
                }
            }
        }
    }

    @ViewBuilder
    private var runRows: some View {
        @Bindable var state = state
        Picker("Run", selection: $state.runMode) {
            ForEach(RunMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        if state.runMode == .score {
            HStack {
                Text("Target")
                TextField("Similarity", value: $state.targetScore, format: .number.precision(.fractionLength(1)))
                    .frame(width: 64)
                Text("% similar")
                    .foregroundStyle(.secondary)
            }
        }
        if state.runMode == .draw {
            Text("Paint on the canvas while running — shapes appear under your brush.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var shapeRows: some View {
        @Bindable var state = state
        ModeGrid(selection: $state.mode)
        LabeledContent("Count") {
            TextField("Shapes", value: $state.shapeCount, format: .number.grouping(.never))
                .frame(width: 80)
        }
        LogSlider(value: $state.shapeCount, range: 10...120_000)
        autoRow("Opacity", auto: $state.alphaAuto) {
            // No step: — stepped sliders draw tick marks, which smear into a
            // ghost line at 255 stops. Quantize in the binding instead.
            Slider(
                value: Binding(
                    get: { state.alpha },
                    set: { state.alpha = $0.rounded() }
                ),
                in: 1...255
            ) {
                Text("Opacity")
            } minimumValueLabel: {
                Text("1").font(.caption2)
            } maximumValueLabel: {
                Text("255").font(.caption2)
            }
            .labelsHidden()
            .controlSize(.small)
        }
        autoRow("Stroke width", auto: $state.strokeAuto) {
            Slider(
                value: Binding(
                    get: { state.strokeWidth },
                    set: { state.strokeWidth = ($0 / 0.25).rounded() * 0.25 }
                ),
                in: 0.25...8
            ) {
                Text("Stroke width")
            } minimumValueLabel: {
                Text("¼").font(.caption2)
            } maximumValueLabel: {
                Text("8").font(.caption2)
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .help("Bezier stroke width — thicker is more painterly")
        LabeledContent("Repeat") {
            Stepper(value: $state.repeatCount, in: 0...16) {
                Text("\(state.repeatCount)")
                    .monospacedDigit()
            }
            .help("Extra shapes per iteration with reduced search")
        }
    }

    @ViewBuilder
    private var sizeRows: some View {
        @Bindable var state = state
        Toggle("Full-resolution input", isOn: $state.inputFullRes)
        if !state.inputFullRes {
            LabeledContent("Resize input to") {
                TextField("Pixels", value: $state.inputResize, format: .number.grouping(.never))
                    .frame(width: 70)
            }
        }
        Toggle("Output matches input size", isOn: $state.outputMatchInput)
        if !state.outputMatchInput {
            LabeledContent("Output size") {
                TextField("Pixels", value: $state.outputSize, format: .number.grouping(.never))
                    .frame(width: 70)
            }
        }
    }

    @ViewBuilder
    private var colorRows: some View {
        @Bindable var state = state
        Toggle("Average background", isOn: $state.bgAuto)
        if !state.bgAuto {
            ColorPicker("Background", selection: $state.bgColor, supportsOpacity: false)
        }
    }

    @ViewBuilder
    private var advancedRows: some View {
        @Bindable var state = state
        Toggle("Use all CPU cores", isOn: $state.workersAll)
        if !state.workersAll {
            LabeledContent("Workers") {
                Stepper(value: $state.workers, in: 1...64) {
                    Text("\(state.workers)")
                        .monospacedDigit()
                }
            }
        }
        Toggle("Save checkpoints", isOn: $state.checkpointsOn)
        if state.checkpointsOn {
            LabeledContent("Every") {
                HStack(spacing: 4) {
                    TextField("N", value: $state.checkpointNth, format: .number.grouping(.never))
                        .frame(width: 56)
                    Text("shapes")
                        .foregroundStyle(.secondary)
                }
            }
            FormatToggles(formats: $state.checkpointFormats, options: ["png", "jpg", "svg"])
            LabeledContent("Folder") {
                Button(state.checkpointDir.isEmpty ? "Choose…" : folderName(state.checkpointDir)) {
                    if let dir = AppState.chooseDirectory(title: "Choose Checkpoint Folder") {
                        state.checkpointDir = dir
                    }
                }
            }
        }
        DisclosureGroup("Stages") {
            Text("One stage per line: count, mode, alpha, repeat. Overrides the settings above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $state.stagesText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 56)
        }
    }

    // MARK: - Helpers

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        state.saveCurrentAsPreset(named: name)
        newPresetName = ""
        showSavePreset = false
    }

    private func folderName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func autoRow(
        _ title: String,
        auto: Binding<Bool>,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Toggle("Auto", isOn: auto)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            control()
                .disabled(auto.wrappedValue)
        }
    }
}

/// 3×3 grid of shape modes, bezier first and prominent.
private struct ModeGrid: View {
    @Binding var selection: Int

    private static let modes: [(mode: Int, name: String, symbol: String)] = [
        (6, "Bezier", "scribble.variable"),
        (1, "Triangle", "triangle"),
        (8, "Polygon", "pentagon"),
        (2, "Rect", "square"),
        (5, "Rect ∠", "rhombus"),
        (3, "Ellipse", "oval"),
        (7, "Ellipse ∠", "oval.portrait"),
        (4, "Circle", "circle"),
        (0, "Combo", "square.on.circle"),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(Self.modes, id: \.mode) { entry in
                Button {
                    selection = entry.mode
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: entry.symbol)
                            .font(.system(size: 16))
                        Text(entry.name)
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        selection == entry.mode ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: .rect(cornerRadius: 6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selection == entry.mode ? Color.accentColor : Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FormatToggles: View {
    @Binding var formats: Set<String>
    let options: [String]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(options, id: \.self) { format in
                Toggle(format.uppercased(), isOn: Binding(
                    get: { formats.contains(format) },
                    set: { on in
                        if on {
                            formats.insert(format)
                        } else {
                            formats.remove(format)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}

/// Logarithmic slider for the shape count (10 … 120k feels linear-ish).
private struct LogSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Double>

    var body: some View {
        Slider(
            value: Binding(
                get: {
                    let clamped = min(max(Double(value), range.lowerBound), range.upperBound)
                    return log(clamped / range.lowerBound) / log(range.upperBound / range.lowerBound)
                },
                set: { t in
                    let raw = range.lowerBound * pow(range.upperBound / range.lowerBound, t)
                    let step: Double = raw < 100 ? 10 : raw < 1000 ? 50 : raw < 10000 ? 100 : 1000
                    value = Int((raw / step).rounded() * step)
                }
            ),
            in: 0...1
        ) {
            Text("Shape count")
        }
        .labelsHidden()
        .controlSize(.small)
    }
}
