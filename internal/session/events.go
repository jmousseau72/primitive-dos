package session

// Event names shared between the Go backend and the frontend. The payload
// structs below are the single source of truth for what each event carries;
// frontend/src/types.ts mirrors them.
const (
	EvtStarted     = "session:started"
	EvtBatch       = "session:batch"
	EvtPaused      = "session:paused"
	EvtResumed     = "session:resumed"
	EvtDone        = "session:done"
	EvtError       = "session:error"
	EvtExported    = "export:done"
	EvtFileDropped = "file:dropped"
)

// Preview modes carried on started/batch events.
const (
	PreviewSVG    = "svg"
	PreviewRaster = "raster"
)

type StartedPayload struct {
	SessionID   string  `json:"sessionId"`
	Width       int     `json:"width"`
	Height      int     `json:"height"`
	Scale       float64 `json:"scale"`
	Background  string  `json:"background"`
	TotalShapes int     `json:"totalShapes"`
	PreviewMode string  `json:"previewMode"`
	InputW      int     `json:"inputW"`
	InputH      int     `json:"inputH"`
}

type BatchPayload struct {
	SessionID    string   `json:"sessionId"`
	Fragments    []string `json:"fragments,omitempty"`
	SnapshotJpeg string   `json:"snapshotJpeg,omitempty"`
	PreviewMode  string   `json:"previewMode"`
	ShapesDone   int      `json:"shapesDone"`
	TotalShapes  int      `json:"totalShapes"`
	Score        float64  `json:"score"`
	ElapsedMs    int64    `json:"elapsedMs"`
	ShapesPerSec float64  `json:"shapesPerSec"`
}

type StatePayload struct {
	SessionID  string `json:"sessionId"`
	ShapesDone int    `json:"shapesDone"`
}

type DonePayload struct {
	SessionID  string  `json:"sessionId"`
	Cancelled  bool    `json:"cancelled"`
	ShapesDone int     `json:"shapesDone"`
	Score      float64 `json:"score"`
	ElapsedMs  int64   `json:"elapsedMs"`
}

type ErrorPayload struct {
	SessionID string `json:"sessionId"`
	Message   string `json:"message"`
}

type ExportedPayload struct {
	SessionID string   `json:"sessionId"`
	Paths     []string `json:"paths"`
}

type DroppedPayload struct {
	Path string `json:"path"`
}
