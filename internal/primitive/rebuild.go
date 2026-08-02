package primitive

import "strings"

// Primitive Dos addition: support for continuing a reconstructed model
// (e.g. one reopened from a document). Shapes deserialized from disk carry
// nil Workers and the model's working raster (Current) holds only the
// background — both must be repaired before Step can run again.

// AttachWorker points a shape back at a worker, which Rasterize needs for
// its scanline buffer and bounds.
func AttachWorker(shape Shape, w *Worker) {
	switch s := shape.(type) {
	case *Triangle:
		s.Worker = w
	case *Rectangle:
		s.Worker = w
	case *RotatedRectangle:
		s.Worker = w
	case *Ellipse:
		s.Worker = w
	case *RotatedEllipse:
		s.Worker = w
	case *Quadratic:
		s.Worker = w
	case *Polygon:
		s.Worker = w
	}
}

// SVGShapesOnly is Model.SVG() without the background rect — a transparent
// vector export for overlaying the shapes onto other artwork.
func (model *Model) SVGShapesOnly() string {
	full := model.SVG()
	lines := strings.Split(full, "\n")
	out := lines[:0]
	for _, line := range lines {
		if strings.HasPrefix(line, "<rect ") {
			continue
		}
		out = append(out, line)
	}
	return strings.Join(out, "\n")
}

// RebuildCurrent replays every shape onto the working raster — exactly what
// Add did during the original render, minus the color computation (colors
// are already known) — and recomputes the true score. After this the model
// can continue stepping as if it had never been serialized.
func (model *Model) RebuildCurrent() {
	if len(model.Workers) == 0 {
		return
	}
	w := model.Workers[0]
	for i, shape := range model.Shapes {
		AttachWorker(shape, w)
		lines := shape.Rasterize()
		drawLines(model.Current, model.Colors[i], lines)
	}
	model.Score = differenceFull(model.Target, model.Current)
}
