# Primitive Dos

A modern macOS app for recreating images with geometric shapes — triangles,
rectangles, ellipses, circles, polygons, and quadratic beziers. Drop in a
photo, watch the reconstruction paint itself shape by shape, and export the
result as an infinitely scalable SVG (or PNG, JPEG, animated GIF, and video).

Primitive Dos is a revival of the algorithm behind
[fogleman/primitive](https://github.com/fogleman/primitive) by Michael
Fogleman (MIT licensed), whose original macOS app is no longer available.
The engine is vendored in `internal/primitive` with minimal, documented
additions; everything around it is new.

## Two frontends, one engine

- **`macos/` — native SwiftUI app (primary).** macOS 26+, the Go engine
  embedded in-process via cgo (`bridge/` builds a universal c-archive).
  This is where new features land first.
- **Wails app (repo root)** — Go + web-tech frontend, kept as the future
  cross-platform (Windows) track.
- **`cmd/primitive-cli`** — the original CLI, preserved flag-for-flag
  (plus `-w` for bezier stroke width).

Both GUIs share presets via `~/Library/Application Support/PrimitiveDos/presets.json`.

## Features (native app)

- Drag-and-drop or browse: PNG, JPEG, GIF, BMP, TIFF, WebP — or a `.prim` document
- Live preview streaming shapes as they are found; light/dark/system appearance
- Every engine option: shape mode, count, opacity (auto), bezier stroke width
  (auto), repeat, input resize (full-res), output size (match input),
  background color (average), workers, multi-stage runs, checkpoint auto-save
- Run modes: until shape count · until stopped · until similarity % ·
  **drawing mode** (paint on the canvas; shapes appear under the brush)
- **`.prim` documents**: full render state (params + embedded source + every
  shape and score), gzipped. Save mid-run, reopen with zero recompute,
  re-export anything, **Continue** adding shapes — even in a different mode.
  Finder shows a custom icon; double-click opens.
- **Timeline scrubber**: slide through the shape history; export any moment
  as PNG / JPEG / SVG / composite-over-source at full resolution
- **Video export (⌘⇧E)**: H.264 / HEVC / ProRes of the artwork drawing
  itself; pacing curves (slow start, linear, score-weighted), hold, size/fps
- **Compositing tools**: tunable source underlay (opacity, color), composite
  export, and transparent export backgrounds (shapes-on-alpha PNG/SVG)
- Presets: built-ins for bezier workflows and classic shape-art looks;
  custom presets with deviation badge, import/export as JSON
- Unsaved-work guard (Save / Don't Save / Cancel) on close, quit, and clear

## Building

Native app: Go 1.25+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
xcodegen generate --spec macos/project.yml --project macos
xcodebuild -project macos/PrimitiveDos.xcodeproj -scheme PrimitiveDos build
```

The pre-build phase compiles the Go engine (universal arm64 + x86_64).
All project settings live in `macos/project.yml` — the `.xcodeproj` is
generated. Tests: `go test ./...`; end-to-end scripts in `macos/Scripts/`
(`smoke.sh`, `smoke-video.sh`).

Wails app: `wails build` (needs Node). CLI: `go build ./cmd/primitive-cli`.

## Known issues

- **Settings sidebar sizing (under investigation).** The right-hand panel
  has a history of layout instability: windows shrinking until the canvas
  collapsed, panel width varying between sessions, and toolbar cramming
  when phase-dependent items appeared. Root cause was SwiftUI's
  `.inspector` negotiating window/column sizing on its own; the panel was
  rebuilt as a plain fixed-width (360pt) `HStack` child and the AppKit
  resize workarounds were removed. **This rewrite has not yet been fully
  verified in daily use — treat sidebar/window sizing as an open defect
  until it survives a real session.** See ROADMAP.md.
- Reopened `.prim` documents show 0:00 elapsed (running time is not stored).
- JPEG/GIF exports always include the background (no alpha in those formats).

## Roadmap

Future feature ideas are tracked in [ROADMAP.md](ROADMAP.md).

## Credits

- Algorithm and engine: [Michael Fogleman](https://www.michaelfogleman.com)
  — [fogleman/primitive](https://github.com/fogleman/primitive), MIT
- App: [jmousseau72](https://github.com/jmousseau72), MIT — see [LICENSE](LICENSE)
- Built with [Wails](https://wails.io), SwiftUI, and AVFoundation
