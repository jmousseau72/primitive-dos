package session

import (
	"fmt"
	"image"

	"github.com/nfnt/resize"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
)

// LoadInput reads an image and optionally downscales it, mirroring the CLI's
// -r flag: resizeTo <= 0 keeps the original resolution.
func LoadInput(path string, resizeTo int) (image.Image, error) {
	img, err := primitive.LoadImage(path)
	if err != nil {
		return nil, err
	}
	if resizeTo > 0 {
		img = resize.Thumbnail(uint(resizeTo), uint(resizeTo), img, resize.Bilinear)
	}
	return img, nil
}

// ResolveBackground mirrors the CLI's -bg flag: empty means the average color
// of the input image, otherwise a hex color like "#1a2b3c".
func ResolveBackground(img image.Image, hex string) primitive.Color {
	if hex == "" {
		return primitive.MakeColor(primitive.AverageImageColor(img))
	}
	return primitive.MakeHexColor(hex)
}

func hexString(c primitive.Color) string {
	return fmt.Sprintf("#%02x%02x%02x", c.R, c.G, c.B)
}
