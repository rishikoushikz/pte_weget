package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func getAutostartDir() string {
	configHome := os.Getenv("XDG_CONFIG_HOME")
	if configHome == "" {
		configHome = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(configHome, "autostart")
}

func getAutostartFilePath() string {
	return filepath.Join(getAutostartDir(), "weget.desktop")
}

func GetAutostartExecPath() string {
	if _, err := os.Stat("/usr/bin/weget-widget"); err == nil {
		return "/usr/bin/weget-widget"
	}
	home := os.Getenv("HOME")
	localWidget := filepath.Join(home, ".local/bin/weget-widget")
	if _, err := os.Stat(localWidget); err == nil {
		return localWidget
	}
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidate := filepath.Join(dir, "weget-widget")
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return "weget-widget"
}

func IsAutostartEnabled() bool {
	p := getAutostartFilePath()
	data, err := os.ReadFile(p)
	if err != nil {
		return false
	}
	content := string(data)
	if strings.Contains(content, "X-GNOME-Autostart-enabled=false") || strings.Contains(content, "Hidden=true") {
		return false
	}
	return strings.Contains(content, "Exec=")
}

func EnableAutostart() error {
	dir := getAutostartDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	execCmd := GetAutostartExecPath()
	entry := fmt.Sprintf(`[Desktop Entry]
Type=Application
Name=Weget
GenericName=Desktop Widget System
Comment=Start Weget Desktop Widgets on login
Exec=%s
Icon=weget
Terminal=false
Categories=Utility;
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=4
`, execCmd)

	filePath := getAutostartFilePath()
	if err := os.WriteFile(filePath, []byte(entry), 0644); err != nil {
		return err
	}

	// Clean up any legacy elysium.desktop that referenced start.sh or elysium
	legacyPath := filepath.Join(dir, "elysium.desktop")
	if data, err := os.ReadFile(legacyPath); err == nil {
		if strings.Contains(string(data), "start.sh") || strings.Contains(string(data), "elysium") {
			_ = os.Remove(legacyPath)
		}
	}

	return nil
}

func DisableAutostart() error {
	p := getAutostartFilePath()
	if _, err := os.Stat(p); err == nil {
		if err := os.Remove(p); err != nil {
			return err
		}
	}

	// Also clean up any legacy elysium.desktop referencing start.sh or elysium
	legacyPath := filepath.Join(getAutostartDir(), "elysium.desktop")
	if data, err := os.ReadFile(legacyPath); err == nil {
		if strings.Contains(string(data), "start.sh") || strings.Contains(string(data), "elysium") {
			_ = os.Remove(legacyPath)
		}
	}

	return nil
}

func SetAutostart(enable bool) error {
	if enable {
		return EnableAutostart()
	}
	return DisableAutostart()
}
