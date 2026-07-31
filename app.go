package main

import (
	"context"
	"fmt"
	"os/exec"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"github.com/jmousseau72/primitive-dos/internal/primitive"
	"github.com/jmousseau72/primitive-dos/internal/session"
)

// App exposes the bound methods the frontend calls. It owns at most one
// active render session at a time; the session map keeps finished sessions
// addressable for export until a new render replaces them.
type App struct {
	ctx      context.Context
	mu       sync.Mutex
	sessions map[string]*session.RenderSession
	nextID   int
	active   *session.RenderSession
}

func NewApp() *App {
	return &App{sessions: make(map[string]*session.RenderSession)}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	runtime.OnFileDrop(ctx, func(x, y int, paths []string) {
		if len(paths) > 0 {
			runtime.EventsEmit(ctx, session.EvtFileDropped, session.DroppedPayload{Path: paths[0]})
		}
	})
}

func (a *App) emit(event string, payload any) {
	runtime.EventsEmit(a.ctx, event, payload)
}

// SelectInputFile shows the native open dialog filtered to image types.
func (a *App) SelectInputFile() (string, error) {
	return runtime.OpenFileDialog(a.ctx, runtime.OpenDialogOptions{
		Title: "Choose an Image",
		Filters: []runtime.FileFilter{
			{DisplayName: "Images", Pattern: "*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.tif;*.tiff;*.webp"},
		},
	})
}

// SelectOutputDir shows the native directory picker for exports/checkpoints.
func (a *App) SelectOutputDir(defaultDir string) (string, error) {
	return runtime.OpenDirectoryDialog(a.ctx, runtime.OpenDialogOptions{
		Title:            "Choose Output Folder",
		DefaultDirectory: defaultDir,
	})
}

// InspectInput loads an image and returns its dimensions plus a small
// thumbnail for the source preview corner.
func (a *App) InspectInput(path string) (session.InputInfo, error) {
	return session.InspectInput(path, 320)
}

// StartRender validates params, spins up a new session, and returns its id.
// Only one render runs at a time.
func (a *App) StartRender(p session.Params) (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.active != nil && !a.active.Done() {
		return "", fmt.Errorf("a render is already running")
	}
	a.nextID++
	id := fmt.Sprintf("s%d", a.nextID)
	s, err := session.New(a.ctx, id, p, a.emit)
	if err != nil {
		return "", err
	}
	// Drop finished sessions; keep only the new one addressable.
	a.sessions = map[string]*session.RenderSession{id: s}
	a.active = s
	s.Start()
	return id, nil
}

func (a *App) session(id string) (*session.RenderSession, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	s, ok := a.sessions[id]
	if !ok {
		return nil, fmt.Errorf("unknown session %q", id)
	}
	return s, nil
}

func (a *App) PauseRender(id string) error {
	s, err := a.session(id)
	if err != nil {
		return err
	}
	s.Pause()
	return nil
}

func (a *App) ResumeRender(id string) error {
	s, err := a.session(id)
	if err != nil {
		return err
	}
	s.Resume()
	return nil
}

func (a *App) CancelRender(id string) error {
	s, err := a.session(id)
	if err != nil {
		return err
	}
	s.Cancel()
	return nil
}

// ExportRender writes the session's current state in the requested formats.
// Works mid-run, while paused, after cancel, and after completion.
func (a *App) ExportRender(id string, opts session.ExportOptions) ([]string, error) {
	s, err := a.session(id)
	if err != nil {
		return nil, err
	}
	return s.Export(opts)
}

// DefaultExportName returns the suggested base filename for the session.
func (a *App) DefaultExportName(id string) (string, error) {
	s, err := a.session(id)
	if err != nil {
		return "", err
	}
	return s.DefaultBaseName(), nil
}

func (a *App) ListPresets() ([]session.Preset, error) {
	return session.ListPresets()
}

func (a *App) SavePreset(p session.Preset) error {
	return session.SaveUserPreset(p)
}

func (a *App) DeletePreset(name string) error {
	return session.DeleteUserPreset(name)
}

// RevealInFinder shows an exported file in Finder.
func (a *App) RevealInFinder(path string) error {
	return exec.Command("open", "-R", path).Run()
}

// SetDrawFocus moves (or lifts) the drawing-mode brush. Coordinates are in
// input-image space; the frontend maps pointer positions before calling.
func (a *App) SetDrawFocus(x, y, radius float64, active bool) {
	if active {
		primitive.SetFocus(x, y, radius)
	} else {
		primitive.ClearFocus()
	}
}
