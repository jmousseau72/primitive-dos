// Thin Swift face over the cgo bridge (bridge/bridge.go, built into
// Vendor/libprimitive.a). Conventions mirrored from the Go side:
// every returned char* is malloc'd and freed here exactly once; results use
// the {"ok":..,"value":..,"error":..} envelope; events are pulled by a single
// dedicated thread (never the cooperative pool — PrimitiveNextEvent blocks).

import Foundation

struct EngineError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Engine {
    private struct Envelope<V: Decodable>: Decodable {
        let ok: Bool
        let value: V?
        let error: String?
    }

    private struct Nothing: Decodable {}

    /// Single funnel for every bridge call: decodes the envelope and frees
    /// the C string, so no call site can leak or double-free.
    private static func call<V: Decodable>(
        _ type: V.Type,
        _ invoke: () -> UnsafeMutablePointer<CChar>?
    ) throws -> V? {
        guard let raw = invoke() else {
            throw EngineError(message: "engine returned no response")
        }
        defer { PrimitiveFree(raw) }
        let data = Data(String(cString: raw).utf8)
        let envelope: Envelope<V>
        do {
            envelope = try JSONDecoder().decode(Envelope<V>.self, from: data)
        } catch {
            throw EngineError(message: "bad engine response: \(error)")
        }
        guard envelope.ok else {
            throw EngineError(message: envelope.error ?? "unknown engine error")
        }
        return envelope.value
    }

    private static func callValue<V: Decodable>(
        _ type: V.Type,
        _ invoke: () -> UnsafeMutablePointer<CChar>?
    ) throws -> V {
        guard let value = try call(type, invoke) else {
            throw EngineError(message: "engine returned no value")
        }
        return value
    }

    private static func callVoid(_ invoke: () -> UnsafeMutablePointer<CChar>?) throws {
        _ = try call(Nothing.self, invoke)
    }

    private static func encode(_ value: some Encodable) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
    }

    private static func cString(_ s: String) -> UnsafeMutablePointer<CChar> {
        strdup(s)
    }

    // MARK: - Calls

    static func inspect(path: String, thumbMaxDim: Int32 = 1600) throws -> InputInfo {
        let cs = cString(path)
        defer { free(cs) }
        return try callValue(InputInfo.self) { PrimitiveInspect(cs, thumbMaxDim) }
    }

    static func startRender(_ params: EngineParams) throws -> String {
        let cs = cString(try encode(params))
        defer { free(cs) }
        return try callValue(String.self) { PrimitiveStartRender(cs) }
    }

    static func pause(_ id: String) throws {
        let cs = cString(id)
        defer { free(cs) }
        try callVoid { PrimitivePauseRender(cs) }
    }

    static func resume(_ id: String) throws {
        let cs = cString(id)
        defer { free(cs) }
        try callVoid { PrimitiveResumeRender(cs) }
    }

    static func cancel(_ id: String) throws {
        let cs = cString(id)
        defer { free(cs) }
        try callVoid { PrimitiveCancelRender(cs) }
    }

    /// Blocking (GIF export replays the whole model) — call off the main actor.
    static func exportRender(id: String, options: ExportOptions) throws -> [String] {
        let cid = cString(id)
        let copts = cString(try encode(options))
        defer {
            free(cid)
            free(copts)
        }
        return try callValue([String].self) { PrimitiveExportRender(cid, copts) }
    }

    static func defaultExportName(id: String) throws -> String {
        let cs = cString(id)
        defer { free(cs) }
        return try callValue(String.self) { PrimitiveDefaultExportName(cs) }
    }

    static func listPresets() throws -> [Preset] {
        try call([Preset].self) { PrimitiveListPresets() } ?? []
    }

    static func savePreset(_ preset: Preset) throws {
        let cs = cString(try encode(preset))
        defer { free(cs) }
        try callVoid { PrimitiveSavePreset(cs) }
    }

    static func deletePreset(name: String) throws {
        let cs = cString(name)
        defer { free(cs) }
        try callVoid { PrimitiveDeletePreset(cs) }
    }

    /// Blocking (reads the source file and serializes every shape) — call
    /// off the main actor. Safe mid-run.
    static func saveDocument(id: String, path: String) throws {
        let cid = cString(id)
        let cpath = cString(path)
        defer {
            free(cid)
            free(cpath)
        }
        try callVoid { PrimitiveSaveDocument(cid, cpath) }
    }

    /// Blocking (decodes the embedded image and rebuilds the model) — call
    /// off the main actor. The returned session is done: exportable and
    /// re-savable, but it never steps.
    static func loadDocument(path: String) throws -> LoadedDocument {
        let cs = cString(path)
        defer { free(cs) }
        return try callValue(LoadedDocument.self) { PrimitiveLoadDocument(cs) }
    }

    /// Hot path during drawing mode — no JSON, no allocation.
    static func setDrawFocus(x: Double, y: Double, radius: Double, active: Bool) {
        PrimitiveSetDrawFocus(x, y, radius, active ? 1 : 0)
    }

    static func shutdown() {
        PrimitiveShutdown()
    }

    // MARK: - Events

    /// The single event pump. PrimitiveNextEvent blocks in a Go channel
    /// receive, so it runs on a dedicated thread; it returns NULL after
    /// PrimitiveShutdown, which finishes the stream. Exactly one consumer
    /// (AppState) for the lifetime of the process.
    static func eventStream() -> AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            Thread.detachNewThread {
                while let raw = PrimitiveNextEvent() {
                    let data = Data(String(cString: raw).utf8)
                    PrimitiveFree(raw)
                    if let event = EngineEvent(json: data) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
        }
    }
}
