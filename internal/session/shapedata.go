package session

import (
	"fmt"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

// ShapeRecord is the structured form of one shape, for frontends that draw
// natively instead of parsing SVG (the Mac app renders these into a
// CGBitmapContext). Coordinates are in model shape-space — the same space as
// the SVG fragments inside <g transform="scale(S) translate(0.5 0.5)">.
//
// Geometry by type:
//
//	tri   p=[x1,y1,x2,y2,x3,y3]            filled, closed
//	rect  p=[x1,y1,x2,y2]                  raw corners; normalize then fill
//	                                       (w = x2-x1+1, h = y2-y1+1)
//	rrect p=[cx,cy,sx,sy,angleDeg]         translate·rotate, rect centered
//	ell   p=[cx,cy,rx,ry]                  axis-aligned (circles: rx == ry)
//	rell  p=[cx,cy,rx,ry,angleDeg]         translate·rotate, unit circle scaled
//	quad  p=[x1,y1,x2,y2,x3,y3], w=width   STROKED quadratic bezier, round caps
//	poly  p=[x0,y0,x1,y1,...]              filled, closed
type ShapeRecord struct {
	T string    `json:"t"`
	P []float64 `json:"p"`
	W float64   `json:"w,omitempty"`
	C string    `json:"c"` // rrggbbaa
}

func makeShapeRecord(shape primitive.Shape, c primitive.Color) ShapeRecord {
	rec := ShapeRecord{C: fmt.Sprintf("%02x%02x%02x%02x", c.R, c.G, c.B, c.A)}
	switch s := shape.(type) {
	case *primitive.Triangle:
		rec.T = "tri"
		rec.P = []float64{
			float64(s.X1), float64(s.Y1),
			float64(s.X2), float64(s.Y2),
			float64(s.X3), float64(s.Y3),
		}
	case *primitive.Rectangle:
		rec.T = "rect"
		rec.P = []float64{float64(s.X1), float64(s.Y1), float64(s.X2), float64(s.Y2)}
	case *primitive.RotatedRectangle:
		rec.T = "rrect"
		rec.P = []float64{
			float64(s.X), float64(s.Y),
			float64(s.Sx), float64(s.Sy),
			float64(s.Angle),
		}
	case *primitive.Ellipse:
		rec.T = "ell"
		rec.P = []float64{float64(s.X), float64(s.Y), float64(s.Rx), float64(s.Ry)}
	case *primitive.RotatedEllipse:
		rec.T = "rell"
		rec.P = []float64{s.X, s.Y, s.Rx, s.Ry, s.Angle}
	case *primitive.Quadratic:
		rec.T = "quad"
		rec.P = []float64{s.X1, s.Y1, s.X2, s.Y2, s.X3, s.Y3}
		rec.W = s.Width
	case *primitive.Polygon:
		rec.T = "poly"
		rec.P = make([]float64, 0, s.Order*2)
		for i := 0; i < s.Order; i++ {
			rec.P = append(rec.P, s.X[i], s.Y[i])
		}
	}
	return rec
}
