# Primitive Dos — Roadmap & Ideas

Ideas discussed and parked for future work, roughly ordered by pull.
`main` is the stable line; each feature gets its own short-lived branch.

## Near-term / high value

- **Fix and verify the settings sidebar.** Open defect (see README Known
  Issues). History: `.inspector` ignored width/window constraints →
  AppKit clamp attempts (windowWillResize/windowDidResize/contentMinSize,
  all since removed) → rebuilt as a fixed 360pt `HStack` child (commit
  9895564). Needs a real-session verification pass: constant panel width
  across phases/relaunches/displays, no canvas collapse, no toolbar
  cramming. If defects remain, next step is a ground-up layout audit of
  ContentView (toolbar item sizing included) rather than more patches.
- **Self-drawing SVG export.** Emit SVGs with CSS/SMIL animation so the
  artwork draws itself in a browser — same shape-history data as video
  export, huge for web/motion designers. Natural next branch.
- **Batch queue.** Drop a folder, apply a preset to every image — the old
  VS Code tasks workflow, productized. Consider a watch-folder mode.
- **Quick Look extension for `.prim`** — press space in Finder, see the
  render (we can already draw from shape records).

## Video input (designed, not started)

Import a video clip and primitive-ize it without melting the machine.
Naive per-frame rendering is hours per clip; the viable architecture:

1. **Warm-start temporal coherence** — frame N+1 inherits frame N's shape
   set; short refinement pass (nudge shapes against new target, drop
   worst, add few). Engine building blocks exist (RebuildCurrent,
   HillClimb, focus).
2. **Keyframe optimization + shape tweening** — optimize 8–12 fps, then
   interpolate shape geometry/colors between keyframes for 30/60fps
   output. Distinctive look; nothing on the market does it.
3. Classic 256px working resolution, a few hundred maintained shapes.

Estimated: 10s clip ≈ 3–8 min offline on Apple Silicon, CPU-bounded with
worker caps. Ingest via AVAssetReader; output through the existing
VideoExporter. Biggest feature on the list — plan-mode it first.

## Creative depth

- **Importance masking** — generalize the drawing brush into a paintable
  "detail here" mask (faces get more shapes); optionally auto-suggest via
  the Vision framework for portraits.
- **New primitives** — straight segments (hatching/etching), stipple dots,
  glyphs, Voronoi cells. Engine's Shape interface makes each tractable.
- **Palette control** — lock output to N colors or a brand palette;
  duotone mode.
- **Recipes** — productize multi-stage runs (coarse triangles → fine
  beziers) as shareable presets.
- **Heatmap view** — the engine's dormant `heatmap.go`.

## Platform & product

- **iPad + Apple Pencil** — the big v2 swing: drawing mode under a pencil
  tip. Engine compiles for iOS; SwiftUI mostly ports.
- **Windows** via the Wails track (untouched by design; needs docs/resume
  parity when picked up).
- **Wails-app parity** — documents, resume, timeline/video for the web
  frontend, if it stays a shipping target.
- **Shortcuts actions** — "Primitive this image with preset X".
- **Distribution** — Developer ID + hardened runtime + notarization for
  selling outside the App Store; sandboxing (presets path migration!) if
  the Mac App Store is pursued. MIT permits selling; fogleman notice ships
  in LICENSE/About. Note: public MIT repo means others may build/sell from
  it too — decide open-core stance before launch.
- **Acknowledgements screen** in-app (freetype credit line, fogleman, deps).

## Small polish

- Store elapsed time in `.prim` documents.
- SVG export at scrub position from the Go side too (currently Swift-assembled).
- Consider dictionary-backed sidebar section state (⌥-click fan-out has
  missed newly added sections once already).
