package session

import (
	"context"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

// Renders a few shapes of every mode, saves a document, reopens it, and
// requires the reopened model to produce byte-identical SVG — which proves
// shapes, colors, order, and transforms all survive the round trip.
func TestDocumentRoundTrip(t *testing.T) {
	dir := t.TempDir()

	img := image.NewRGBA(image.Rect(0, 0, 40, 40))
	for y := 0; y < 40; y++ {
		for x := 0; x < 40; x++ {
			img.Set(x, y, color.RGBA{uint8(x * 6), uint8(y * 6), 90, 255})
		}
	}
	srcPath := filepath.Join(dir, "source.png")
	f, err := os.Create(srcPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(f, img); err != nil {
		t.Fatal(err)
	}
	f.Close()

	model := primitive.NewModel(img, primitive.MakeHexColor("445566"), 40, 2)
	modes := []primitive.ShapeType{
		primitive.ShapeTypeQuadratic,
		primitive.ShapeTypeTriangle,
		primitive.ShapeTypeRectangle,
		primitive.ShapeTypeRotatedRectangle,
		primitive.ShapeTypeEllipse,
		primitive.ShapeTypeCircle,
		primitive.ShapeTypeRotatedEllipse,
		primitive.ShapeTypePolygon,
	}
	for _, m := range modes {
		model.Step(m, 200, 0)
	}

	// Wrap the model in a session the way OpenDocument does, then save.
	s := &RenderSession{ID: "t1", params: Params{InputPath: srcPath, Mode: 6, ShapeCount: len(modes)}}
	s.model = model
	s.stepsDone = len(modes)

	docPath := filepath.Join(dir, "test.prim")
	if err := s.SaveDocument(docPath); err != nil {
		t.Fatalf("save: %v", err)
	}

	loaded, err := OpenDocument(docPath, "t2", nil)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer os.Remove(loaded.InputPath)

	if loaded.Session.stepsDone != len(modes) {
		t.Fatalf("stepsDone %d != %d", loaded.Session.stepsDone, len(modes))
	}
	if len(loaded.Session.model.Shapes) != len(model.Shapes) {
		t.Fatalf("shape count %d != %d", len(loaded.Session.model.Shapes), len(model.Shapes))
	}

	originalSVG := model.SVG()
	reopenedSVG := loaded.Session.model.SVG()
	if originalSVG != reopenedSVG {
		t.Fatalf("SVG round trip differs:\n--- original ---\n%s\n--- reopened ---\n%s", originalSVG, reopenedSVG)
	}

	// GIF re-export needs scores; ensure they survived.
	for i, sc := range loaded.Session.model.Scores {
		if sc != model.Scores[i] {
			t.Fatalf("score[%d] %v != %v", i, sc, model.Scores[i])
		}
	}
}

// Reopens a document and continues rendering on top of it: the working
// raster must be rebuilt, new shapes appended, and the score improved.
func TestDocumentResume(t *testing.T) {
	dir := t.TempDir()

	img := image.NewRGBA(image.Rect(0, 0, 40, 40))
	for y := 0; y < 40; y++ {
		for x := 0; x < 40; x++ {
			img.Set(x, y, color.RGBA{uint8(x * 6), 40, uint8(y * 6), 255})
		}
	}
	srcPath := filepath.Join(dir, "source.png")
	f, err := os.Create(srcPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(f, img); err != nil {
		t.Fatal(err)
	}
	f.Close()

	model := primitive.NewModel(img, primitive.MakeHexColor("333333"), 40, 2)
	for i := 0; i < 5; i++ {
		model.Step(primitive.ShapeTypeTriangle, 128, 0)
	}

	s := &RenderSession{ID: "r1", params: Params{InputPath: srcPath, Mode: 1, ShapeCount: 5}}
	s.model = model
	s.stepsDone = 5
	docPath := filepath.Join(dir, "resume.prim")
	if err := s.SaveDocument(docPath); err != nil {
		t.Fatal(err)
	}
	savedScore := model.Score

	done := make(chan DonePayload, 1)
	emit := func(event string, payload any) {
		if event == EvtDone {
			if p, ok := payload.(DonePayload); ok {
				done <- p
			}
		}
	}
	loaded, err := OpenDocument(docPath, "r2", emit)
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(loaded.InputPath)

	err = loaded.Session.Continue(context.Background(), Params{
		Mode:       1,
		ShapeCount: 12,
		Alpha:      128,
		Workers:    2,
		RunMode:    RunCount,
	})
	if err != nil {
		t.Fatalf("continue: %v", err)
	}

	select {
	case p := <-done:
		if p.ShapesDone != 12 {
			t.Fatalf("expected 12 steps done, got %d", p.ShapesDone)
		}
		if p.Cancelled {
			t.Fatal("continuation reported cancelled")
		}
	case <-time.After(60 * time.Second):
		t.Fatal("continuation did not finish")
	}

	if got := len(loaded.Session.model.Shapes); got < 12 {
		t.Fatalf("expected >=12 shapes after resume, got %d", got)
	}
	if loaded.Session.model.Score >= savedScore {
		t.Fatalf("score did not improve: %v -> %v", savedScore, loaded.Session.model.Score)
	}

	// Continuing with a target below the current count must refuse clearly.
	if err := loaded.Session.Continue(context.Background(), Params{Mode: 1, ShapeCount: 3, Alpha: 128, RunMode: RunCount}); err == nil {
		t.Fatal("expected error for target below current shape count")
	}
}
