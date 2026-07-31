package session

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"image/jpeg"
	"runtime"
	"sync"
	"time"

	"github.com/nfnt/resize"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

// Tunables for the live preview event stream.
const (
	// Above this many cumulative shapes the preview switches from streamed
	// SVG fragments to throttled raster snapshots (WKWebView chokes on very
	// large SVG DOMs).
	svgPreviewShapeLimit = 20000
	// Minimum interval between raster snapshots sent to the frontend.
	snapshotMinInterval = 500 * time.Millisecond
	// Snapshots are downscaled to at most this dimension before encoding.
	snapshotMaxDim = 1024
	// Batch flush thresholds: whichever comes first.
	batchFlushInterval = 150 * time.Millisecond
	batchMaxFragments  = 200
)

// Params mirrors the CLI flags. Zero values mean "auto" everywhere the CLI
// uses a sentinel: Alpha 0 = per-shape auto, InputResize 0 = full resolution,
// OutputSize 0 = match input's largest dimension, Background "" = average
// color, Workers 0 = all cores.
type Params struct {
	InputPath   string           `json:"inputPath"`
	Mode        int              `json:"mode"`
	ShapeCount  int              `json:"shapeCount"`
	Alpha       int              `json:"alpha"`
	Repeat      int              `json:"repeat"`
	InputResize int              `json:"inputResize"`
	OutputSize  int              `json:"outputSize"`
	Background  string           `json:"background"`
	Workers     int              `json:"workers"`
	AutoSave    *AutoSaveOptions `json:"autoSave,omitempty"`
	// Stages, when non-empty, overrides Mode/ShapeCount/Alpha/Repeat and
	// reproduces the CLI's repeatable -n flag.
	Stages []Stage `json:"stages,omitempty"`
}

type Stage struct {
	Count  int `json:"count"`
	Mode   int `json:"mode"`
	Alpha  int `json:"alpha"`
	Repeat int `json:"repeat"`
}

// AutoSaveOptions reproduces the CLI's %04d checkpoint-frame habit: every Nth
// step, write BaseName-NNNN.<fmt> for each requested format.
type AutoSaveOptions struct {
	Dir      string   `json:"dir"`
	BaseName string   `json:"baseName"`
	Formats  []string `json:"formats"`
	Nth      int      `json:"nth"`
}

func (p *Params) stages() []Stage {
	if len(p.Stages) > 0 {
		return p.Stages
	}
	return []Stage{{Count: p.ShapeCount, Mode: p.Mode, Alpha: p.Alpha, Repeat: p.Repeat}}
}

func (p *Params) totalSteps() int {
	total := 0
	for _, s := range p.stages() {
		total += s.Count
	}
	return total
}

func (p *Params) Validate() error {
	if p.InputPath == "" {
		return fmt.Errorf("no input image selected")
	}
	for _, s := range p.stages() {
		if s.Count < 1 {
			return fmt.Errorf("shape count must be at least 1")
		}
		if s.Mode < 0 || s.Mode > 8 {
			return fmt.Errorf("mode must be between 0 and 8")
		}
		if s.Alpha < 0 || s.Alpha > 255 {
			return fmt.Errorf("alpha must be between 0 (auto) and 255")
		}
		if s.Repeat < 0 {
			return fmt.Errorf("repeat must not be negative")
		}
	}
	return nil
}

// RenderSession drives a primitive.Model step by step, emitting progress
// events, honoring pause/cancel between steps, and allowing export at any
// point (the model stays valid mid-run and after cancellation).
type RenderSession struct {
	ID     string
	params Params

	ctx    context.Context
	cancel context.CancelFunc
	emit   func(event string, payload any)

	mu    sync.Mutex // guards model and inputStem during Step vs Export
	model *primitive.Model

	pauseMu   sync.Mutex
	pauseCond *sync.Cond
	paused    bool

	stepsDone     int // atomic-ish: only written by run loop, read via mu on export naming
	autoSaveDead  bool
	lastShapeIdx  int
	previewRaster bool
	lastSnapshot  time.Time
}

func New(parent context.Context, id string, p Params, emit func(string, any)) (*RenderSession, error) {
	if err := p.Validate(); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithCancel(parent)
	s := &RenderSession{ID: id, params: p, ctx: ctx, cancel: cancel, emit: emit}
	s.pauseCond = sync.NewCond(&s.pauseMu)
	return s, nil
}

func (s *RenderSession) Params() Params { return s.params }

// Start launches the render loop in its own goroutine and returns immediately.
func (s *RenderSession) Start() {
	go s.run()
}

func (s *RenderSession) Pause() {
	s.pauseMu.Lock()
	if !s.paused {
		s.paused = true
		s.emit(EvtPaused, StatePayload{SessionID: s.ID, ShapesDone: s.stepsDone})
	}
	s.pauseMu.Unlock()
}

func (s *RenderSession) Resume() {
	s.pauseMu.Lock()
	if s.paused {
		s.paused = false
		s.emit(EvtResumed, StatePayload{SessionID: s.ID, ShapesDone: s.stepsDone})
	}
	s.pauseMu.Unlock()
	s.pauseCond.Broadcast()
}

// Cancel stops the run after the in-flight Step finishes. The model remains
// valid, so "cancel then export" is supported deliberately.
func (s *RenderSession) Cancel() {
	s.cancel()
	s.Resume() // wake the loop if it is parked in pause
}

func (s *RenderSession) Done() bool {
	select {
	case <-s.ctx.Done():
		return true
	default:
		return false
	}
}

// waitIfPaused parks between steps while paused. Returns true if cancelled.
func (s *RenderSession) waitIfPaused() bool {
	s.pauseMu.Lock()
	for s.paused && s.ctx.Err() == nil {
		s.pauseCond.Wait()
	}
	s.pauseMu.Unlock()
	return s.ctx.Err() != nil
}

func (s *RenderSession) fail(format string, args ...any) {
	s.cancel()
	s.emit(EvtError, ErrorPayload{SessionID: s.ID, Message: fmt.Sprintf(format, args...)})
}

func (s *RenderSession) run() {
	p := s.params

	input, err := LoadInput(p.InputPath, p.InputResize)
	if err != nil {
		s.fail("could not load image: %v", err)
		return
	}
	inputW := input.Bounds().Dx()
	inputH := input.Bounds().Dy()

	outputSize := p.OutputSize
	if outputSize <= 0 {
		outputSize = maxInt(inputW, inputH)
	}
	workers := p.Workers
	if workers < 1 {
		workers = runtime.NumCPU()
	}
	bg := ResolveBackground(input, p.Background)

	s.mu.Lock()
	s.model = primitive.NewModel(input, bg, outputSize, workers)
	model := s.model
	s.mu.Unlock()

	total := p.totalSteps()
	s.emit(EvtStarted, StartedPayload{
		SessionID:   s.ID,
		Width:       model.Sw,
		Height:      model.Sh,
		Scale:       model.Scale,
		Background:  hexString(bg),
		TotalShapes: total,
		PreviewMode: PreviewSVG,
		InputW:      inputW,
		InputH:      inputH,
	})

	start := time.Now()
	lastFlush := start
	var fragments []string
	rate := 0.0

	flush := func() {
		batch := BatchPayload{
			SessionID:    s.ID,
			PreviewMode:  PreviewSVG,
			ShapesDone:   s.stepsDone,
			TotalShapes:  total,
			Score:        model.Score,
			ElapsedMs:    time.Since(start).Milliseconds(),
			ShapesPerSec: rate,
		}
		if s.previewRaster {
			batch.PreviewMode = PreviewRaster
			if time.Since(s.lastSnapshot) >= snapshotMinInterval {
				batch.SnapshotJpeg = s.encodeSnapshot()
				s.lastSnapshot = time.Now()
			}
		} else {
			batch.Fragments = fragments
		}
		fragments = nil
		lastFlush = time.Now()
		s.emit(EvtBatch, batch)
	}

	for _, stage := range p.stages() {
		for i := 0; i < stage.Count; i++ {
			if s.waitIfPaused() {
				flush()
				s.finish(start, true)
				return
			}

			stepStart := time.Now()
			s.mu.Lock()
			model.Step(primitive.ShapeType(stage.Mode), stage.Alpha, stage.Repeat)
			added := s.collectNewShapes()
			s.mu.Unlock()
			s.stepsDone++

			stepDur := time.Since(stepStart).Seconds()
			if stepDur > 0 {
				instant := float64(len(added)) / stepDur
				if rate == 0 {
					rate = instant
				} else {
					rate = rate*0.9 + instant*0.1
				}
			}

			if !s.previewRaster {
				fragments = append(fragments, added...)
				if s.lastShapeIdx > svgPreviewShapeLimit {
					s.previewRaster = true
				}
			}

			if len(fragments) >= batchMaxFragments || time.Since(lastFlush) >= batchFlushInterval {
				flush()
			}

			s.maybeAutoSave()
		}
	}
	flush()
	s.finish(start, false)
}

func (s *RenderSession) finish(start time.Time, cancelled bool) {
	s.cancel()
	s.mu.Lock()
	score := s.model.Score
	s.mu.Unlock()
	s.emit(EvtDone, DonePayload{
		SessionID:  s.ID,
		Cancelled:  cancelled,
		ShapesDone: s.stepsDone,
		Score:      score,
		ElapsedMs:  time.Since(start).Milliseconds(),
	})
}

// collectNewShapes renders SVG fragments for shapes appended since the last
// call (Step adds 1 + repeat shapes). The attrs format matches Model.SVG()
// exactly, so the streamed preview is built from the same strings the final
// SVG export will contain. Caller must hold s.mu.
func (s *RenderSession) collectNewShapes() []string {
	var out []string
	for i := s.lastShapeIdx; i < len(s.model.Shapes); i++ {
		c := s.model.Colors[i]
		attrs := fmt.Sprintf("fill=\"#%02x%02x%02x\" fill-opacity=\"%f\"", c.R, c.G, c.B, float64(c.A)/255)
		out = append(out, s.model.Shapes[i].SVG(attrs))
	}
	s.lastShapeIdx = len(s.model.Shapes)
	return out
}

// encodeSnapshot returns a base64 JPEG of the current canvas, downscaled so
// full-resolution renders never travel across the event bridge.
func (s *RenderSession) encodeSnapshot() string {
	s.mu.Lock()
	img := s.model.Context.Image()
	s.mu.Unlock()
	b := img.Bounds()
	if maxInt(b.Dx(), b.Dy()) > snapshotMaxDim {
		img = resize.Thumbnail(snapshotMaxDim, snapshotMaxDim, img, resize.Bilinear)
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 80}); err != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(buf.Bytes())
}

func (s *RenderSession) maybeAutoSave() {
	as := s.params.AutoSave
	if as == nil || s.autoSaveDead || as.Nth < 1 || s.stepsDone%as.Nth != 0 {
		return
	}
	if err := s.writeCheckpoint(as); err != nil {
		// Surface once, then stop trying rather than spamming errors every
		// Nth step (e.g. the target volume was unmounted mid-run).
		s.autoSaveDead = true
		s.emit(EvtError, ErrorPayload{
			SessionID: s.ID,
			Message:   fmt.Sprintf("checkpoint save failed (auto-save disabled for this run): %v", err),
		})
	}
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
