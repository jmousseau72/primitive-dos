// Command appicon generates build/appicon.png — the app icon, rendered by
// the app's own engine: a glowing orb is drawn, reconstructed as quadratic
// bezier strokes, and composited into a macOS squircle. Regenerate with:
//
//	go run ./cmd/appicon
//
// The engine is stochastic, so each run produces a sibling of the committed
// icon, never an identical twin.
package main

import (
	"image/color"
	"log"

	"github.com/fogleman/gg"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

const (
	canvas  = 1024 // full icon canvas
	plate   = 824  // macOS squircle plate size, centered
	radius  = 186  // corner radius of the plate
	srcSize = 512  // source image fed to the engine
	steps   = 320  // bezier shapes — few enough that strokes stay visible
	strokeW = 4.5  // stroke width in source coords (scales up with output)
	darkHex = "16161c"
	workers = 8
)

// drawSource paints the image the engine will reconstruct: a warm gradient
// orb floating on the app's dark background, lit from the upper left.
func drawSource() *gg.Context {
	dc := gg.NewContext(srcSize, srcSize)
	dc.SetHexColor(darkHex)
	dc.Clear()

	cx, cy := float64(srcSize)*0.5, float64(srcSize)*0.52
	r := float64(srcSize) * 0.36

	grad := gg.NewRadialGradient(cx-r*0.35, cy-r*0.45, r*0.1, cx, cy, r*1.15)
	grad.AddColorStop(0.0, color.RGBA{0xff, 0xd9, 0x7a, 0xff})  // sunlit gold
	grad.AddColorStop(0.35, color.RGBA{0xff, 0x9f, 0x45, 0xff}) // orange
	grad.AddColorStop(0.7, color.RGBA{0xf2, 0x4f, 0x7c, 0xff})  // magenta
	grad.AddColorStop(1.0, color.RGBA{0x4c, 0x2a, 0x8f, 0xff})  // deep violet rim
	dc.SetFillStyle(grad)
	dc.DrawCircle(cx, cy, r)
	dc.Fill()

	return dc
}

func main() {
	src := drawSource()

	// Reconstruct the orb with the engine, exactly as the app would.
	primitive.QuadraticWidth = strokeW
	primitive.QuadraticWidthMutate = false
	bg := primitive.MakeHexColor(darkHex)
	model := primitive.NewModel(src.Image(), bg, plate, workers)
	for i := 0; i < steps; i++ {
		model.Step(primitive.ShapeTypeQuadratic, 255, 0)
		if (i+1)%100 == 0 {
			log.Printf("%d/%d shapes, score %.5f", i+1, steps, model.Score)
		}
	}
	rendered := model.Context.Image()

	// Composite onto the transparent 1024 canvas inside a squircle plate.
	out := gg.NewContext(canvas, canvas)
	offset := float64(canvas-plate) / 2
	out.DrawRoundedRectangle(offset, offset, plate, plate, radius)
	out.Clip()
	out.DrawImage(rendered, int(offset), int(offset))
	out.ResetClip()

	// Faint rim light for a little depth, like native icons.
	out.SetRGBA(1, 1, 1, 0.06)
	out.SetLineWidth(3)
	out.DrawRoundedRectangle(offset+1.5, offset+1.5, plate-3, plate-3, radius-1.5)
	out.Stroke()

	if err := out.SavePNG("build/appicon.png"); err != nil {
		log.Fatal(err)
	}
	log.Println("wrote build/appicon.png")
}
