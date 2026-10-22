package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

type WeatherTelemetry struct {
	City  string `json:"city"`
	Temp  string `json:"temp"`
	Desc  string `json:"desc"`
	Feels string `json:"feels"`
	Hum   string `json:"hum"`
	Icon  string `json:"icon"`
}

type MediaTelemetry struct {
	Status       string  `json:"status"`
	IsPlaying    bool    `json:"is_playing"`
	Title        string  `json:"title"`
	Artist       string  `json:"artist"`
	Progress     float64 `json:"progress"`
	Time         string  `json:"time"`
	Player       string  `json:"player,omitempty"`
	PlayerName   string  `json:"player_name,omitempty"`
	PlayerIcon   string  `json:"player_icon,omitempty"`
	PlayerIndex  int     `json:"player_index,omitempty"`
	TotalPlayers int     `json:"total_players,omitempty"`
}

type NetworkTelemetry struct {
	SSID string `json:"ssid"`
}

type QuoteTelemetry struct {
	Text   string `json:"text"`
	Author string `json:"author"`
	Tag    string `json:"tag"`
}

type SystemTelemetry struct {
	CPUPercent  int    `json:"cpu_percent"`
	RAMPercent  int    `json:"ram_percent"`
	DiskPercent int    `json:"disk_percent"`
	DiskUsed    string `json:"disk_used"`
	DiskTotal   string `json:"disk_total"`
}

type TelemetryPayload struct {
	Weather WeatherTelemetry `json:"weather"`
	Media   MediaTelemetry   `json:"media"`
	Network NetworkTelemetry `json:"network"`
	Quote   QuoteTelemetry   `json:"quote"`
	System  SystemTelemetry  `json:"system"`
	Updated int64            `json:"updated"`
}

type DaemonManager struct {
	mu           sync.RWMutex
	telemetry    TelemetryPayload
	conkyCmd     *exec.Cmd
	stopChan     chan struct{}
	running      bool
	conkyBinPath string
	conkyLibPath string
	configPath   string
}

var GlobalDaemon = &DaemonManager{
	telemetry: TelemetryPayload{
		Weather: WeatherTelemetry{
			City:  "Mumbai",
			Temp:  "29°C",
			Desc:  "Fair",
			Feels: "33°C",
			Hum:   "65%",
			Icon:  "󰖙",
		},
		Media: MediaTelemetry{
			Status:    "󰓛 Idle",
			IsPlaying: false,
			Title:     "No Media Playing",
			Artist:    "Weget Audio Engine",
			Progress:  0.0,
			Time:      "--:--",
		},
		Network: NetworkTelemetry{
			SSID: "WiFi",
		},
		Quote: QuoteTelemetry{
			Text:   "Simplicity is the soul of efficiency.",
			Author: "Austin Freeman",
			Tag:    "Engineering",
		},
		System: SystemTelemetry{
			CPUPercent:  12,
			RAMPercent:  48,
			DiskPercent: 54,
			DiskUsed:    "128G",
			DiskTotal:   "500G",
		},
	},
}

var dailyQuotes = []QuoteTelemetry{
	{Text: "Peace begins when you accept things as they are.", Author: "Austin Freeman", Tag: "Daily Wisdom"},
	{Text: "Stability quietly fuels sustainable growth.", Author: "Marcus Aurelius", Tag: "Mindset"},
	{Text: "Steady work wins over sudden bursts.", Author: "Seneca", Tag: "Consistency"},
	{Text: "Daily effort defines long term success.", Author: "James Clear", Tag: "Habits"},
	{Text: "A calm mind sees opportunities where a restless mind sees problems.", Author: "Epictetus", Tag: "Focus"},
	{Text: "Every sunrise offers another chance to begin again with clarity.", Author: "Lao Tzu", Tag: "Renewal"},
	{Text: "Simplicity is the soul of efficiency.", Author: "Austin Freeman", Tag: "Engineering"},
}

func getTelemetryPaths() []string {
	paths := []string{
		"/tmp/weget_telemetry.json",
	}
	if home := os.Getenv("HOME"); home != "" {
		p := filepath.Join(home, ".cache/weget/telemetry.json")
		_ = os.MkdirAll(filepath.Dir(p), 0755)
		paths = append(paths, p)
	}
	return paths
}

func (dm *DaemonManager) SaveTelemetry() {
	dm.mu.RLock()
	dm.telemetry.Updated = time.Now().Unix()
	data, err := json.MarshalIndent(dm.telemetry, "", "  ")
	dm.mu.RUnlock()

	if err != nil {
		return
	}

	for _, path := range getTelemetryPaths() {
		tmp := path + ".tmp"
		if err := os.WriteFile(tmp, data, 0644); err == nil {
			_ = os.Rename(tmp, path)
		}
	}
}

func (dm *DaemonManager) StartTelemetryLoop() {
	dm.mu.Lock()
	if dm.stopChan != nil {
		dm.mu.Unlock()
		return
	}
	dm.stopChan = make(chan struct{})
	dm.mu.Unlock()

	// Initial synchronous save so Conky has immediate cached data
	dm.updateQuote()
	dm.updateNetwork()
	dm.updateSystem()
	dm.SaveTelemetry()

	// Launch background pollers
	go dm.pollWeatherLoop()
	go dm.pollMediaLoop()
	go dm.pollNetworkLoop()
	go dm.pollSystemLoop()
	go dm.pollBlurLoop()
}

func (dm *DaemonManager) stopTelemetryLoopLocked() {
	if dm.stopChan != nil {
		close(dm.stopChan)
		dm.stopChan = nil
	}
}

func (dm *DaemonManager) StopTelemetryLoop() {
	dm.mu.Lock()
	defer dm.mu.Unlock()
	dm.stopTelemetryLoopLocked()
}

func (dm *DaemonManager) pollWeatherLoop() {
	// First fetch immediately in background
	dm.fetchWeather()

	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			dm.fetchWeather()
		case <-dm.stopChan:
			return
		}
	}
}

func (dm *DaemonManager) fetchWeather() {
	settings, _ := LoadSettings()
	loc := settings.Location
	if loc == "" {
		loc = "Mumbai"
	}
	units := settings.MeasurementSystem
	if units == "" {
		units = "metric"
	}

	url := fmt.Sprintf("https://wttr.in/%s?format=j1", loc)
	client := http.Client{Timeout: 4 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return
	}

	var data struct {
		CurrentCondition []struct {
			TempC       string `json:"temp_C"`
			TempF       string `json:"temp_F"`
			FeelsLikeC  string `json:"FeelsLikeC"`
			FeelsLikeF  string `json:"FeelsLikeF"`
			Humidity    string `json:"humidity"`
			WeatherDesc []struct {
				Value string `json:"value"`
			} `json:"weatherDesc"`
		} `json:"current_condition"`
		NearestArea []struct {
			AreaName []struct {
				Value string `json:"value"`
			} `json:"areaName"`
		} `json:"nearest_area"`
	}

	if err := json.Unmarshal(body, &data); err != nil || len(data.CurrentCondition) == 0 {
		return
	}

	c := data.CurrentCondition[0]
	city := loc
	if len(data.NearestArea) > 0 && len(data.NearestArea[0].AreaName) > 0 {
		city = data.NearestArea[0].AreaName[0].Value
	}

	temp := c.TempC + "°C"
	feels := c.FeelsLikeC + "°C"
	if units == "imperial" {
		temp = c.TempF + "°F"
		feels = c.FeelsLikeF + "°F"
	}

	desc := "Fair"
	if len(c.WeatherDesc) > 0 && c.WeatherDesc[0].Value != "" {
		desc = c.WeatherDesc[0].Value
	}

	icon := "󰖙"
	dLow := strings.ToLower(desc)
	switch {
	case strings.Contains(dLow, "sun") || strings.Contains(dLow, "clear"):
		icon = "󰖙"
	case strings.Contains(dLow, "partly"):
		icon = "󰖕"
	case strings.Contains(dLow, "cloud") || strings.Contains(dLow, "overcast"):
		icon = "󰖐"
	case strings.Contains(dLow, "rain") || strings.Contains(dLow, "drizzle") || strings.Contains(dLow, "shower"):
		icon = "󰖖"
	case strings.Contains(dLow, "thunder"):
		icon = "󰙾"
	case strings.Contains(dLow, "snow"):
		icon = "󰖘"
	case strings.Contains(dLow, "fog") || strings.Contains(dLow, "mist") || strings.Contains(dLow, "haze"):
		icon = "󰖑"
	}

	dm.mu.Lock()
	dm.telemetry.Weather = WeatherTelemetry{
		City:  city,
		Temp:  temp,
		Desc:  desc,
		Feels: feels,
		Hum:   c.Humidity + "%",
		Icon:  icon,
	}
	dm.mu.Unlock()
	dm.SaveTelemetry()
}

func (dm *DaemonManager) pollMediaLoop() {
	ticker := time.NewTicker(1200 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			dm.updateMedia()
		case <-dm.stopChan:
			return
		}
	}
}

func findMediaHelper() string {
	home := os.Getenv("HOME")
	candidates := []string{
		filepath.Join(home, ".config/conky/macwidget/helpers/media.py"),
		filepath.Join(home, ".local/share/weget/helpers/media.py"),
		"/usr/share/weget/helpers/media.py",
		"/app/share/weget/helpers/media.py",
		"engine/helpers/media.py",
		"helpers/media.py",
	}
	for _, c := range candidates {
		if fi, err := os.Stat(c); err == nil && !fi.IsDir() {
			return c
		}
	}
	return ""
}

func (dm *DaemonManager) updateMedia() {
	ctx, cancel := context.WithTimeout(context.Background(), 2500*time.Millisecond)
	defer cancel()

	helper := findMediaHelper()
	var jsonBytes []byte
	var err error

	if helper != "" {
		jsonBytes, err = exec.CommandContext(ctx, "python3", helper, "json").Output()
	} else if _, pErr := exec.LookPath("playerctl"); pErr == nil {
		statusBytes, sErr := exec.CommandContext(ctx, "playerctl", "status").Output()
		if sErr == nil {
			status := strings.TrimSpace(string(statusBytes))
			isPlaying := (status == "Playing")
			statusIcon := "󰓛 Idle"
			if isPlaying {
				statusIcon = "󰐊 Playing"
			} else if status == "Paused" {
				statusIcon = "󰏤 Paused"
			}
			titleBytes, _ := exec.CommandContext(ctx, "playerctl", "metadata", "title").Output()
			title := strings.TrimSpace(string(titleBytes))
			if title == "" { title = "Unknown Track" }
			if len(title) > 28 { title = title[:28] }
			artistBytes, _ := exec.CommandContext(ctx, "playerctl", "metadata", "artist").Output()
			artist := strings.TrimSpace(string(artistBytes))
			if artist == "" { artist = "Weget Audio Engine" }
			if len(artist) > 25 { artist = artist[:25] }
			posBytes, _ := exec.CommandContext(ctx, "playerctl", "position").Output()
			posSec, _ := strconv.ParseFloat(strings.TrimSpace(string(posBytes)), 64)
			lenBytes, _ := exec.CommandContext(ctx, "playerctl", "metadata", "mpris:length").Output()
			lenUSec, _ := strconv.ParseFloat(strings.TrimSpace(string(lenBytes)), 64)
			lenSec := lenUSec / 1000000.0
			progress := 0.0
			timeStr := "--:--"
			if lenSec > 0 {
				progress = posSec / lenSec
				if progress > 1.0 { progress = 1.0 }
				timeStr = fmt.Sprintf("%02d:%02d / %02d:%02d", int(posSec)/60, int(posSec)%60, int(lenSec)/60, int(lenSec)%60)
			}
			dm.mu.Lock()
			dm.telemetry.Media = MediaTelemetry{
				Status:    statusIcon,
				IsPlaying: isPlaying,
				Title:     title,
				Artist:    artist,
				Progress:  progress,
				Time:      timeStr,
			}
			dm.mu.Unlock()
			dm.SaveTelemetry()
			return
		}
		err = sErr
	} else {
		err = fmt.Errorf("no media helper or playerctl found")
	}

	if err == nil && len(jsonBytes) > 0 {
		var m MediaTelemetry
		if unmarshalErr := json.Unmarshal(jsonBytes, &m); unmarshalErr == nil {
			dm.mu.Lock()
			dm.telemetry.Media = m
			dm.mu.Unlock()
			dm.SaveTelemetry()
			return
		}
	}

	dm.mu.Lock()
	dm.telemetry.Media = MediaTelemetry{
		Status:    "󰓛 Idle",
		IsPlaying: false,
		Title:     "No Media Playing",
		Artist:    "Weget Audio Engine",
		Progress:  0.0,
		Time:      "--:--",
	}
	dm.mu.Unlock()
	dm.SaveTelemetry()
}

func (dm *DaemonManager) pollNetworkLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			dm.updateNetwork()
		case <-dm.stopChan:
			return
		}
	}
}

func (dm *DaemonManager) updateNetwork() {
	ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
	defer cancel()

	cmd := exec.CommandContext(ctx, "nmcli", "-t", "-f", "active,ssid", "dev", "wifi")
	out, err := cmd.Output()
	ssid := ""
	if err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			parts := strings.Split(line, ":")
			if len(parts) >= 2 && parts[0] == "yes" && parts[1] != "" {
				ssid = parts[1]
				break
			}
		}
	}
	if ssid == "" {
		ssid = "Connected"
	}

	dm.mu.Lock()
	dm.telemetry.Network.SSID = ssid
	dm.mu.Unlock()
	dm.SaveTelemetry()
}

func (dm *DaemonManager) updateQuote() {
	day := time.Now().YearDay()
	q := dailyQuotes[day%len(dailyQuotes)]
	dm.mu.Lock()
	dm.telemetry.Quote = q
	dm.mu.Unlock()
}

func (dm *DaemonManager) pollSystemLoop() {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			dm.updateSystem()
		case <-dm.stopChan:
			return
		}
	}
}

var (
	lastCPUTotal uint64
	lastCPUIdle  uint64
)

func (dm *DaemonManager) updateSystem() {
	sys := SystemTelemetry{
		CPUPercent:  10,
		RAMPercent:  40,
		DiskPercent: 50,
		DiskUsed:    "0G",
		DiskTotal:   "0G",
	}

	// 1. Disk usage via statfs
	var stat syscall.Statfs_t
	if err := syscall.Statfs("/", &stat); err == nil {
		totalBytes := stat.Blocks * uint64(stat.Bsize)
		freeBytes := stat.Bavail * uint64(stat.Bsize)
		if totalBytes > 0 {
			usedBytes := totalBytes - freeBytes
			sys.DiskPercent = int((usedBytes * 100) / totalBytes)
			totalGB := float64(totalBytes) / (1024 * 1024 * 1024)
			usedGB := float64(usedBytes) / (1024 * 1024 * 1024)
			sys.DiskUsed = fmt.Sprintf("%.1fG", usedGB)
			sys.DiskTotal = fmt.Sprintf("%.1fG", totalGB)
		}
	}

	// 2. RAM usage via /proc/meminfo
	if data, err := os.ReadFile("/proc/meminfo"); err == nil {
		var memTotal, memAvailable uint64
		for _, line := range strings.Split(string(data), "\n") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				if fields[0] == "MemTotal:" {
					memTotal, _ = strconv.ParseUint(fields[1], 10, 64)
				} else if fields[0] == "MemAvailable:" {
					memAvailable, _ = strconv.ParseUint(fields[1], 10, 64)
				}
			}
		}
		if memTotal > 0 && memAvailable <= memTotal {
			used := memTotal - memAvailable
			sys.RAMPercent = int((used * 100) / memTotal)
		}
	}

	// 3. CPU usage via /proc/stat
	if data, err := os.ReadFile("/proc/stat"); err == nil {
		lines := strings.Split(string(data), "\n")
		if len(lines) > 0 && strings.HasPrefix(lines[0], "cpu ") {
			fields := strings.Fields(lines[0])
			if len(fields) >= 5 {
				var total uint64
				for _, f := range fields[1:] {
					v, _ := strconv.ParseUint(f, 10, 64)
					total += v
				}
				idle, _ := strconv.ParseUint(fields[4], 10, 64)
				if len(fields) >= 6 {
					iowait, _ := strconv.ParseUint(fields[5], 10, 64)
					idle += iowait
				}

				if lastCPUTotal > 0 && total > lastCPUTotal {
					deltaTotal := total - lastCPUTotal
					deltaIdle := idle - lastCPUIdle
					if deltaTotal > 0 && deltaTotal >= deltaIdle {
						sys.CPUPercent = int(((deltaTotal - deltaIdle) * 100) / deltaTotal)
					}
				}
				lastCPUTotal = total
				lastCPUIdle = idle
			}
		}
	}

	dm.mu.Lock()
	dm.telemetry.System = sys
	dm.mu.Unlock()
	dm.SaveTelemetry()
}

func findBlurHelper() string {
	home := os.Getenv("HOME")
	candidates := []string{
		filepath.Join(home, ".config/conky/macwidget/helpers/blur.py"),
		filepath.Join(home, ".local/share/weget/helpers/blur.py"),
		"/usr/share/weget/helpers/blur.py",
		"/app/share/weget/helpers/blur.py",
		"engine/helpers/blur.py",
		"helpers/blur.py",
		"../helpers/blur.py",
	}
	for _, c := range candidates {
		if fi, err := os.Stat(c); err == nil && !fi.IsDir() {
			return c
		}
	}
	return ""
}

func findPaletteHelper() string {
	home := os.Getenv("HOME")
	candidates := []string{
		filepath.Join(home, ".config/conky/macwidget/helpers/palette.py"),
		filepath.Join(home, ".local/share/weget/helpers/palette.py"),
		"/usr/share/weget/helpers/palette.py",
		"/app/share/weget/helpers/palette.py",
		"engine/helpers/palette.py",
		"helpers/palette.py",
		"../helpers/palette.py",
	}
	for _, c := range candidates {
		if fi, err := os.Stat(c); err == nil && !fi.IsDir() {
			return c
		}
	}
	return ""
}

func (dm *DaemonManager) updateBlur() {
	helper := findBlurHelper()
	if helper != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = exec.CommandContext(ctx, "python3", helper).Run()
	}
}

func (dm *DaemonManager) pollBlurLoop() {
	dm.updateBlur()
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			dm.updateBlur()
		case <-dm.stopChan:
			return
		}
	}
}

// -----------------------------------------------------------------------------
// Engine & Daemon Process Management
// -----------------------------------------------------------------------------

func isPidAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	statusBytes, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", pid))
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(statusBytes), "\n") {
		if strings.HasPrefix(line, "State:") {
			if strings.Contains(line, "Z (zombie)") || strings.Contains(line, "X (dead)") {
				return false
			}
			return true
		}
	}
	return true
}

func isBinaryRunnable(binPath string, libPath string) bool {
	if binPath == "" {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()

	cmd := exec.CommandContext(ctx, binPath, "-v")
	if libPath != "" {
		oldLD := os.Getenv("LD_LIBRARY_PATH")
		cmd.Env = append(os.Environ(), fmt.Sprintf("LD_LIBRARY_PATH=%s:%s", libPath, oldLD))
	}
	return cmd.Run() == nil
}

func (dm *DaemonManager) findConkyBinary() string {
	candidates := []string{}

	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(dir, "engine/conky/bin/conky"),
			filepath.Join(dir, "../engine/conky/bin/conky"),
			filepath.Join(dir, "../lib/weget/engine/bin/conky"),
		)
	}

	candidates = append(candidates,
		"/usr/lib/weget/engine/bin/conky",
		filepath.Join(os.Getenv("HOME"), ".local/share/weget/engine/conky/bin/conky"),
		filepath.Join(os.Getenv("HOME"), ".config/conky/macwidget/engine/conky/bin/conky"),
		"engine/conky/bin/conky",
		"../engine/conky/bin/conky",
	)

	// 1. Try bundled engine candidates (verifying dynamic libraries can load)
	for _, c := range candidates {
		if abs, err := filepath.Abs(c); err == nil {
			if info, err := os.Stat(abs); err == nil && !info.IsDir() && (info.Mode()&0111 != 0) {
				libDir := dm.findConkyLibDir(abs)
				if isBinaryRunnable(abs, libDir) {
					return abs
				}
			}
		}
	}

	// 2. Fall back to system conky
	if sysConky, err := exec.LookPath("conky"); err == nil {
		if isBinaryRunnable(sysConky, "") {
			return sysConky
		}
	}

	return ""
}

func (dm *DaemonManager) findConkyLibDir(binPath string) string {
	if binPath == "" {
		return ""
	}
	// Normal bundled layout: bin/conky -> lib/
	bundledLib := filepath.Join(filepath.Dir(binPath), "../lib")
	if info, err := os.Stat(bundledLib); err == nil && info.IsDir() {
		return bundledLib
	}
	return ""
}

func (dm *DaemonManager) findConfigFile() string {
	candidates := []string{
		filepath.Join(os.Getenv("HOME"), ".config/conky/macwidget/conky.conf"),
		"engine/conky.conf",
		"../engine/conky.conf",
		"conky.conf",
		"../conky.conf",
		"/usr/share/weget/conky.conf",
		"/app/share/weget/conky.conf",
		filepath.Join(os.Getenv("HOME"), ".local/share/weget/conky.conf"),
	}

	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(dir, "engine/conky.conf"),
			filepath.Join(dir, "../engine/conky.conf"),
			filepath.Join(dir, "conky.conf"),
			filepath.Join(dir, "../conky.conf"),
		)
	}

	for _, c := range candidates {
		if abs, err := filepath.Abs(c); err == nil {
			if info, err := os.Stat(abs); err == nil && !info.IsDir() {
				return abs
			}
		}
	}
	return ""
}

func waitForDisplayReady(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for {
		disp := os.Getenv("DISPLAY")
		wayland := os.Getenv("WAYLAND_DISPLAY")
		if disp != "" || wayland != "" {
			return true
		}
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(250 * time.Millisecond)
	}
	return false
}

func (dm *DaemonManager) getConkyLaunchParams() (binPath string, cfgPath string, env []string, err error) {
	binPath = dm.findConkyBinary()
	if binPath == "" {
		return "", "", nil, fmt.Errorf("no runnable Conky engine found (bundled engine is missing runtime libraries or system conky is not installed).\nFix by installing dependencies: sudo apt install conky-all")
	}
	cfgPath = dm.findConfigFile()
	if cfgPath == "" {
		return "", "", nil, fmt.Errorf("conky.conf not found")
	}
	libPath := dm.findConkyLibDir(binPath)

	env = os.Environ()
	if libPath != "" {
		oldLD := os.Getenv("LD_LIBRARY_PATH")
		env = append(env, fmt.Sprintf("LD_LIBRARY_PATH=%s:%s", libPath, oldLD))
		env = append(env, fmt.Sprintf("LUA_CPATH=%s/lib?.so;;", libPath))
	}
	return binPath, cfgPath, env, nil
}

// RunConkyStandalone replaces the current process with Conky directly via syscall.Exec.
// Zero Go background processes remain in memory.
func (dm *DaemonManager) RunConkyStandalone() error {
	waitForDisplayReady(5 * time.Second)

	binPath, cfgPath, env, err := dm.getConkyLaunchParams()
	if err != nil {
		return err
	}

	return syscall.Exec(binPath, []string{"conky", "-c", cfgPath}, env)
}

// StartConkyDirectBackground spawns Conky directly into the background without running any Go supervisor daemon.
func (dm *DaemonManager) StartConkyDirectBackground() error {
	dm.mu.Lock()
	defer dm.mu.Unlock()

	waitForDisplayReady(5 * time.Second)

	dm.killExistingConkyLocked()

	binPath, cfgPath, env, err := dm.getConkyLaunchParams()
	if err != nil {
		return err
	}

	dm.conkyBinPath = binPath
	dm.conkyLibPath = dm.findConkyLibDir(binPath)
	dm.configPath = cfgPath

	cacheDir := filepath.Join(os.Getenv("HOME"), ".cache/weget")
	_ = os.MkdirAll(cacheDir, 0755)
	logPath := filepath.Join(cacheDir, "conky.log")
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)

	cmd := exec.Command(binPath, "-c", cfgPath)
	cmd.Dir = filepath.Dir(cfgPath)
	cmd.Env = env
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err == nil {
		cmd.Stdout = logFile
		cmd.Stderr = logFile
		defer logFile.Close()
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start conky engine: %w", err)
	}

	// Verify child didn't immediately crash (e.g. exit 127 missing dynamic libraries)
	time.Sleep(150 * time.Millisecond)
	if cmd.Process == nil || !isPidAlive(cmd.Process.Pid) {
		dm.running = false
		dm.conkyCmd = nil
		errLog := ""
		if data, rErr := os.ReadFile(logPath); rErr == nil {
			errLog = strings.TrimSpace(string(data))
		}
		if errLog != "" {
			return fmt.Errorf("conky engine terminated immediately on launch: %s", errLog)
		}
		return fmt.Errorf("conky engine terminated immediately (check %s)", logPath)
	}

	dm.conkyCmd = cmd
	dm.running = true
	return nil
}

func (dm *DaemonManager) Start() error {
	return dm.StartConkyDirectBackground()
}

func (dm *DaemonManager) killExistingConkyLocked() {
	// 1. Terminate managed conky cmd
	if dm.conkyCmd != nil && dm.conkyCmd.Process != nil {
		_ = dm.conkyCmd.Process.Kill()
		_, _ = dm.conkyCmd.Process.Wait()
		dm.conkyCmd = nil
	}

	// 2. Terminate ONLY conky binaries matching macwidget / conky.conf
	out, err := exec.Command("pgrep", "-x", "conky").Output()
	if err == nil {
		pids := strings.Fields(string(out))
		for _, p := range pids {
			if pid, err := strconv.Atoi(p); err == nil && pid != os.Getpid() {
				cmdline, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
				if err == nil && (strings.Contains(string(cmdline), "macwidget") || strings.Contains(string(cmdline), "conky.conf")) {
					_ = syscall.Kill(pid, syscall.SIGKILL)
				}
			}
		}
	}
	dm.running = false
}


func (dm *DaemonManager) Stop() error {
	dm.mu.Lock()
	defer dm.mu.Unlock()

	dm.stopTelemetryLoopLocked()
	dm.killExistingConkyLocked()

	// Also kill any background weget daemon processes
	if out, err := exec.Command("pgrep", "-f", "weget daemon").Output(); err == nil {
		for _, p := range strings.Fields(string(out)) {
			if pid, err := strconv.Atoi(p); err == nil && pid != os.Getpid() {
				_ = syscall.Kill(pid, syscall.SIGTERM)
			}
		}
	}
	return nil
}

func (dm *DaemonManager) Restart() error {
	_ = dm.Stop()
	time.Sleep(200 * time.Millisecond)
	return dm.Start()
}

func (dm *DaemonManager) findRunningConkyPID() (string, bool) {
	if dm.conkyCmd != nil && dm.conkyCmd.Process != nil {
		pid := dm.conkyCmd.Process.Pid
		if dm.conkyCmd.ProcessState == nil && isPidAlive(pid) {
			if err := dm.conkyCmd.Process.Signal(syscall.Signal(0)); err == nil {
				return strconv.Itoa(pid), true
			}
		}
		dm.conkyCmd = nil
	}

	out, err := exec.Command("pgrep", "-x", "conky").Output()
	if err == nil {
		for _, p := range strings.Fields(string(out)) {
			if pid, err := strconv.Atoi(p); err == nil && pid != os.Getpid() && isPidAlive(pid) {
				cmdline, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
				if err == nil && (strings.Contains(string(cmdline), "macwidget") || strings.Contains(string(cmdline), "conky.conf")) {
					return strconv.Itoa(pid), true
				}
			}
		}
	}
	return "", false
}

func (dm *DaemonManager) Status() (bool, string, string, string) {
	dm.mu.RLock()
	defer dm.mu.RUnlock()

	pid, running := dm.findRunningConkyPID()

	uptime := ""
	if upOut, err := exec.Command("uptime", "-p").Output(); err == nil {
		uptime = strings.TrimSpace(string(upOut))
	}

	engine := "bundled"
	if strings.HasPrefix(dm.conkyBinPath, "/usr/bin/conky") {
		engine = "system"
	}

	return running, pid, uptime, engine
}

func (dm *DaemonManager) HandleMediaAction(action string) {
	helper := findMediaHelper()
	if helper != "" {
		_ = exec.Command("python3", helper, action).Run()
	} else if _, pErr := exec.LookPath("playerctl"); pErr == nil {
		switch action {
		case "play-pause", "play", "pause":
			_ = exec.Command("playerctl", "play-pause").Run()
		case "next":
			_ = exec.Command("playerctl", "next").Run()
		case "prev", "previous":
			_ = exec.Command("playerctl", "previous").Run()
		}
	}
	go dm.updateMedia()
}
