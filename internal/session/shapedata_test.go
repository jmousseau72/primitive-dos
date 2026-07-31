package session

import (
	"image"
	"image/color"
	"testing"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

// Renders a few shapes of every mode through the real engine and checks that
// every concrete shape type maps to a complete, faithful ShapeRecord.
func TestMakeShapeRecordCoversAllModes(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 48, 48))
	for y := 0; y < 48; y++ {
		for x := 0; x < 48; x++ {
			img.Set(x, y, color.RGBA{uint8(x * 5), uint8(y * 5), 128, 255})
		}
	}

	modes := []primitive.ShapeType{
		primitive.ShapeTypeTriangle,
		primitive.ShapeTypeRectangle,
		primitive.ShapeTypeEllipse,
		primitive.ShapeTypeCircle,
		primitive.ShapeTypeRotatedRectangle,
		primitive.ShapeTypeQuadratic,
		primitive.ShapeTypeRotatedEllipse,
		primitive.ShapeTypePolygon,
	}

	model := primitive.NewModel(img, primitive.MakeHexColor("808080"), 48, 2)
	for _, m := range modes {
		model.Step(m, 128, 0)
	}

	seen := map[string]bool{}
	for i, sh := range model.Shapes {
		rec := makeShapeRecord(sh, model.Colors[i])
		if rec.T == "" {
			t.Fatalf("shape %T produced no record type", sh)
		}
		if len(rec.C) != 8 {
			t.Fatalf("record color %q is not rrggbbaa", rec.C)
		}
		seen[rec.T] = true

		switch s := sh.(type) {
		case *primitive.Quadratic:
			want := []float64{s.X1, s.Y1, s.X2, s.Y2, s.X3, s.Y3}
			assertPoints(t, rec.P, want)
			if rec.W != s.Width {
				t.Fatalf("quad width %v != %v", rec.W, s.Width)
			}
		case *primitive.Triangle:
			want := []float64{
				float64(s.X1), float64(s.Y1),
				float64(s.X2), float64(s.Y2),
				float64(s.X3), float64(s.Y3),
			}
			assertPoints(t, rec.P, want)
		case *primitive.RotatedEllipse:
			assertPoints(t, rec.P, []float64{s.X, s.Y, s.Rx, s.Ry, s.Angle})
		case *primitive.Polygon:
			if len(rec.P) != s.Order*2 {
				t.Fatalf("polygon record has %d coords, want %d", len(rec.P), s.Order*2)
			}
		}
	}

	for _, want := range []string{"tri", "rect", "rrect", "ell", "rell", "quad", "poly"} {
		if !seen[want] {
			t.Fatalf("no record of type %q produced (modes covered: %v)", want, seen)
		}
	}
}

func assertPoints(t *testing.T, got, want []float64) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("points %v != %v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("points %v != %v", got, want)
		}
	}
}
