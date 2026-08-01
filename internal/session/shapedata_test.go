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

// ShapeData must snapshot the full history with scores and model geometry.
func TestShapeData(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 32, 32))
	for y := 0; y < 32; y++ {
		for x := 0; x < 32; x++ {
			img.Set(x, y, color.RGBA{uint8(x * 8), uint8(y * 8), 60, 255})
		}
	}
	model := primitive.NewModel(img, primitive.MakeHexColor("223344"), 64, 2)
	for i := 0; i < 4; i++ {
		model.Step(primitive.ShapeTypeQuadratic, 255, 0)
	}

	s := &RenderSession{ID: "sd1"}
	s.model = model

	payload, err := s.ShapeData()
	if err != nil {
		t.Fatal(err)
	}
	if len(payload.Shapes) != 4 {
		t.Fatalf("expected 4 shapes, got %d", len(payload.Shapes))
	}
	if payload.Width != model.Sw || payload.Height != model.Sh {
		t.Fatalf("dims %dx%d != model %dx%d", payload.Width, payload.Height, model.Sw, model.Sh)
	}
	if payload.Scale != model.Scale {
		t.Fatalf("scale %v != %v", payload.Scale, model.Scale)
	}
	if payload.Background != "#223344" {
		t.Fatalf("background %q", payload.Background)
	}
	for i, ds := range payload.Shapes {
		if ds.T != "quad" {
			t.Fatalf("shape %d type %q", i, ds.T)
		}
		if ds.S != model.Scores[i] {
			t.Fatalf("score %d: %v != %v", i, ds.S, model.Scores[i])
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
