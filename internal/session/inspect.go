package session

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image/jpeg"

	"github.com/nfnt/resize"
)

type InputInfo struct {
	Path         string `json:"path"`
	Width        int    `json:"width"`
	Height       int    `json:"height"`
	ThumbJpegB64 string `json:"thumbJpegB64"`
}

// InspectInput loads an image and returns its dimensions plus a JPEG
// thumbnail, shared by every frontend. Dimensions come from the same decoder
// the engine uses, so they can never disagree with a render's coordinates
// (e.g. via EXIF rotation that other image APIs might apply).
func InspectInput(path string, thumbMaxDim int) (InputInfo, error) {
	img, err := LoadInput(path, 0)
	if err != nil {
		return InputInfo{}, fmt.Errorf("could not read image: %w", err)
	}
	if thumbMaxDim < 16 {
		thumbMaxDim = 320
	}
	info := InputInfo{Path: path, Width: img.Bounds().Dx(), Height: img.Bounds().Dy()}
	thumb := resize.Thumbnail(uint(thumbMaxDim), uint(thumbMaxDim), img, resize.Bilinear)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, thumb, &jpeg.Options{Quality: 80}); err == nil {
		info.ThumbJpegB64 = base64.StdEncoding.EncodeToString(buf.Bytes())
	}
	return info, nil
}
