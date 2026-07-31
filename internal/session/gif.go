package session

import (
	"image"
	"image/color"
	"image/draw"
	"image/gif"
	"os"

	"github.com/ericpauley/go-quantize/quantize"
	"github.com/nfnt/resize"
)

// SaveAnimatedGIF encodes frames as a looping animated GIF natively — no
// ImageMagick dependency. A single median-cut palette is computed from the
// final (most detailed) frame and shared across all frames so colors stay
// stable as shapes accumulate. Delays are in centiseconds, matching both
// image/gif and the ImageMagick -delay units the CLI used.
func SaveAnimatedGIF(path string, frames []image.Image, delayCS, lastDelayCS, maxDim int) error {
	if maxDim > 0 {
		resized := make([]image.Image, len(frames))
		for i, f := range frames {
			resized[i] = resize.Thumbnail(uint(maxDim), uint(maxDim), f, resize.Bilinear)
		}
		frames = resized
	}

	q := quantize.MedianCutQuantizer{}
	palette := q.Quantize(make([]color.Color, 0, 256), frames[len(frames)-1])

	g := &gif.GIF{LoopCount: 0}
	for i, src := range frames {
		dst := image.NewPaletted(src.Bounds(), palette)
		draw.FloydSteinberg.Draw(dst, dst.Rect, src, image.Point{})
		g.Image = append(g.Image, dst)
		if i == len(frames)-1 {
			g.Delay = append(g.Delay, lastDelayCS)
		} else {
			g.Delay = append(g.Delay, delayCS)
		}
	}

	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	return gif.EncodeAll(file, g)
}
