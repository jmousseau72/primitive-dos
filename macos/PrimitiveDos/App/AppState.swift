// Central state machine, mirroring the Wails frontend's rules
// (frontend/src/main.ts): Start hides while running/paused and reads
// "Restart" when done; Export is live from the first started event onward
// (mid-run export is safe — the Go side locks the model between steps);
// controls disable while running; loading a new image requires stopping.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    enum Phase {
        case empty, loaded, running, paused, done
    }

    // MARK: - Session state

    private(set) var phase: Phase = .empty
    private(set) var inputInfo: InputInfo?
    private(set) var sourceImage: NSImage?
    private(set) var sessionId = ""
    private(set) var sessionStarted = false
    private(set) var started: StartedPayload?
    private(set) var previewImage: CGImage?

    private(set) var shapesDone = 0
    private(set) var totalShapes = 0
    private(set) var score = 0.0
    private(set) var shapesPerSec = 0.0
    private(set) var elapsedMs = 0

    var underlayVisible = false
    var toast: String?
    var errorMessage: String?
    var isExporting = false
    var showExportSheet = false

    // MARK: - Controls (built into EngineParams at start)

    var mode = 6
    var shapeCount = 2000
    var alphaAuto = false
    var alpha = 255.0
    var strokeAuto = false
    var strokeWidth = 0.5
    var repeatCount = 0
    var inputFullRes = true
    var inputResize = 256
    var outputMatchInput = false
    var outputSize = 1024
    var bgAuto = true
    var bgColor = Color.black
    var workersAll = true
    var workers = 8
    var runMode: RunMode = .count
    var targetScore = 95.0
    var checkpointsOn = false
    var checkpointNth = 100
    var checkpointDir = ""
    var checkpointFormats: Set<String> = ["png"]
    var stagesText = ""
    var exportFormats: Set<String> = ["png", "jpg", "svg"]

    private(set) var presets: [Preset] = []
    var selectedPreset = ""
    // Snapshot taken right after applying a preset (round-tripped through
    // buildParams so defaults normalize), used to flag divergence.
    private var presetBaseline: (params: EngineParams, formats: Set<String>)?

    private let renderer = PreviewRenderer()
    private var pumpTask: Task<Void, Never>?

    // MARK: - Derived

    var similarity: Double { max(0, (1 - score) * 100) }
    var isBusy: Bool { phase == .running || phase == .paused }

    /// True once any control differs from the selected preset.
    var isPresetEdited: Bool {
        guard !selectedPreset.isEmpty, let baseline = presetBaseline else { return false }
        var current = buildParams(inputPath: "")
        current.autoSave = nil
        return current != baseline.params || exportFormats != baseline.formats
    }
    var canStart: Bool { phase == .loaded || phase == .done }
    var canExport: Bool { sessionStarted && (isBusy || phase == .done) && !isExporting }
    var isDrawingRun: Bool { runMode == .draw && phase == .running }

    // MARK: - Lifecycle

    func startEventPump() {
        guard pumpTask == nil else { return }
        pumpTask = Task {
            for await event in Engine.eventStream() {
                await handle(event)
            }
        }
        refreshPresets()
    }

    func shutdown() {
        if !sessionId.isEmpty, isBusy {
            try? Engine.cancel(sessionId)
        }
        Engine.shutdown()
    }

    // MARK: - Input

    /// Single entry for anything the user opens or drops: routes .prim
    /// documents to the document loader, everything else to image loading.
    func open(url: URL) async {
        if url.pathExtension.lowercased() == "prim" {
            await openDocument(url: url)
        } else {
            await loadImage(url: url)
        }
    }

    func loadImage(url: URL) async {
        guard !isBusy else {
            errorMessage = "Stop the current render before loading a new image."
            return
        }
        let path = url.path(percentEncoded: false)
        do {
            let info = try await Task.detached(priority: .userInitiated) {
                try Engine.inspect(path: path, thumbMaxDim: 1600)
            }.value
            inputInfo = info
            if let data = Data(base64Encoded: info.thumbJpegB64) {
                sourceImage = NSImage(data: data)
            }
            sessionStarted = false
            sessionId = ""
            started = nil
            previewImage = nil
            await renderer.reset()
            resetStats()
            phase = .loaded
            underlayVisible = true // the empty canvas guide, like the web app
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears the loaded image and any finished render, returning to the
    /// drop-zone state. Stop the render first if one is active.
    func clearImage() {
        guard !isBusy else {
            errorMessage = "Stop the current render before clearing the image."
            return
        }
        guard phase != .empty else { return }
        resetTimeline()
        inputInfo = nil
        sourceImage = nil
        sessionId = ""
        sessionStarted = false
        started = nil
        previewImage = nil
        underlayVisible = false
        resetStats()
        phase = .empty
        Task { await renderer.reset() }
    }

    static let primType = UTType(filenameExtension: "prim") ?? .data

    func openImagePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, Self.primType]
        panel.title = "Choose an Image or Primitive Document"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await open(url: url) }
        }
    }

    // MARK: - Documents

    /// Saves the current render — mid-run, paused, or done — as a .prim
    /// document: params, the embedded source image, and every shape.
    func saveDocument() {
        guard sessionStarted, !sessionId.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Save Primitive Document"
        panel.allowedContentTypes = [Self.primType]
        panel.nameFieldStringValue =
            ((try? Engine.defaultExportName(id: sessionId)) ?? "render") + ".prim"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let id = sessionId
        let path = url.path(percentEncoded: false)
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Engine.saveDocument(id: id, path: path)
                }.value
                toast = "Saved \(url.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reopens a .prim document: controls take its params, the preview is
    /// rebuilt shape by shape, and export/save work immediately — no
    /// recompute. Restart re-renders from the embedded source.
    func openDocument(url: URL) async {
        guard !isBusy else {
            errorMessage = "Stop the current render before opening a document."
            return
        }
        let path = url.path(percentEncoded: false)
        do {
            toast = "Opening \(url.lastPathComponent)…"
            let doc = try await Task.detached(priority: .userInitiated) {
                try Engine.loadDocument(path: path)
            }.value
            applyParams(doc.params)
            selectedPreset = ""
            presetBaseline = nil
            inputInfo = doc.input
            if let data = Data(base64Encoded: doc.input.thumbJpegB64) {
                sourceImage = NSImage(data: data)
            }
            sessionId = doc.sessionId
            started = doc.started
            sessionStarted = true
            underlayVisible = false
            shapesDone = doc.shapesDone
            totalShapes = doc.started.totalShapes
            score = doc.score
            shapesPerSec = 0
            elapsedMs = doc.elapsedMs
            _ = await renderer.begin(doc.started)
            previewImage = await renderer.append(doc.shapes)
            phase = .done
            toast = "Opened \(url.lastPathComponent) — \(doc.shapesDone.formatted()) shapes"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Render control

    private func ensureCheckpointDir() -> Bool {
        guard checkpointsOn && checkpointDir.isEmpty else { return true }
        guard let dir = Self.chooseDirectory(title: "Choose Checkpoint Folder") else {
            errorMessage = "Checkpoints are enabled but no folder is chosen."
            return false
        }
        checkpointDir = dir
        return true
    }

    func start() {
        guard let inputInfo, canStart else { return }
        guard ensureCheckpointDir() else { return }
        do {
            sessionStarted = false
            sessionId = try Engine.startRender(buildParams(inputPath: inputInfo.path))
            phase = .running
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canContinue: Bool { phase == .done && sessionStarted && !sessionId.isEmpty }

    /// Continues the finished (or reopened) render: keeps every shape on the
    /// canvas and adds more with the current sidebar settings — same mode or
    /// a different one. Count is the total target.
    func continueRender() {
        guard canContinue, let inputInfo else { return }
        guard ensureCheckpointDir() else { return }
        do {
            try Engine.continueRender(id: sessionId, params: buildParams(inputPath: inputInfo.path))
            phase = .running
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        try? Engine.pause(sessionId)
    }

    func resume() {
        try? Engine.resume(sessionId)
    }

    func stop() {
        try? Engine.cancel(sessionId)
    }

    // MARK: - Drawing-mode brush

    func brushMoved(to imagePoint: CGPoint, active: Bool) {
        guard let started else { return }
        let radius = 0.08 * Double(max(started.inputW, started.inputH))
        Engine.setDrawFocus(x: imagePoint.x, y: imagePoint.y, radius: radius, active: active)
    }

    // MARK: - Export

    func runExport() {
        guard canExport, !sessionId.isEmpty else { return }
        guard let dir = Self.chooseDirectory(title: "Choose Output Folder") else { return }
        let id = sessionId
        let formats = exportFormats.sorted()
        isExporting = true
        Task {
            do {
                let baseName = try Engine.defaultExportName(id: id)
                let options = ExportOptions(
                    dir: dir,
                    baseName: baseName,
                    formats: formats,
                    gif: formats.contains("gif") ? GIFOptions() : nil
                )
                let paths = try await Task.detached(priority: .userInitiated) {
                    try Engine.exportRender(id: id, options: options)
                }.value
                toast = "Exported \(paths.count) file\(paths.count == 1 ? "" : "s")"
                if let first = paths.first {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first)])
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    static func chooseDirectory(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = title
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }

    // MARK: - Video export

    var showVideoExportSheet = false
    var videoSettings = VideoExportSettings()
    private(set) var videoExportFraction: Double?
    private var videoExportTask: Task<Void, Never>?

    var canExportVideo: Bool { sessionStarted && !sessionId.isEmpty && videoExportFraction == nil }

    func beginVideoExport() {
        guard canExportVideo else { return }
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.allowedContentTypes = videoSettings.format.fileType == .mov ? [.quickTimeMovie] : [.mpeg4Movie]
        panel.nameFieldStringValue =
            ((try? Engine.defaultExportName(id: sessionId)) ?? "render") + "." + videoSettings.format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let id = sessionId
        let settings = videoSettings
        videoExportFraction = 0
        videoExportTask = Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Engine.getShapes(id: id)
                }.value
                guard !data.shapes.isEmpty else {
                    throw VideoExportError.setup("no shapes to export yet")
                }
                try await VideoExporter.export(data: data, settings: settings, to: url) { [weak self] fraction in
                    self?.videoExportFraction = fraction
                }
                toast = "Exported \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch is CancellationError {
                toast = "Video export cancelled"
            } catch {
                errorMessage = error.localizedDescription
            }
            videoExportFraction = nil
            videoExportTask = nil
        }
    }

    func cancelVideoExport() {
        videoExportTask?.cancel()
    }

    // MARK: - Timeline scrubber

    private(set) var timeline: ShapeTimeline?
    private(set) var timelineCount = 0
    private(set) var timelinePosition = 0
    private(set) var timelineLoading = false
    var timelineVisible = false
    private var preScrubImage: CGImage?

    var canShowTimeline: Bool { phase == .done && sessionStarted && !sessionId.isEmpty }

    func toggleTimeline() {
        if timelineVisible {
            closeTimeline()
        } else {
            openTimeline()
        }
    }

    private func openTimeline() {
        guard canShowTimeline, !timelineLoading else { return }
        let id = sessionId
        timelineLoading = true
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Engine.getShapes(id: id)
                }.value
                guard !data.shapes.isEmpty else {
                    throw EngineError(message: "no shapes to scrub yet")
                }
                let timeline = ShapeTimeline(data: data)
                await timeline.prepare()
                guard phase == .done, sessionId == id else { return } // state moved on
                self.timeline = timeline
                preScrubImage = previewImage
                timelineCount = data.shapes.count
                timelinePosition = data.shapes.count
                timelineVisible = true
            } catch {
                errorMessage = error.localizedDescription
            }
            timelineLoading = false
        }
    }

    /// Drops the scrub view and restores the live render image.
    func closeTimeline() {
        if let preScrubImage {
            previewImage = preScrubImage
        }
        resetTimeline()
    }

    /// Invalidates the timeline without restoring the image (a new render,
    /// continuation, or clear is about to replace the preview anyway).
    func resetTimeline() {
        timelineVisible = false
        timeline = nil
        timelineCount = 0
        timelinePosition = 0
        preScrubImage = nil
    }

    func scrubTimeline(to position: Int) {
        guard let timeline, timelineVisible else { return }
        let clamped = min(max(0, position), timelineCount)
        timelinePosition = clamped
        Task {
            if let image = await timeline.frame(at: clamped) {
                previewImage = image
            }
        }
    }

    func exportTimelineFrame() {
        guard let timeline, timelineVisible else { return }
        let position = timelinePosition
        let panel = NSSavePanel()
        panel.title = "Export Frame"
        panel.allowedContentTypes = [.png]
        let base = (try? Engine.defaultExportName(id: sessionId)) ?? "render"
        panel.nameFieldStringValue = "\(base)-frame\(position).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let image = await timeline.renderFull(at: position) else {
                errorMessage = "Could not render the frame."
                return
            }
            do {
                try Self.writePNG(image, to: url)
                toast = "Exported \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw EngineError(message: "PNG encoding failed")
        }
        try data.write(to: url)
    }

    // MARK: - Presets

    func refreshPresets() {
        presets = (try? Engine.listPresets()) ?? []
    }

    /// Maps engine params back onto the individual controls (used by both
    /// presets and reopened documents).
    func applyParams(_ p: EngineParams) {
        mode = p.mode
        shapeCount = p.shapeCount
        alphaAuto = p.alpha == 0
        if p.alpha > 0 { alpha = Double(p.alpha) }
        strokeAuto = p.strokeWidth == 0
        if p.strokeWidth > 0 { strokeWidth = p.strokeWidth }
        repeatCount = p.repeatCount
        inputFullRes = p.inputResize == 0
        if p.inputResize > 0 { inputResize = p.inputResize }
        outputMatchInput = p.outputSize == 0
        if p.outputSize > 0 { outputSize = p.outputSize }
        bgAuto = p.background.isEmpty
        if !p.background.isEmpty { bgColor = Color(hex: p.background) ?? .black }
        workersAll = p.workers == 0
        if p.workers > 0 { workers = p.workers }
        runMode = p.runMode
        if p.targetScore > 0 { targetScore = p.targetScore }
        stagesText = (p.stages ?? [])
            .map { "\($0.count), \($0.mode), \($0.alpha), \($0.repeatCount)" }
            .joined(separator: "\n")
    }

    func applyPreset(named name: String) {
        guard let preset = presets.first(where: { $0.name == name }) else { return }
        applyParams(preset.params)
        if !preset.exportFormats.isEmpty { exportFormats = Set(preset.exportFormats) }
        var baseline = buildParams(inputPath: "")
        baseline.autoSave = nil
        presetBaseline = (baseline, exportFormats)
        toast = "Applied “\(name)”"
    }

    func saveCurrentAsPreset(named name: String) {
        var params = buildParams(inputPath: "")
        params.autoSave = nil // checkpoint folders are machine-specific
        let preset = Preset(name: name, builtIn: false, params: params, exportFormats: exportFormats.sorted())
        do {
            try Engine.savePreset(preset)
            refreshPresets()
            selectedPreset = name
            presetBaseline = (params, exportFormats)
            toast = "Saved “\(name)”"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Preset transfer

    /// Writes the custom presets (built-ins exist everywhere) to a JSON file
    /// that Import can merge on any machine.
    func exportPresets() {
        let customs = presets.filter { !$0.builtIn }
        guard !customs.isEmpty else {
            errorMessage = "No custom presets to export yet."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Presets"
        panel.nameFieldStringValue = "PrimitiveDos-Presets.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(customs).write(to: url)
            toast = "Exported \(customs.count) preset\(customs.count == 1 ? "" : "s")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Merges presets from a JSON file: same-name customs are overwritten,
    /// names colliding with built-ins are skipped.
    func importPresets() {
        let panel = NSOpenPanel()
        panel.title = "Import Presets"
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try JSONDecoder().decode([Preset].self, from: Data(contentsOf: url))
            var imported = 0
            var skipped = 0
            for preset in incoming where !preset.name.isEmpty {
                do {
                    try Engine.savePreset(preset)
                    imported += 1
                } catch {
                    skipped += 1
                }
            }
            refreshPresets()
            toast = skipped == 0
                ? "Imported \(imported) preset\(imported == 1 ? "" : "s")"
                : "Imported \(imported), skipped \(skipped) (built-in names)"
        } catch {
            errorMessage = "Could not read presets file: \(error.localizedDescription)"
        }
    }

    func deletePreset(named name: String) {
        do {
            try Engine.deletePreset(name: name)
            refreshPresets()
            if selectedPreset == name { selectedPreset = "" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Params assembly

    func buildParams(inputPath: String) -> EngineParams {
        var p = EngineParams()
        p.inputPath = inputPath
        p.mode = mode
        p.shapeCount = max(1, shapeCount)
        p.alpha = alphaAuto ? 0 : Int(alpha)
        p.repeatCount = max(0, repeatCount)
        p.inputResize = inputFullRes ? 0 : inputResize
        p.outputSize = outputMatchInput ? 0 : outputSize
        p.background = bgAuto ? "" : (bgColor.hexString ?? "")
        p.workers = workersAll ? 0 : max(1, workers)
        p.strokeWidth = strokeAuto ? 0 : strokeWidth
        p.runMode = runMode
        p.targetScore = min(99.9, max(1, targetScore))
        let stages = Self.parseStages(stagesText, fallbackMode: mode)
        if !stages.isEmpty {
            p.stages = stages
        }
        if checkpointsOn && !checkpointDir.isEmpty && !checkpointFormats.isEmpty {
            p.autoSave = AutoSaveOptions(
                dir: checkpointDir,
                baseName: "",
                formats: checkpointFormats.sorted(),
                nth: max(1, checkpointNth)
            )
        }
        return p
    }

    static func parseStages(_ text: String, fallbackMode: Int) -> [Stage] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ",").map {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            guard let count = parts.first ?? nil, count > 0 else { return nil }
            return Stage(
                count: count,
                mode: parts.count > 1 ? (parts[1] ?? fallbackMode) : fallbackMode,
                alpha: parts.count > 2 ? (parts[2] ?? 128) : 128,
                repeatCount: parts.count > 3 ? (parts[3] ?? 0) : 0
            )
        }
    }

    // MARK: - Event handling

    private func handle(_ event: EngineEvent) async {
        switch event {
        case .started(let p):
            guard p.sessionId == sessionId else { return }
            resetTimeline()
            sessionStarted = true
            started = p
            totalShapes = p.totalShapes
            // Pure shapes by default; in drawing mode the faint source is the
            // painting guide.
            underlayVisible = runMode == .draw
            if p.resumed != true {
                // Fresh render: new preview document. Continuations keep the
                // existing canvas and append.
                resetStats()
                totalShapes = p.totalShapes
                previewImage = await renderer.begin(p)
            }
            phase = .running

        case .batch(let b):
            guard b.sessionId == sessionId else { return }
            if b.previewMode == "raster", let jpeg = b.snapshotJpeg {
                if let img = await renderer.applySnapshot(jpegBase64: jpeg) {
                    previewImage = img
                }
            } else if let shapes = b.shapes, !shapes.isEmpty {
                if let img = await renderer.append(shapes) {
                    previewImage = img
                }
            }
            shapesDone = b.shapesDone
            totalShapes = b.totalShapes
            score = b.score
            shapesPerSec = b.shapesPerSec
            elapsedMs = b.elapsedMs

        case .paused:
            if phase == .running { phase = .paused }

        case .resumed:
            if phase == .paused { phase = .running }

        case .done(let p):
            guard p.sessionId == sessionId else { return }
            shapesDone = p.shapesDone
            score = p.score
            elapsedMs = p.elapsedMs
            phase = .done
            toast = p.cancelled
                ? "Stopped at \(p.shapesDone.formatted()) shapes — you can still export"
                : "Finished \(p.shapesDone.formatted()) shapes"

        case .error(let p):
            errorMessage = p.message
            if p.sessionId == sessionId && !sessionStarted {
                phase = inputInfo == nil ? .empty : .loaded
            }

        case .exported:
            break // runExport reports from the synchronous return value
        }
    }

    private func resetStats() {
        shapesDone = 0
        totalShapes = 0
        score = 0
        shapesPerSec = 0
        elapsedMs = 0
    }
}

// MARK: - Color/hex helpers

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let bits = UInt64(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((bits >> 16) & 0xff) / 255,
            green: Double((bits >> 8) & 0xff) / 255,
            blue: Double(bits & 0xff) / 255
        )
    }

    var hexString: String? {
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(converted.redComponent * 255))
        let g = Int(round(converted.greenComponent * 255))
        let b = Int(round(converted.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
