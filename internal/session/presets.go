package session

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Preset struct {
	Name          string   `json:"name"`
	BuiltIn       bool     `json:"builtIn"`
	Params        Params   `json:"params"`
	ExportFormats []string `json:"exportFormats"`
}

// BuiltInPresets mirrors the workflow this app grew out of: quadratic beziers
// at full opacity, processed at full input resolution. "Fast" renders to a
// 1024px canvas; "HQ Final" matches the input's dimensions (OutputSize 0).
func BuiltInPresets() []Preset {
	quad := func(name string, count, outputSize int) Preset {
		return Preset{
			Name:    name,
			BuiltIn: true,
			Params: Params{
				Mode:        6,
				ShapeCount:  count,
				Alpha:       255,
				OutputSize:  outputSize,
				StrokeWidth: 0.5,
				RunMode:     RunCount,
			},
			ExportFormats: []string{"png", "jpg", "svg"},
		}
	}
	// The classic abstract-art looks from the original project use a
	// 256px working input and half alpha — that combination, not shape
	// count alone, is what produces the iconic result.
	classic := func(name string, mode, count int) Preset {
		return Preset{
			Name:    name,
			BuiltIn: true,
			Params: Params{
				Mode:        mode,
				ShapeCount:  count,
				Alpha:       128,
				InputResize: 256,
				OutputSize:  1024,
				StrokeWidth: 0.5,
				RunMode:     RunCount,
			},
			ExportFormats: []string{"png", "jpg", "svg"},
		}
	}
	return []Preset{
		quad("Fast Quad 20k", 20000, 1024),
		quad("Fast Quad 50k", 50000, 1024),
		quad("Fast Quad 100k", 100000, 1024),
		quad("HQ Final 2k", 2000, 0),
		quad("HQ Final 5k", 5000, 0),
		quad("HQ Final 10k", 10000, 0),
		quad("HQ Final 50k", 50000, 0),
		quad("HQ Final 120k", 120000, 0),
		classic("Classic Triangles 200", 1, 200),
		classic("Triangles Fine 1k", 1, 1000),
		classic("Mosaic Rectangles 300", 2, 300),
		classic("Rotated Rects 350", 5, 350),
		classic("Stained Glass 500", 8, 500),
		classic("Ellipse Wash 250", 3, 250),
		classic("Circles 400", 4, 400),
		classic("Combo 600", 0, 600),
	}
}

func presetsPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "PrimitiveDos", "presets.json"), nil
}

func LoadUserPresets() ([]Preset, error) {
	path, err := presetsPath()
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var presets []Preset
	if err := json.Unmarshal(data, &presets); err != nil {
		return nil, fmt.Errorf("presets file is corrupt: %w", err)
	}
	for i := range presets {
		presets[i].BuiltIn = false
	}
	return presets, nil
}

// ListPresets returns built-ins followed by user presets.
func ListPresets() ([]Preset, error) {
	user, err := LoadUserPresets()
	if err != nil {
		return nil, err
	}
	return append(BuiltInPresets(), user...), nil
}

func saveUserPresets(presets []Preset) error {
	path, err := presetsPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(presets, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

// SaveUserPreset upserts by name. Built-in names are reserved.
func SaveUserPreset(p Preset) error {
	if p.Name == "" {
		return fmt.Errorf("preset needs a name")
	}
	for _, b := range BuiltInPresets() {
		if b.Name == p.Name {
			return fmt.Errorf("%q is a built-in preset; pick another name", p.Name)
		}
	}
	p.BuiltIn = false
	presets, err := LoadUserPresets()
	if err != nil {
		return err
	}
	replaced := false
	for i := range presets {
		if presets[i].Name == p.Name {
			presets[i] = p
			replaced = true
			break
		}
	}
	if !replaced {
		presets = append(presets, p)
	}
	return saveUserPresets(presets)
}

func DeleteUserPreset(name string) error {
	presets, err := LoadUserPresets()
	if err != nil {
		return err
	}
	out := presets[:0]
	for _, p := range presets {
		if p.Name != name {
			out = append(out, p)
		}
	}
	if len(out) == len(presets) {
		return fmt.Errorf("no user preset named %q", name)
	}
	return saveUserPresets(out)
}
