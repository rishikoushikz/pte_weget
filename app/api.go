package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func SetupAPIRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/settings", handleSettings)
	mux.HandleFunc("/api/autostart", handleAutostart)
	mux.HandleFunc("/api/slots", handleSlots)
	mux.HandleFunc("/api/daemon/", handleDaemon)
	mux.HandleFunc("/api/media/", handleMedia)
	mux.HandleFunc("/api/status", handleStatus)
	mux.HandleFunc("/api/reset", handleReset)
	mux.HandleFunc("/api/wallpaper-palette", handleWallpaperPalette)
	mux.HandleFunc("/api/wallpaper-palette/refresh", handleWallpaperPaletteRefresh)
}

func handleSettings(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method == http.MethodGet {
		s, _ := LoadSettings()
		json.NewEncoder(w).Encode(s)
		return
	}

	if r.Method == http.MethodPost {
		oldSettings, _ := LoadSettings()
		var s Settings
		if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := SaveSettings(s); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		geometryChanged := oldSettings.Position != s.Position ||
			oldSettings.GapX != s.GapX ||
			oldSettings.GapY != s.GapY ||
			oldSettings.Scale != s.Scale ||
			len(oldSettings.RowOrder) != len(s.RowOrder)

		if geometryChanged {
			go func() {
				time.Sleep(100 * time.Millisecond)
				_ = GlobalDaemon.Restart()
				time.Sleep(300 * time.Millisecond)
				GlobalDaemon.updateBlur()
			}()
		} else if oldSettings.BlurRadius != s.BlurRadius || oldSettings.GlassEffect != s.GlassEffect {
			go GlobalDaemon.updateBlur()
		}

		// If location or units changed, trigger background weather refresh
		go GlobalDaemon.fetchWeather()
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		return
	}
	http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
}

func handleAutostart(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method == http.MethodGet {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"enabled": IsAutostartEnabled(),
			"path":    getAutostartFilePath(),
			"exec":    GetAutostartExecPath(),
		})
		return
	}

	if r.Method == http.MethodPost {
		var req struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := SetAutostart(req.Enabled); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		s, err := LoadSettings()
		if err == nil {
			s.Autostart = req.Enabled
			_ = SaveSettings(s)
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "ok",
			"enabled": IsAutostartEnabled(),
		})
		return
	}

	http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
}

func countActiveRows(slots map[string]string, rowOrder []string) int {
	count := 0
	for _, r := range rowOrder {
		m1 := slots[r+"1"]
		m2 := slots[r+"2"]
		if (m1 != "" && m1 != "EMPTY") || (m2 != "" && m2 != "EMPTY") {
			count++
		}
	}
	return count
}

func handleSlots(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	s, _ := LoadSettings()
	if s.Slots == nil {
		s.Slots = make(map[string]string)
	}

	oldRowCount := len(s.RowOrder)
	oldSlots := make(map[string]string)
	for k, v := range s.Slots {
		oldSlots[k] = v
	}

	var reqSingle struct {
		Slot   string `json:"slot"`
		Module string `json:"module"`
	}
	if err := json.Unmarshal(body, &reqSingle); err == nil && reqSingle.Slot != "" {
		s.Slots[reqSingle.Slot] = reqSingle.Module
	}

	var reqMulti struct {
		Slots    map[string]string `json:"slots"`
		RowOrder []string          `json:"row_order"`
	}
	if err := json.Unmarshal(body, &reqMulti); err == nil {
		if reqMulti.Slots != nil {
			s.Slots = reqMulti.Slots
		}
		if reqMulti.RowOrder != nil {
			s.RowOrder = reqMulti.RowOrder
		}
	}

	SaveSettings(s)

	rowStructureChanged := oldRowCount != len(s.RowOrder)
	if !rowStructureChanged {
		if countActiveRows(oldSlots, s.RowOrder) != countActiveRows(s.Slots, s.RowOrder) {
			rowStructureChanged = true
		}
	}

	if rowStructureChanged {
		go func() {
			time.Sleep(100 * time.Millisecond)
			_ = GlobalDaemon.Restart()
			time.Sleep(300 * time.Millisecond)
			GlobalDaemon.updateBlur()
		}()
	} else {
		go GlobalDaemon.updateBlur()
	}

	json.NewEncoder(w).Encode(map[string]interface{}{"status": "ok", "slots": s.Slots, "row_order": s.RowOrder})
}

func handleDaemon(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	action := strings.TrimPrefix(r.URL.Path, "/api/daemon/")

	var err error
	switch action {
	case "start":
		err = GlobalDaemon.Start()
	case "stop":
		err = GlobalDaemon.Stop()
	case "restart":
		err = GlobalDaemon.Restart()
	default:
		http.Error(w, "Unknown action", http.StatusBadRequest)
		return
	}

	if err != nil {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "error",
			"error":  err.Error(),
			"action": action,
		})
		return
	}

	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "action": action})
}

func handleMedia(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	action := strings.TrimPrefix(r.URL.Path, "/api/media/")
	GlobalDaemon.HandleMediaAction(action)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "action": action})
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	running, pid, uptime, engine := GlobalDaemon.Status()

	json.NewEncoder(w).Encode(map[string]interface{}{
		"running": running,
		"pid":     pid,
		"uptime":  uptime,
		"engine":  engine,
	})
}

func handleReset(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	def := DefaultSettings()
	SaveSettings(def)
	json.NewEncoder(w).Encode(def)
}

func ServeStatic(mux *http.ServeMux, fs http.FileSystem) {
	fileServer := http.FileServer(fs)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			return
		}
		f, err := fs.Open(r.URL.Path)
		if err != nil {
			// Fallback to index.html for SPA
			index, err := fs.Open("index.html")
			if err == nil {
				defer index.Close()
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
				io.Copy(w, index)
				return
			}
		} else {
			f.Close()
		}
		fileServer.ServeHTTP(w, r)
	})
}

func handleWallpaperPalette(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	palPath := filepath.Join(os.Getenv("HOME"), ".config/conky/macwidget/settings/wallpaper_palette.json")
	data, err := os.ReadFile(palPath)
	if err != nil {
		helper := findPaletteHelper()
		if helper != "" {
			if out, err := exec.Command("python3", helper).Output(); err == nil && len(out) > 0 {
				w.Write(out)
				return
			}
		}
		http.Error(w, "Palette not found", http.StatusNotFound)
		return
	}
	w.Write(data)
}

func handleWallpaperPaletteRefresh(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	helper := findPaletteHelper()
	if helper == "" {
		http.Error(w, "Palette helper not found", http.StatusInternalServerError)
		return
	}
	out, err := exec.Command("python3", helper).Output()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Write(out)
}
