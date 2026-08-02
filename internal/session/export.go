package session

import (
	"fmt"
	"image"
	"os"
	"path/filepath"
	"strings"

	"github.com/fogleman/gg"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

type ExportOptions struct {
	Dir         string      `json:"dir"`
	BaseName    string      `json:"baseName"`
	Formats     []string    `json:"formats"`
	JPEGQuality int         `json:"jpegQuality"`
	GIF         *GIFOptions `json:"gif,omitempty"`
	// TransparentBackground omits the background from PNG and SVG output
	// (shapes only, alpha canvas). JPEG and GIF have no alpha and keep the
	// background regardless. Rendering still optimizes against the
	// background color either way.
	TransparentBackground bool `json:"transparentBackground,omitempty"`
}

type GIFOptions struct {
	ScoreDelta  float64 `json:"scoreDelta"`
	DelayCS     int     `json:"delayCS"`
	LastDelayCS int     `json:"lastDelayCS"`
	MaxDim      int     `json:"maxDim"`
}

func defaultGIFOptions() GIFOptions {
	return GIFOptions{ScoreDelta: 0.001, DelayCS: 50, LastDelayCS: 250, MaxDim: 640}
}

// DefaultBaseName reproduces the naming scheme <inputStem>-m<mode>-n<steps>.
func (s *RenderSession) DefaultBaseName() string {
	stem := strings.TrimSuffix(filepath.Base(s.params.InputPath), filepath.Ext(s.params.InputPath))
	return fmt.Sprintf("%s-m%d-n%d", stem, s.params.Mode, s.stepsDone)
}

// Export writes the current model in every requested format and returns the
// written paths. Safe to call mid-run (it takes the model lock between steps),
// while paused, after cancellation, or after completion.
func (s *RenderSession) Export(opts ExportOptions) ([]string, error) {
	if s.model == nil {
		return nil, fmt.Errorf("nothing to export yet")
	}
	if opts.Dir == "" {
		return nil, fmt.Errorf("no output folder selected")
	}
	if len(opts.Formats) == 0 {
		return nil, fmt.Errorf("no output formats selected")
	}
	if opts.BaseName == "" {
		opts.BaseName = s.DefaultBaseName()
	}
	if opts.JPEGQuality < 1 || opts.JPEGQuality > 100 {
		opts.JPEGQuality = 95
	}
	if err := os.MkdirAll(opts.Dir, 0o755); err != nil {
		return nil, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	var paths []string
	for _, format := range opts.Formats {
		path := filepath.Join(opts.Dir, opts.BaseName+"."+format)
		var err error
		switch strings.ToLower(format) {
		case "png":
			if opts.TransparentBackground {
				err = primitive.SavePNG(path, renderShapesOnly(s.model))
			} else {
				err = primitive.SavePNG(path, s.model.Context.Image())
			}
		case "jpg", "jpeg":
			err = primitive.SaveJPG(path, s.model.Context.Image(), opts.JPEGQuality)
		case "svg":
			if opts.TransparentBackground {
				err = primitive.SaveFile(path, s.model.SVGShapesOnly())
			} else {
				err = primitive.SaveFile(path, s.model.SVG())
			}
		case "gif":
			gifOpts := defaultGIFOptions()
			if opts.GIF != nil {
				gifOpts = *opts.GIF
			}
			frames := s.model.Frames(gifOpts.ScoreDelta)
			err = SaveAnimatedGIF(path, frames, gifOpts.DelayCS, gifOpts.LastDelayCS, gifOpts.MaxDim)
		default:
			err = fmt.Errorf("unrecognized format: %s", format)
		}
		if err != nil {
			return paths, fmt.Errorf("writing %s: %w", filepath.Base(path), err)
		}
		paths = append(paths, path)
	}
	if s.emit != nil {
		s.emit(EvtExported, ExportedPayload{SessionID: s.ID, Paths: paths})
	}
	return paths, nil
}

// renderShapesOnly draws every shape onto a transparent canvas at output
// size — the raster counterpart of SVGShapesOnly.
func renderShapesOnly(model *primitive.Model) image.Image {
	dc := gg.NewContext(model.Sw, model.Sh)
	dc.Scale(model.Scale, model.Scale)
	dc.Translate(0.5, 0.5)
	for i, shape := range model.Shapes {
		c := model.Colors[i]
		dc.SetRGBA255(c.R, c.G, c.B, c.A)
		shape.Draw(dc, model.Scale)
	}
	return dc.Image()
}

// writeCheckpoint writes the numbered frame files for auto-save. Called from
// the run loop between steps, so it takes the model lock itself.
func (s *RenderSession) writeCheckpoint(as *AutoSaveOptions) error {
	if as.Dir == "" {
		return fmt.Errorf("no checkpoint folder selected")
	}
	if err := os.MkdirAll(as.Dir, 0o755); err != nil {
		return err
	}
	base := as.BaseName
	if base == "" {
		base = strings.TrimSuffix(filepath.Base(s.params.InputPath), filepath.Ext(s.params.InputPath))
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, format := range as.Formats {
		path := filepath.Join(as.Dir, fmt.Sprintf("%s-%04d.%s", base, s.stepsDone, format))
		var err error
		switch strings.ToLower(format) {
		case "png":
			err = primitive.SavePNG(path, s.model.Context.Image())
		case "jpg", "jpeg":
			err = primitive.SaveJPG(path, s.model.Context.Image(), 95)
		case "svg":
			err = primitive.SaveFile(path, s.model.SVG())
		default:
			err = fmt.Errorf("unrecognized checkpoint format: %s", format)
		}
		if err != nil {
			return err
		}
	}
	return nil
}
