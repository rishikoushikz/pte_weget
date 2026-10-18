package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
)

type Settings struct {
	ColorMode         string            `json:"color_mode"`
	GlassEffect       bool              `json:"glass_effect"`
	BlurRadius        int               `json:"blur_radius"`
	BlurOpacity       float64           `json:"blur_opacity"`
	WidgetBorder      bool              `json:"widget_border"`
	Scale             float64           `json:"scale"`
	Position          string            `json:"position"`
	GapX              int               `json:"gap_x"`
	GapY              int               `json:"gap_y"`
	TimeFormat        string            `json:"time_format"`
	MeasurementSystem string            `json:"measurement_system"`
	Location          string            `json:"location"`
	Autostart         bool              `json:"autostart"`
	RowOrder          []string          `json:"row_order,omitempty"`
	Slots             map[string]string `json:"slots"`
}

var settingsLock sync.RWMutex

func getReadSettingsPath() string {
	home := os.Getenv("HOME")
	candidates := []string{
		filepath.Join(home, ".config/conky/macwidget/settings/settings.json"),
		"/usr/share/weget/settings/settings.json",
		filepath.Join(home, ".local/share/weget/settings/settings.json"),
		"engine/settings/settings.json",
		"settings/settings.json",
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return filepath.Join(home, ".config/conky/macwidget/settings/settings.json")
}

func getSettingsPath() string {
	return filepath.Join(os.Getenv("HOME"), ".config/conky/macwidget/settings/settings.json")
}

func DefaultSettings() Settings {
	return Settings{
		ColorMode:         "dark",
		GlassEffect:       true,
		BlurRadius:        30,
		BlurOpacity:       0.60,
		WidgetBorder:      true,
		Scale:             1.0,
		Position:          "top_right",
		GapX:              26,
		GapY:              54,
		TimeFormat:        "24h",
		MeasurementSystem: "metric",
		Location:          "Mumbai",
		Autostart:         IsAutostartEnabled(),
		RowOrder:          []string{"A", "B", "C", "D"},
		Slots: map[string]string{
			"A1": "CALN_2x1_WID",
			"B1": "WEAT_1x1_MIN",
			"B2": "RING_1x1_MIN",
			"C1": "NETW_2x1_WID",
			"D1": "MEDI_2x1_WID",
		},
	}
}

func LoadSettings() (Settings, error) {
	settingsLock.RLock()
	defer settingsLock.RUnlock()

	s := DefaultSettings()
	path := getReadSettingsPath()
	data, err := os.ReadFile(path)
	if err != nil {
		s.Autostart = IsAutostartEnabled()
		return s, err
	}

	if err := json.Unmarshal(data, &s); err != nil {
		s = DefaultSettings()
		s.Autostart = IsAutostartEnabled()
		return s, err
	}

	// Graceful migration: if legacy color_mode was "glass", migrate to dark + glass_effect = true
	if s.ColorMode == "glass" {
		s.ColorMode = "dark"
		s.GlassEffect = true
	}

	if s.BlurRadius <= 0 {
		s.BlurRadius = 30
	}
	if s.BlurOpacity <= 0 {
		s.BlurOpacity = 0.60
	}

	if s.Position == "" {
		s.Position = "top_right"
	}
	if s.Scale <= 0 {
		s.Scale = 1.0
	}

	s.Autostart = IsAutostartEnabled()

	if s.Slots == nil {
		s.Slots = DefaultSettings().Slots
	}
	if len(s.RowOrder) == 0 {
		s.RowOrder = []string{"A", "B", "C", "D"}
	}
	return s, nil
}

func SaveSettings(s Settings) error {
	settingsLock.Lock()
	defer settingsLock.Unlock()

	// Sync autostart XDG desktop entry
	if s.Autostart != IsAutostartEnabled() {
		_ = SetAutostart(s.Autostart)
	}

	path := getSettingsPath()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}

	tmpFile := path + ".tmp"
	if err := os.WriteFile(tmpFile, data, 0644); err != nil {
		return err
	}

	err = os.Rename(tmpFile, path)
	if err == nil && s.GlassEffect {
		go func() {
			helper := findBlurHelper()
			if helper != "" {
				_ = exec.Command("python3", helper).Run()
			}
		}()
	}
	return err
}
