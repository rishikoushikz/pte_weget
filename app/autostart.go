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
	home := os.Getenv("HOME")
	localBin := filepath.Join(home, ".local/bin/weget")
	if _, err := os.Stat(localBin); err == nil {
		return localBin + " start"
	}
	if _, err := os.Stat("/usr/bin/weget"); err == nil {
		return "/usr/bin/weget start"
	}
	if exe, err := os.Executable(); err == nil {
		if abs, err := filepath.Abs(exe); err == nil {
			return abs + " start"
		}
	}
	return "weget start"
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
X-GNOME-Autostart-Delay=3
`, execCmd)

	filePath := getAutostartFilePath()
	if err := os.WriteFile(filePath, []byte(entry), 0644); err != nil {
		return err
	}

	// Clean up any legacy elysium.desktop that referenced start.sh
	legacyPath := filepath.Join(dir, "elysium.desktop")
	if data, err := os.ReadFile(legacyPath); err == nil {
		if strings.Contains(string(data), "start.sh") {
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

	// Also clean up any legacy elysium.desktop referencing start.sh
	legacyPath := filepath.Join(getAutostartDir(), "elysium.desktop")
	if data, err := os.ReadFile(legacyPath); err == nil {
		if strings.Contains(string(data), "start.sh") {
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
