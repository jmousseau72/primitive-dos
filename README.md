# Primitive Dos

A modern macOS app for recreating images with geometric shapes — triangles,
rectangles, ellipses, circles, polygons, and quadratic beziers. Drop in a
photo, watch the reconstruction paint itself shape by shape, and export the
result as an infinitely scalable SVG (or PNG, JPEG, animated GIF).

Primitive Dos is a revival of the algorithm behind
[fogleman/primitive](https://github.com/fogleman/primitive) by Michael
Fogleman (MIT licensed), whose original macOS app is no longer available.
The engine is vendored unmodified in `internal/primitive`; everything around
it — the GUI, live preview, session driver, presets, native GIF encoding —
is new.

## Why

At high shape counts, the quadratic-bezier mode produces an SVG replica that
is essentially indistinguishable from the source photo at a normal viewing
distance — and because it is vector art, it scales to any size with zero
quality loss.

## Features

- **Drag and drop** an image (or browse) — PNG, JPEG, GIF, BMP, TIFF, WebP
- **Live preview**: shapes stream into an inline SVG as they are found; very
  large runs switch automatically to throttled raster snapshots
- **Every CLI option** as a control: shape mode, count, opacity (incl. auto),
  repeat, input resize (incl. full resolution), output size (incl. match
  input), background color (incl. auto average), worker count, multi-stage
  configs
- **Run modes**: to a shape count, until stopped, until a similarity target,
  or **drawing mode** — paint on the canvas and shapes appear under your brush
- **Bezier stroke width** control (fixed or optimizer-varied), which the
  upstream engine had frozen at 0.5
- **Source underlay toggle** — see the original faintly beneath the shapes,
  or keep the canvas pure
- **Pause / resume / stop**, and **export at any moment** — mid-run, paused,
  or stopped
- **Presets**: built-ins for fast experiments and high-quality finals, plus
  save-your-own
- **Checkpoints**: optionally save numbered PNG/JPG/SVG frames every Nth shape
- **Exports**: PNG · JPEG · SVG · animated GIF (encoded natively — no
  ImageMagick required), any combination in one go

## Building

Requirements: Go 1.25+, Node.js, and the [Wails v2 CLI](https://wails.io).

```
wails build
```

produces `build/bin/Primitive Dos.app`. For live development:

```
wails dev
```

## Command-line interface

The original `primitive` CLI is preserved flag-for-flag:

```
go build -o primitive ./cmd/primitive-cli
./primitive -i input.png -o output.svg -n 2000 -m 6 -a 255 -r 0 -s 1024
```

| Flag | Default | Description |
| --- | --- | --- |
| `i` | n/a | input file |
| `o` | n/a | output file (repeatable; format by extension: png, jpg, svg, gif; `%d` for frames) |
| `n` | n/a | number of shapes (repeatable for multi-stage runs) |
| `m` | 1 | mode: 0=combo 1=triangle 2=rect 3=ellipse 4=circle 5=rotatedrect 6=beziers 7=rotatedellipse 8=polygon |
| `rep` | 0 | extra shapes per iteration with reduced search |
| `w` | 0.5 | bezier stroke width (0 = let the optimizer vary it) — new in Primitive Dos |
| `nth` | 1 | save every Nth frame (with `%d` in output path) |
| `r` | 256 | resize large input images to this size (0 = full resolution) |
| `s` | 1024 | output image size |
| `a` | 128 | color alpha (0 = auto per shape) |
| `bg` | avg | starting background color (hex) |
| `j` | 0 | parallel workers (0 = all cores) |
| `v` / `vv` | off | verbose / very verbose output |

## Credits

- Algorithm and engine: [Michael Fogleman](https://www.michaelfogleman.com)
  — [fogleman/primitive](https://github.com/fogleman/primitive), MIT
- App: [jmousseau72](https://github.com/jmousseau72), MIT — see [LICENSE](LICENSE)
- Built with [Wails](https://wails.io)
