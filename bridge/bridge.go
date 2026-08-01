// Package main builds the Primitive Dos engine as a C static archive for the
// native macOS app:
//
//	go build -buildmode=c-archive -o macos/Vendor/libprimitive.a ./bridge
//
// Conventions, mirrored by macos/PrimitiveDos/Bridge/EngineClient.swift:
//   - Every returned char* is malloc'd; the caller frees it with PrimitiveFree.
//   - Input char* are copied before return; the caller keeps ownership.
//   - Results use a uniform envelope: {"ok":true,"value":...} or
//     {"ok":false,"error":"message"}.
//   - Events are pulled: PrimitiveNextEvent blocks until the next event JSON
//     ({"event":...,"payload":...}) and returns NULL after PrimitiveShutdown.
//     Exactly one consumer thread should pump it.
//
// One render session is active at a time, matching the GUI contract in
// app.go.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"unsafe"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
	"github.com/jmousseau72/primitive-dos/internal/session"
)

var (
	mu       sync.Mutex
	sessions = map[string]*session.RenderSession{}
	active   *session.RenderSession
	nextID   int

	rootCtx, rootCancel = context.WithCancel(context.Background())
	// Buffered enough that the render loop never stalls at the batch cadence
	// (~7 events/sec); if the consumer wedges, emit blocks and the render
	// throttles rather than growing memory. Never closed — NextEvent selects
	// on rootCtx so shutdown can't race a send.
	events = make(chan string, 256)
)

func emit(event string, payload any) {
	b, err := json.Marshal(struct {
		Event   string `json:"event"`
		Payload any    `json:"payload"`
	}{event, payload})
	if err != nil {
		return
	}
	select {
	case events <- string(b):
	case <-rootCtx.Done():
	}
}

func ok(v any) *C.char {
	b, err := json.Marshal(map[string]any{"ok": true, "value": v})
	if err != nil {
		return fail(err)
	}
	return C.CString(string(b))
}

func fail(err error) *C.char {
	b, _ := json.Marshal(map[string]any{"ok": false, "error": err.Error()})
	return C.CString(string(b))
}

//export PrimitiveInspect
func PrimitiveInspect(path *C.char, thumbMaxDim C.int) *C.char {
	info, err := session.InspectInput(C.GoString(path), int(thumbMaxDim))
	if err != nil {
		return fail(err)
	}
	return ok(info)
}

//export PrimitiveStartRender
func PrimitiveStartRender(paramsJSON *C.char) *C.char {
	var p session.Params
	if err := json.Unmarshal([]byte(C.GoString(paramsJSON)), &p); err != nil {
		return fail(fmt.Errorf("bad params: %w", err))
	}
	p.EmitShapeData = true

	mu.Lock()
	defer mu.Unlock()
	if active != nil && !active.Done() {
		return fail(fmt.Errorf("a render is already running"))
	}
	nextID++
	id := fmt.Sprintf("s%d", nextID)
	s, err := session.New(rootCtx, id, p, emit)
	if err != nil {
		return fail(err)
	}
	sessions = map[string]*session.RenderSession{id: s}
	active = s
	s.Start()
	return ok(id)
}

func withSession(id *C.char, fn func(*session.RenderSession) *C.char) *C.char {
	mu.Lock()
	s, found := sessions[C.GoString(id)]
	mu.Unlock()
	if !found {
		return fail(fmt.Errorf("unknown session %q", C.GoString(id)))
	}
	return fn(s)
}

//export PrimitivePauseRender
func PrimitivePauseRender(id *C.char) *C.char {
	return withSession(id, func(s *session.RenderSession) *C.char {
		s.Pause()
		return ok(nil)
	})
}

//export PrimitiveResumeRender
func PrimitiveResumeRender(id *C.char) *C.char {
	return withSession(id, func(s *session.RenderSession) *C.char {
		s.Resume()
		return ok(nil)
	})
}

//export PrimitiveCancelRender
func PrimitiveCancelRender(id *C.char) *C.char {
	return withSession(id, func(s *session.RenderSession) *C.char {
		s.Cancel()
		return ok(nil)
	})
}

//export PrimitiveExportRender
func PrimitiveExportRender(id *C.char, optsJSON *C.char) *C.char {
	var opts session.ExportOptions
	if err := json.Unmarshal([]byte(C.GoString(optsJSON)), &opts); err != nil {
		return fail(fmt.Errorf("bad export options: %w", err))
	}
	return withSession(id, func(s *session.RenderSession) *C.char {
		paths, err := s.Export(opts)
		if err != nil {
			return fail(err)
		}
		return ok(paths)
	})
}

//export PrimitiveDefaultExportName
func PrimitiveDefaultExportName(id *C.char) *C.char {
	return withSession(id, func(s *session.RenderSession) *C.char {
		return ok(s.DefaultBaseName())
	})
}

//export PrimitiveListPresets
func PrimitiveListPresets() *C.char {
	presets, err := session.ListPresets()
	if err != nil {
		return fail(err)
	}
	return ok(presets)
}

//export PrimitiveSavePreset
func PrimitiveSavePreset(presetJSON *C.char) *C.char {
	var p session.Preset
	if err := json.Unmarshal([]byte(C.GoString(presetJSON)), &p); err != nil {
		return fail(fmt.Errorf("bad preset: %w", err))
	}
	if err := session.SaveUserPreset(p); err != nil {
		return fail(err)
	}
	return ok(nil)
}

//export PrimitiveDeletePreset
func PrimitiveDeletePreset(name *C.char) *C.char {
	if err := session.DeleteUserPreset(C.GoString(name)); err != nil {
		return fail(err)
	}
	return ok(nil)
}

//export PrimitiveContinueRender
func PrimitiveContinueRender(id *C.char, paramsJSON *C.char) *C.char {
	var p session.Params
	if err := json.Unmarshal([]byte(C.GoString(paramsJSON)), &p); err != nil {
		return fail(fmt.Errorf("bad params: %w", err))
	}
	return withSession(id, func(s *session.RenderSession) *C.char {
		if err := s.Continue(rootCtx, p); err != nil {
			return fail(err)
		}
		mu.Lock()
		active = s
		mu.Unlock()
		return ok(nil)
	})
}

//export PrimitiveSaveDocument
func PrimitiveSaveDocument(id *C.char, path *C.char) *C.char {
	p := C.GoString(path)
	return withSession(id, func(s *session.RenderSession) *C.char {
		if err := s.SaveDocument(p); err != nil {
			return fail(err)
		}
		return ok(nil)
	})
}

type loadedDocResponse struct {
	SessionID  string                 `json:"sessionId"`
	Params     session.Params         `json:"params"`
	Input      session.InputInfo      `json:"input"`
	Started    session.StartedPayload `json:"started"`
	Shapes     []session.ShapeRecord  `json:"shapes"`
	ShapesDone int                    `json:"shapesDone"`
	Score      float64                `json:"score"`
	ElapsedMs  int64                  `json:"elapsedMs"`
}

//export PrimitiveLoadDocument
func PrimitiveLoadDocument(path *C.char) *C.char {
	mu.Lock()
	if active != nil && !active.Done() {
		mu.Unlock()
		return fail(fmt.Errorf("stop the current render before opening a document"))
	}
	nextID++
	id := fmt.Sprintf("s%d", nextID)
	mu.Unlock()

	loaded, err := session.OpenDocument(C.GoString(path), id, emit)
	if err != nil {
		return fail(err)
	}

	info, err := session.InspectInput(loaded.InputPath, 1600)
	if err != nil {
		return fail(err)
	}

	mu.Lock()
	sessions = map[string]*session.RenderSession{id: loaded.Session}
	active = loaded.Session
	mu.Unlock()

	return ok(loadedDocResponse{
		SessionID:  id,
		Params:     loaded.Session.Params(),
		Input:      info,
		Started:    loaded.Started,
		Shapes:     loaded.Shapes,
		ShapesDone: loaded.StepsDone,
		Score:      loaded.Score,
		ElapsedMs:  loaded.ElapsedMs,
	})
}

//export PrimitiveSetDrawFocus
func PrimitiveSetDrawFocus(x, y, radius C.double, activeFlag C.int) {
	if activeFlag != 0 {
		primitive.SetFocus(float64(x), float64(y), float64(radius))
	} else {
		primitive.ClearFocus()
	}
}

//export PrimitiveNextEvent
func PrimitiveNextEvent() *C.char {
	select {
	case s := <-events:
		return C.CString(s)
	case <-rootCtx.Done():
		return nil
	}
}

//export PrimitiveShutdown
func PrimitiveShutdown() {
	mu.Lock()
	if active != nil {
		active.Cancel()
	}
	mu.Unlock()
	rootCancel()
}

//export PrimitiveFree
func PrimitiveFree(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
