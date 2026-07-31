package primitive

import (
	"math/rand"
	"sync"
)

// This file contains the Primitive Dos additions to the otherwise-unmodified
// upstream engine.

// Quadratic stroke width. Upstream hard-coded 0.5, and its width-mutation
// branch was unreachable (rnd.Intn(3) can never select case 3). These are
// read at shape-creation time; set them only between renders — the GUI and
// CLI both configure them before a run starts.
var (
	// QuadraticWidth is the stroke width new bezier shapes start with.
	QuadraticWidth = 0.5
	// QuadraticWidthMutate lets the optimizer vary each bezier's width.
	QuadraticWidthMutate = false
)

// Focus is an optional region that biases where new shapes are seeded. This
// powers drawing mode: while a focus is active, shapes cluster around the
// brush. Workers read it concurrently while the UI moves it, hence the lock.
var (
	focusMu     sync.RWMutex
	focusX      float64
	focusY      float64
	focusRadius float64
	focusOn     bool
)

// SetFocus activates the focus region. Coordinates are in input-image space.
func SetFocus(x, y, radius float64) {
	focusMu.Lock()
	focusX, focusY, focusRadius, focusOn = x, y, radius, true
	focusMu.Unlock()
}

// ClearFocus deactivates the focus region; seeding is uniform again.
func ClearFocus() {
	focusMu.Lock()
	focusOn = false
	focusMu.Unlock()
}

func FocusActive() bool {
	focusMu.RLock()
	defer focusMu.RUnlock()
	return focusOn
}

// seedPoint returns the initial placement for a new random shape: uniform
// over the canvas normally, gaussian around the focus while one is active.
func seedPoint(rnd *rand.Rand, w, h int) (float64, float64) {
	focusMu.RLock()
	on, fx, fy, fr := focusOn, focusX, focusY, focusRadius
	focusMu.RUnlock()
	if !on {
		return rnd.Float64() * float64(w), rnd.Float64() * float64(h)
	}
	x := clamp(fx+rnd.NormFloat64()*fr, 0, float64(w-1))
	y := clamp(fy+rnd.NormFloat64()*fr, 0, float64(h-1))
	return x, y
}

func seedPointInt(rnd *rand.Rand, w, h int) (int, int) {
	x, y := seedPoint(rnd, w, h)
	return int(x), int(y)
}
