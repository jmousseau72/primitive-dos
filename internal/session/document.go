package session

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

// A .prim document is a durable, self-contained render: the parameters, the
// source image itself (embedded, so the document survives the original file
// moving), and every shape with its color and score. Reopening rebuilds the
// model without recomputing, so all exports — including GIF, which needs the
// per-shape scores — work at full fidelity, and the embedded source allows a
// fresh re-render. Stored as gzipped JSON.

const documentVersion = 1

// DocShape is a ShapeRecord plus the post-add score, which Frames() needs
// for GIF re-export.
type DocShape struct {
	ShapeRecord
	S float64 `json:"s"`
}

type Document struct {
	Version    int      `json:"version"`
	Params     Params   `json:"params"`
	SourceName string   `json:"sourceName"`
	Source     []byte   `json:"source"` // original image file bytes
	Background string   `json:"background"`
	OutputSize int      `json:"outputSize"` // resolved size the model was built with
	StepsDone  int      `json:"stepsDone"`
	Score      float64  `json:"score"`
	ElapsedMs  int64    `json:"elapsedMs"`
	Shapes     []DocShape `json:"shapes"`
}

// SaveDocument writes the session's current state. Safe mid-run (takes the
// model lock between steps), while paused, or after completion.
func (s *RenderSession) SaveDocument(path string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.model == nil {
		return fmt.Errorf("nothing to save yet")
	}

	source, err := os.ReadFile(s.params.InputPath)
	if err != nil {
		// The original moved since loading — fall back to re-encoding the
		// model's target (post-resize, but better than an empty document).
		var buf bytes.Buffer
		if encErr := png.Encode(&buf, s.model.Target); encErr != nil {
			return fmt.Errorf("source image unavailable: %w", err)
		}
		source = buf.Bytes()
	}

	doc := Document{
		Version:    documentVersion,
		Params:     s.params,
		SourceName: filepath.Base(s.params.InputPath),
		Source:     source,
		Background: hexString(s.model.Background),
		OutputSize: maxInt(s.model.Sw, s.model.Sh),
		StepsDone:  s.stepsDone,
		Score:      s.model.Score,
	}
	doc.Params.AutoSave = nil // checkpoint folders are machine-specific
	for i, shape := range s.model.Shapes {
		ds := DocShape{ShapeRecord: makeShapeRecord(shape, s.model.Colors[i])}
		if i < len(s.model.Scores) {
			ds.S = s.model.Scores[i]
		}
		doc.Shapes = append(doc.Shapes, ds)
	}

	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	zw := gzip.NewWriter(file)
	if err := json.NewEncoder(zw).Encode(&doc); err != nil {
		return err
	}
	return zw.Close()
}

// ReadDocument parses a .prim file (gzipped or plain JSON).
func ReadDocument(path string) (*Document, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var reader io.Reader = bytes.NewReader(raw)
	if len(raw) >= 2 && raw[0] == 0x1f && raw[1] == 0x8b {
		zr, err := gzip.NewReader(reader)
		if err != nil {
			return nil, fmt.Errorf("corrupt document: %w", err)
		}
		defer zr.Close()
		reader = zr
	}
	var doc Document
	if err := json.NewDecoder(reader).Decode(&doc); err != nil {
		return nil, fmt.Errorf("could not read document: %w", err)
	}
	if doc.Version < 1 || len(doc.Shapes) == 0 {
		return nil, fmt.Errorf("document is empty or from an unknown version")
	}
	return &doc, nil
}

// LoadedDocument is what a frontend needs to present a reopened document.
type LoadedDocument struct {
	Session   *RenderSession
	InputPath string // temp file holding the embedded source
	Started   StartedPayload
	Shapes    []ShapeRecord
	StepsDone int
	Score     float64
	ElapsedMs int64
}

// OpenDocument rebuilds a render session from a document: the embedded
// source is written to a temp file (so re-rendering and inspection work like
// any loaded image) and the model is reconstructed shape by shape with the
// stored colors — no recomputation. The returned session is already "done":
// it cannot step, but Export and SaveDocument work on it.
func OpenDocument(path, id string, emit func(string, any)) (*LoadedDocument, error) {
	doc, err := ReadDocument(path)
	if err != nil {
		return nil, err
	}

	origImg, _, err := image.Decode(bytes.NewReader(doc.Source))
	if err != nil {
		return nil, fmt.Errorf("embedded source image is unreadable: %w", err)
	}

	// Materialize the source so restart/re-render behaves like a normal load.
	stem := strings.TrimSuffix(doc.SourceName, filepath.Ext(doc.SourceName))
	if stem == "" {
		stem = "prim-source"
	}
	tmp, err := os.CreateTemp("", stem+"-*"+filepath.Ext(doc.SourceName))
	if err != nil {
		return nil, err
	}
	if _, err := tmp.Write(doc.Source); err != nil {
		tmp.Close()
		return nil, err
	}
	tmp.Close()

	params := doc.Params
	params.InputPath = tmp.Name()

	input := origImg
	if params.InputResize > 0 {
		input, err = LoadInput(tmp.Name(), params.InputResize)
		if err != nil {
			return nil, err
		}
	}

	bg := primitive.MakeHexColor(doc.Background)
	workers := params.Workers
	if workers < 1 {
		workers = runtime.NumCPU()
	}
	model := primitive.NewModel(input, bg, doc.OutputSize, workers)
	for _, ds := range doc.Shapes {
		shape, ok := shapeFromRecord(ds.ShapeRecord)
		if !ok {
			continue
		}
		c := primitive.MakeHexColor(ds.C)
		model.Shapes = append(model.Shapes, shape)
		model.Colors = append(model.Colors, c)
		model.Scores = append(model.Scores, ds.S)
		model.Context.SetRGBA255(c.R, c.G, c.B, c.A)
		shape.Draw(model.Context, model.Scale)
	}
	model.Score = doc.Score

	// A pre-cancelled session: Done() is true and stepping is idle, but the
	// model is live for Export/SaveDocument — and Continue() can pick it
	// back up (needsRebuild replays the working raster first).
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	s := &RenderSession{ID: id, params: params, ctx: ctx, cancel: cancel, emit: emit}
	s.pauseCond = sync.NewCond(&s.pauseMu)
	s.model = model
	s.stepsDone = doc.StepsDone
	s.lastShapeIdx = len(model.Shapes)
	s.needsRebuild = true

	shapes := make([]ShapeRecord, 0, len(doc.Shapes))
	for _, ds := range doc.Shapes {
		shapes = append(shapes, ds.ShapeRecord)
	}

	return &LoadedDocument{
		Session:   s,
		InputPath: tmp.Name(),
		Started: StartedPayload{
			SessionID:   id,
			Width:       model.Sw,
			Height:      model.Sh,
			Scale:       model.Scale,
			Background:  doc.Background,
			TotalShapes: doc.StepsDone,
			PreviewMode: PreviewSVG,
			InputW:      input.Bounds().Dx(),
			InputH:      input.Bounds().Dy(),
		},
		Shapes:    shapes,
		StepsDone: doc.StepsDone,
		Score:     doc.Score,
		ElapsedMs: doc.ElapsedMs,
	}, nil
}

// shapeFromRecord is the inverse of makeShapeRecord. Worker stays nil — fine
// for Draw/SVG/Copy; only stepping needs a worker, and loaded sessions never
// step.
func shapeFromRecord(rec ShapeRecord) (primitive.Shape, bool) {
	p := rec.P
	switch rec.T {
	case "tri":
		if len(p) < 6 {
			return nil, false
		}
		return &primitive.Triangle{
			X1: int(p[0]), Y1: int(p[1]),
			X2: int(p[2]), Y2: int(p[3]),
			X3: int(p[4]), Y3: int(p[5]),
		}, true
	case "rect":
		if len(p) < 4 {
			return nil, false
		}
		return &primitive.Rectangle{
			X1: int(p[0]), Y1: int(p[1]),
			X2: int(p[2]), Y2: int(p[3]),
		}, true
	case "rrect":
		if len(p) < 5 {
			return nil, false
		}
		return &primitive.RotatedRectangle{
			X: int(p[0]), Y: int(p[1]),
			Sx: int(p[2]), Sy: int(p[3]),
			Angle: int(p[4]),
		}, true
	case "ell":
		if len(p) < 4 {
			return nil, false
		}
		return &primitive.Ellipse{
			X: int(p[0]), Y: int(p[1]),
			Rx: int(p[2]), Ry: int(p[3]),
			Circle: p[2] == p[3],
		}, true
	case "rell":
		if len(p) < 5 {
			return nil, false
		}
		return &primitive.RotatedEllipse{
			X: p[0], Y: p[1], Rx: p[2], Ry: p[3], Angle: p[4],
		}, true
	case "quad":
		if len(p) < 6 {
			return nil, false
		}
		return &primitive.Quadratic{
			X1: p[0], Y1: p[1], X2: p[2], Y2: p[3], X3: p[4], Y3: p[5],
			Width: rec.W,
		}, true
	case "poly":
		if len(p) < 6 || len(p)%2 != 0 {
			return nil, false
		}
		poly := &primitive.Polygon{Order: len(p) / 2}
		for i := 0; i+1 < len(p); i += 2 {
			poly.X = append(poly.X, p[i])
			poly.Y = append(poly.Y, p[i+1])
		}
		return poly, true
	default:
		return nil, false
	}
}

