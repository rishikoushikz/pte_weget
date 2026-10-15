package main

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
)

func SetupAPIRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/settings", handleSettings)
	mux.HandleFunc("/api/autostart", handleAutostart)
	mux.HandleFunc("/api/slots", handleSlots)
	mux.HandleFunc("/api/daemon/", handleDaemon)
	mux.HandleFunc("/api/media/", handleMedia)
	mux.HandleFunc("/api/status", handleStatus)
	mux.HandleFunc("/api/reset", handleReset)
}

func handleSettings(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method == http.MethodGet {
		s, _ := LoadSettings()
		json.NewEncoder(w).Encode(s)
		return
	}

	if r.Method == http.MethodPost {
		var s Settings
		if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := SaveSettings(s); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
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

	var reqSingle struct {
		Slot   string `json:"slot"`
		Module string `json:"module"`
	}
	if err := json.Unmarshal(body, &reqSingle); err == nil && reqSingle.Slot != "" {
		s.Slots[reqSingle.Slot] = reqSingle.Module
	}

	var reqMulti struct {
		Slots map[string]string `json:"slots"`
	}
	if err := json.Unmarshal(body, &reqMulti); err == nil && reqMulti.Slots != nil {
		for k, v := range reqMulti.Slots {
			s.Slots[k] = v
		}
	}

	SaveSettings(s)
	json.NewEncoder(w).Encode(map[string]interface{}{"status": "ok", "slots": s.Slots})
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
