// Command docicon generates build/docicon.png — the .prim document icon: a
// classic macOS page with a folded corner, carrying a small engine-rendered
// bezier orb. Regenerate with:
//
//	go run ./cmd/docicon
//
// Then rebuild macos/PrimitiveDos/PrimDocument.icns from it (see
// macos/Scripts/build-bridge.sh notes for the sips/iconutil recipe).
package main

import (
	"image/color"
	"log"

	"github.com/fogleman/gg"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

const (
	canvas  = 1024
	pageW   = 640.0
	pageH   = 832.0
	fold    = 168.0 // folded-corner size
	corner  = 28.0
	srcSize = 512
	steps   = 260
	strokeW = 4.0
	workers = 8
)

func drawOrbSource() *gg.Context {
	dc := gg.NewContext(srcSize, srcSize)
	// Transparent-ish backdrop matching the page so strokes blend onto it.
	dc.SetHexColor("f2f2f5")
	dc.Clear()

	cx, cy := float64(srcSize)*0.5, float64(srcSize)*0.52
	r := float64(srcSize) * 0.4

	grad := gg.NewRadialGradient(cx-r*0.35, cy-r*0.45, r*0.1, cx, cy, r*1.15)
	grad.AddColorStop(0.0, color.RGBA{0xff, 0xd9, 0x7a, 0xff})
	grad.AddColorStop(0.35, color.RGBA{0xff, 0x9f, 0x45, 0xff})
	grad.AddColorStop(0.7, color.RGBA{0xf2, 0x4f, 0x7c, 0xff})
	grad.AddColorStop(1.0, color.RGBA{0x4c, 0x2a, 0x8f, 0xff})
	dc.SetFillStyle(grad)
	dc.DrawCircle(cx, cy, r)
	dc.Fill()
	return dc
}

func main() {
	// The orb, reconstructed by the engine like the app icon — the document
	// wears the same artwork the app does.
	primitive.QuadraticWidth = strokeW
	primitive.QuadraticWidthMutate = false
	src := drawOrbSource()
	bg := primitive.MakeHexColor("f2f2f5")
	model := primitive.NewModel(src.Image(), bg, 460, workers)
	for i := 0; i < steps; i++ {
		model.Step(primitive.ShapeTypeQuadratic, 255, 0)
	}
	orb := model.Context.Image()

	out := gg.NewContext(canvas, canvas)
	x1 := (canvas - pageW) / 2
	y1 := (canvas - pageH) / 2
	x2 := x1 + pageW
	y2 := y1 + pageH

	// Page outline with the top-right corner cut for the fold.
	page := func() {
		out.NewSubPath()
		out.MoveTo(x1+corner, y1)
		out.LineTo(x2-fold, y1)
		out.LineTo(x2, y1+fold)
		out.LineTo(x2, y2-corner)
		out.QuadraticTo(x2, y2, x2-corner, y2)
		out.LineTo(x1+corner, y2)
		out.QuadraticTo(x1, y2, x1, y2-corner)
		out.LineTo(x1, y1+corner)
		out.QuadraticTo(x1, y1, x1+corner, y1)
		out.ClosePath()
	}

	page()
	out.SetHexColor("f2f2f5")
	out.Fill()

	// Orb artwork centered on the page.
	out.Push()
	page()
	out.Clip()
	out.DrawImageAnchored(orb, int((x1+x2)/2), int((y1+y2)/2)+30, 0.5, 0.5)
	out.ResetClip()
	out.Pop()

	// Folded corner.
	out.MoveTo(x2-fold, y1)
	out.LineTo(x2-fold, y1+fold)
	out.LineTo(x2, y1+fold)
	out.ClosePath()
	out.SetHexColor("d4d4da")
	out.Fill()

	// Page border.
	page()
	out.SetHexColor("c2c2c9")
	out.SetLineWidth(6)
	out.Stroke()

	if err := out.SavePNG("build/docicon.png"); err != nil {
		log.Fatal(err)
	}
	log.Println("wrote build/docicon.png")
}
