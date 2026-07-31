// Codable mirrors of the Go types in internal/session (events.go, session.go,
// presets.go, export.go). Keys match the Go JSON tags exactly.

import Foundation

enum RunMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case count, forever, score, draw
    var id: String { rawValue }

    var label: String {
        switch self {
        case .count: "Until shape count"
        case .forever: "Until stopped"
        case .score: "Until similarity target"
        case .draw: "Drawing mode"
        }
    }
}

struct EngineParams: Codable, Sendable {
    var inputPath = ""
    var mode = 6
    var shapeCount = 2000
    var alpha = 255
    var repeatCount = 0
    var inputResize = 0
    var outputSize = 1024
    var background = ""
    var workers = 0
    var strokeWidth = 0.5
    var runMode: RunMode = .count
    var targetScore = 95.0
    var autoSave: AutoSaveOptions?
    var stages: [Stage]?

    enum CodingKeys: String, CodingKey {
        case inputPath, mode, shapeCount, alpha
        case repeatCount = "repeat"
        case inputResize, outputSize, background, workers
        case strokeWidth, runMode, targetScore, autoSave, stages
    }
}

struct Stage: Codable, Sendable, Identifiable {
    var count: Int
    var mode: Int
    var alpha: Int
    var repeatCount: Int

    var id: String { "\(count)-\(mode)-\(alpha)-\(repeatCount)" }

    enum CodingKeys: String, CodingKey {
        case count, mode, alpha
        case repeatCount = "repeat"
    }
}

struct AutoSaveOptions: Codable, Sendable {
    var dir: String
    var baseName: String
    var formats: [String]
    var nth: Int
}

struct InputInfo: Codable, Sendable {
    let path: String
    let width: Int
    let height: Int
    let thumbJpegB64: String
}

struct ShapeRecord: Codable, Sendable {
    let t: String
    let p: [Double]
    let w: Double?
    let c: String
}

struct StartedPayload: Codable, Sendable {
    let sessionId: String
    let width: Int
    let height: Int
    let scale: Double
    let background: String
    let totalShapes: Int
    let previewMode: String
    let inputW: Int
    let inputH: Int
}

struct BatchPayload: Codable, Sendable {
    let sessionId: String
    let shapes: [ShapeRecord]?
    let snapshotJpeg: String?
    let previewMode: String
    let shapesDone: Int
    let totalShapes: Int
    let score: Double
    let elapsedMs: Int
    let shapesPerSec: Double
}

struct StatePayload: Codable, Sendable {
    let sessionId: String
    let shapesDone: Int
}

struct DonePayload: Codable, Sendable {
    let sessionId: String
    let cancelled: Bool
    let shapesDone: Int
    let score: Double
    let elapsedMs: Int
}

struct ErrorPayload: Codable, Sendable {
    let sessionId: String
    let message: String
}

struct ExportedPayload: Codable, Sendable {
    let sessionId: String
    let paths: [String]
}

struct Preset: Codable, Sendable, Identifiable {
    var name: String
    var builtIn: Bool
    var params: EngineParams
    var exportFormats: [String]

    var id: String { name }
}

struct GIFOptions: Codable, Sendable {
    var scoreDelta = 0.001
    var delayCS = 50
    var lastDelayCS = 250
    var maxDim = 640
}

struct ExportOptions: Codable, Sendable {
    var dir: String
    var baseName: String
    var formats: [String]
    var jpegQuality = 95
    var gif: GIFOptions?
}

enum EngineEvent: Sendable {
    case started(StartedPayload)
    case batch(BatchPayload)
    case paused(StatePayload)
    case resumed(StatePayload)
    case done(DonePayload)
    case error(ErrorPayload)
    case exported(ExportedPayload)

    init?(json: Data) {
        struct Header: Decodable {
            let event: String
        }
        struct Typed<P: Decodable>: Decodable {
            let payload: P
        }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: json) else { return nil }
        func payload<P: Decodable>(_ type: P.Type) -> P? {
            (try? decoder.decode(Typed<P>.self, from: json))?.payload
        }
        switch header.event {
        case "session:started":
            guard let p = payload(StartedPayload.self) else { return nil }
            self = .started(p)
        case "session:batch":
            guard let p = payload(BatchPayload.self) else { return nil }
            self = .batch(p)
        case "session:paused":
            guard let p = payload(StatePayload.self) else { return nil }
            self = .paused(p)
        case "session:resumed":
            guard let p = payload(StatePayload.self) else { return nil }
            self = .resumed(p)
        case "session:done":
            guard let p = payload(DonePayload.self) else { return nil }
            self = .done(p)
        case "session:error":
            guard let p = payload(ErrorPayload.self) else { return nil }
            self = .error(p)
        case "export:done":
            guard let p = payload(ExportedPayload.self) else { return nil }
            self = .exported(p)
        default:
            return nil
        }
    }
}
