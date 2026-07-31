// Phase-1 smoke test for the cgo bridge: inspect an image, run a small
// bezier render pumping the event stream, then export SVG+PNG.
// Run via smoke.sh — it compiles this against macos/Vendor/libprimitive.a.

import Foundation

func call(_ raw: UnsafeMutablePointer<CChar>?) -> [String: Any] {
    guard let raw else { fatalError("bridge returned NULL") }
    defer { PrimitiveFree(raw) }
    let json = String(cString: raw)
    guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
        fatalError("bad JSON from bridge: \(json)")
    }
    return obj
}

func value(_ envelope: [String: Any]) -> Any? {
    guard envelope["ok"] as? Bool == true else {
        fatalError("bridge error: \(envelope["error"] ?? "unknown")")
    }
    return envelope["value"]
}

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: smoke <image> <outdir>") }
let imagePath = args[1]
let outDir = args[2]

// 1. Inspect
let info = value(call(imagePath.withCString { PrimitiveInspect(UnsafeMutablePointer(mutating: $0), 320) })) as! [String: Any]
let width = info["width"] as! Int
let height = info["height"] as! Int
precondition(width > 0 && height > 0, "bad dimensions")
print("inspect ok: \(width)x\(height)")

// 2. Start a small bezier render
let params: [String: Any] = [
    "inputPath": imagePath,
    "mode": 6,
    "shapeCount": 50,
    "alpha": 255,
    "inputResize": 128,
    "outputSize": 256,
    "strokeWidth": 1.5,
    "runMode": "count",
]
let paramsJSON = String(data: try! JSONSerialization.data(withJSONObject: params), encoding: .utf8)!
let sessionId = value(call(paramsJSON.withCString { PrimitiveStartRender(UnsafeMutablePointer(mutating: $0)) })) as! String
print("session \(sessionId) started")

// 3. Pump events until done
var sawStarted = false
var quadShapes = 0
var lastScore = 1.0
var scores: [Double] = []
var done = false

while !done {
    guard let raw = PrimitiveNextEvent() else { fatalError("event stream closed early") }
    let evt = String(cString: raw)
    PrimitiveFree(raw)
    guard let obj = try? JSONSerialization.jsonObject(with: Data(evt.utf8)) as? [String: Any],
          let name = obj["event"] as? String else { fatalError("bad event: \(evt)") }
    let payload = obj["payload"] as? [String: Any] ?? [:]
    switch name {
    case "session:started":
        sawStarted = true
        print("started: \(payload["width"]!)x\(payload["height"]!) scale \(payload["scale"]!)")
    case "session:batch":
        if let shapes = payload["shapes"] as? [[String: Any]] {
            quadShapes += shapes.filter { $0["t"] as? String == "quad" }.count
            for s in shapes {
                precondition(s["c"] as? String != nil, "shape missing color")
            }
        }
        precondition(payload["fragments"] == nil, "got SVG fragments — EmitShapeData not forced")
        if let score = payload["score"] as? Double, score > 0 {
            scores.append(score)
            lastScore = score
        }
    case "session:done":
        done = true
        print("done: \(payload["shapesDone"]!) shapes, score \(payload["score"]!)")
    case "session:error":
        fatalError("engine error: \(payload["message"] ?? "?")")
    default:
        break
    }
}

precondition(sawStarted, "no started event")
precondition(quadShapes >= 50, "expected >=50 quad records, got \(quadShapes)")
precondition(scores.first! > scores.last!, "score did not improve: \(scores.first!) -> \(scores.last!)")
print("events ok: \(quadShapes) quad shapes, score \(scores.first!) -> \(lastScore)")

// 4. Export
let opts: [String: Any] = ["dir": outDir, "baseName": "smoke", "formats": ["svg", "png"], "jpegQuality": 95]
let optsJSON = String(data: try! JSONSerialization.data(withJSONObject: opts), encoding: .utf8)!
let exported = sessionId.withCString { sid in
    optsJSON.withCString { oj in
        call(PrimitiveExportRender(UnsafeMutablePointer(mutating: sid), UnsafeMutablePointer(mutating: oj)))
    }
}
let paths = value(exported) as! [String]
for p in paths {
    precondition(FileManager.default.fileExists(atPath: p), "missing export \(p)")
}
print("export ok: \(paths)")

PrimitiveShutdown()
print("SMOKE PASS")
