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

// Run modes. Count reproduces the CLI behavior; the other three come from
// the legacy macOS app: open-ended runs, a similarity target, and painting
// shapes under the cursor.
const (
	RunCount   = "count"
	RunForever = "forever"
	RunScore   = "score"
	RunDraw    = "draw"
)

// Params mirrors the CLI flags. Zero values mean "auto" everywhere the CLI
// uses a sentinel: Alpha 0 = per-shape auto, InputResize 0 = full resolution,
// OutputSize 0 = match input's largest dimension, Background "" = average
// color, Workers 0 = all cores, StrokeWidth 0 = optimizer-varied.
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
	StrokeWidth float64          `json:"strokeWidth"` // bezier stroke width; 0 = auto
	RunMode     string           `json:"runMode"`     // "" or RunCount/RunForever/RunScore/RunDraw
	TargetScore float64          `json:"targetScore"` // similarity %, for RunScore
	// EmitShapeData switches the preview stream from SVG fragment strings to
	// structured ShapeRecords, and disables the raster fallback (that limit
	// exists only because WKWebView chokes on huge SVG DOMs; native renderers
	// draw incrementally and handle any count).
	EmitShapeData bool `json:"emitShapeData,omitempty"`
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

// unbounded reports whether the run has no predetermined shape count.
func (p *Params) unbounded() bool {
	switch p.RunMode {
	case RunForever, RunScore, RunDraw:
		return true
	}
	return false
}

// totalSteps returns the target step count, or 0 for unbounded runs.
func (p *Params) totalSteps() int {
	if p.unbounded() {
		return 0
	}
	total := 0
	for _, s := range p.stages() {
		total += s.Count
	}
	return total
}

// similarityPct converts the model's RMSE score into the friendly percentage
// the legacy app displayed.
func similarityPct(score float64) float64 {
	p := (1 - score) * 100
	if p < 0 {
		return 0
	}
	return p
}

func (p *Params) Validate() error {
	if p.InputPath == "" {
		return fmt.Errorf("no input image selected")
	}
	switch p.RunMode {
	case "", RunCount, RunForever, RunScore, RunDraw:
	default:
		return fmt.Errorf("unknown run mode %q", p.RunMode)
	}
	if p.RunMode == RunScore && (p.TargetScore <= 0 || p.TargetScore >= 100) {
		return fmt.Errorf("target similarity must be between 0 and 100%%")
	}
	if p.StrokeWidth < 0 || p.StrokeWidth > 64 {
		return fmt.Errorf("stroke width must be between 0 (auto) and 64")
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
	// needsRebuild marks a document-loaded model whose working raster must
	// be replayed before stepping can continue.
	needsRebuild bool
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

// Continue picks a finished (or document-loaded) session back up with new
// params: same input, same shapes so far, then more shapes on top — possibly
// in a different mode. For count mode, ShapeCount is the total target.
func (s *RenderSession) Continue(parent context.Context, p Params) error {
	if !s.Done() {
		return fmt.Errorf("the render is still active")
	}
	s.mu.Lock()
	model := s.model
	s.mu.Unlock()
	if model == nil {
		return fmt.Errorf("nothing to continue yet")
	}
	p.InputPath = s.params.InputPath
	p.EmitShapeData = s.params.EmitShapeData
	if err := p.Validate(); err != nil {
		return err
	}
	if !p.unbounded() && p.ShapeCount <= s.stepsDone {
		return fmt.Errorf("raise the shape count above %s to continue, or switch run mode", formatInt(s.stepsDone))
	}
	s.params = p
	s.ctx, s.cancel = context.WithCancel(parent)
	s.pauseMu.Lock()
	s.paused = false
	s.pauseMu.Unlock()
	go s.runContinue()
	return nil
}

func formatInt(n int) string {
	out := fmt.Sprintf("%d", n)
	for i := len(out) - 3; i > 0; i -= 3 {
		out = out[:i] + "," + out[i:]
	}
	return out
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

// configureEngine sets the per-run engine globals. Safe before a run's
// workers start stepping; only one session renders at a time.
func (s *RenderSession) configureEngine() {
	if s.params.StrokeWidth > 0 {
		primitive.QuadraticWidth = s.params.StrokeWidth
		primitive.QuadraticWidthMutate = false
	} else {
		primitive.QuadraticWidth = 1
		primitive.QuadraticWidthMutate = true
	}
	primitive.ClearFocus()
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

	s.configureEngine()
	defer primitive.ClearFocus()

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

	s.renderLoop(model, p.stages(), total)
}

// runContinue picks up a finished or document-loaded session and keeps
// adding shapes with the (possibly changed) current params. For count mode,
// ShapeCount is the TOTAL target; unbounded modes behave as usual.
func (s *RenderSession) runContinue() {
	p := s.params

	s.configureEngine()
	defer primitive.ClearFocus()

	s.mu.Lock()
	model := s.model
	if s.needsRebuild {
		model.RebuildCurrent()
		s.needsRebuild = false
	}
	s.mu.Unlock()

	total := 0
	stage := Stage{Count: 1, Mode: p.Mode, Alpha: p.Alpha, Repeat: p.Repeat}
	if !p.unbounded() {
		total = p.ShapeCount
		stage.Count = total - s.stepsDone
	}

	s.emit(EvtStarted, StartedPayload{
		SessionID:   s.ID,
		Width:       model.Sw,
		Height:      model.Sh,
		Scale:       model.Scale,
		Background:  hexString(model.Background),
		TotalShapes: total,
		PreviewMode: PreviewSVG,
		InputW:      model.Target.Bounds().Dx(),
		InputH:      model.Target.Bounds().Dy(),
		Resumed:     true,
	})

	s.renderLoop(model, []Stage{stage}, total)
}

// renderLoop is the shared heart of run and runContinue: step, batch, emit,
// honor pause/cancel/brush, finish.
func (s *RenderSession) renderLoop(model *primitive.Model, stages []Stage, total int) {
	p := s.params
	start := time.Now()
	lastFlush := start
	var fragments []string
	var records []ShapeRecord
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
		} else if p.EmitShapeData {
			batch.Shapes = records
		} else {
			batch.Fragments = fragments
		}
		fragments = nil
		records = nil
		lastFlush = time.Now()
		s.emit(EvtBatch, batch)
	}

	// stepOnce runs one engine step and all bookkeeping; true = cancelled.
	stepOnce := func(stage Stage) bool {
		if s.waitIfPaused() {
			return true
		}

		stepStart := time.Now()
		s.mu.Lock()
		model.Step(primitive.ShapeType(stage.Mode), stage.Alpha, stage.Repeat)
		addedFrags, addedRecs := s.collectNewShapes()
		s.mu.Unlock()
		s.stepsDone++

		addedCount := len(addedFrags) + len(addedRecs)
		stepDur := time.Since(stepStart).Seconds()
		if stepDur > 0 {
			instant := float64(addedCount) / stepDur
			if rate == 0 {
				rate = instant
			} else {
				rate = rate*0.9 + instant*0.1
			}
		}

		if !s.previewRaster {
			fragments = append(fragments, addedFrags...)
			records = append(records, addedRecs...)
			// The raster fallback exists for WKWebView's SVG-DOM limits;
			// structured-data consumers render incrementally at any count.
			if !p.EmitShapeData && s.lastShapeIdx > svgPreviewShapeLimit {
				s.previewRaster = true
			}
		}

		if len(fragments)+len(records) >= batchMaxFragments || time.Since(lastFlush) >= batchFlushInterval {
			flush()
		}

		s.maybeAutoSave()
		return false
	}

	// waitForBrush idles (drawing mode) until the user paints; false = cancelled.
	waitForBrush := func() bool {
		for !primitive.FocusActive() {
			if s.waitIfPaused() {
				return false
			}
			select {
			case <-s.ctx.Done():
				return false
			case <-time.After(50 * time.Millisecond):
			}
		}
		return true
	}

	cancelled := false
	if p.unbounded() {
		stage := stages[0]
		for {
			if p.RunMode == RunScore && similarityPct(model.Score) >= p.TargetScore {
				break
			}
			if p.RunMode == RunDraw && !waitForBrush() {
				cancelled = true
				break
			}
			if stepOnce(stage) {
				cancelled = true
				break
			}
		}
	} else {
	outer:
		for _, stage := range stages {
			for i := 0; i < stage.Count; i++ {
				if stepOnce(stage) {
					cancelled = true
					break outer
				}
			}
		}
	}
	flush()
	s.finish(start, cancelled)
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

// collectNewShapes serializes shapes appended since the last call (Step adds
// 1 + repeat shapes) — as SVG fragment strings matching Model.SVG() exactly,
// or as structured ShapeRecords when EmitShapeData is set. Caller must hold
// s.mu.
func (s *RenderSession) collectNewShapes() ([]string, []ShapeRecord) {
	var frags []string
	var recs []ShapeRecord
	for i := s.lastShapeIdx; i < len(s.model.Shapes); i++ {
		c := s.model.Colors[i]
		if s.params.EmitShapeData {
			recs = append(recs, makeShapeRecord(s.model.Shapes[i], c))
		} else {
			attrs := fmt.Sprintf("fill=\"#%02x%02x%02x\" fill-opacity=\"%f\"", c.R, c.G, c.B, float64(c.A)/255)
			frags = append(frags, s.model.Shapes[i].SVG(attrs))
		}
	}
	s.lastShapeIdx = len(s.model.Shapes)
	return frags, recs
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
