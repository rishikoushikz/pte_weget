package main

import (
	"embed"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

//go:embed ui/*
var uiFS embed.FS

// Version is set at link time via -ldflags "-X main.Version=..." (must stay a var).
var Version = "0.1"

func printUsage() {
	fmt.Printf(`Weget v%s
Usage:
  weget                Launch the Weget Settings UI
  weget widget         Run desktop widget directly (standalone Conky process)
  weget start          Start desktop widget in the background (standalone Conky)
  weget stop           Stop the desktop widget
  weget restart        Restart the desktop widget
  weget status         Show running status, PID, and engine mode
  weget autostart      Check or configure login autostart (starts pure Conky on login)
  weget version        Show version info
`, Version)
}

func findAppIcon() string {
	home := os.Getenv("HOME")
	candidates := []string{
		// 1. System pixmaps (standard universal location for .deb / .rpm)
		"/usr/share/pixmaps/weget.png",
		// 2. System hicolor sizes
		"/usr/share/icons/hicolor/256x256/apps/weget.png",
		"/usr/share/icons/hicolor/512x512/apps/weget.png",
		"/usr/share/icons/hicolor/128x128/apps/weget.png",
		"/usr/share/icons/hicolor/64x64/apps/weget.png",
		// 3. User local hicolor / pixmaps
		filepath.Join(home, ".local/share/icons/hicolor/256x256/apps/weget.png"),
		filepath.Join(home, ".local/share/icons/hicolor/512x512/apps/weget.png"),
		filepath.Join(home, ".local/share/pixmaps/weget.png"),
		// 4. Flatpak hicolor location
		"/app/share/icons/hicolor/512x512/apps/org.weget.Weget.png",
		"/app/share/icons/hicolor/256x256/apps/org.weget.Weget.png",
		// 5. System share weget assets
		"/usr/share/weget/assets/icon.png",
		filepath.Join(home, ".local/share/weget/assets/icon.png"),
	}

	// 6. Relative to currently running executable
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(dir, "assets/icons/hicolor/256x256/apps/weget.png"),
			filepath.Join(dir, "assets/icon.png"),
			filepath.Join(dir, "../assets/icon.png"),
			filepath.Join(dir, "usr/share/pixmaps/weget.png"),
		)
	}

	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}

	// 7. Fallback: extract embedded ui/icon.png to ~/.cache/weget/icon.png
	cacheIcon := filepath.Join(home, ".cache/weget/icon.png")
	if data, err := fs.ReadFile(uiFS, "ui/icon.png"); err == nil && len(data) > 0 {
		_ = os.MkdirAll(filepath.Dir(cacheIcon), 0755)
		if err := os.WriteFile(cacheIcon, data, 0644); err == nil {
			return cacheIcon
		}
	}

	return ""
}

func main() {
	if len(os.Args) > 1 {
		cmd := os.Args[1]
		switch cmd {
		case "widget", "run-widget":
			// Direct standalone Conky execution via syscall.Exec
			// Replaces current process with Conky directly: zero Go background processes!
			if err := GlobalDaemon.RunConkyStandalone(); err != nil {
				fmt.Fprintf(os.Stderr, "Error launching standalone widget: %v\n", err)
				os.Exit(1)
			}
			return

		case "start":
			fmt.Println("Starting Weget Desktop Widget (standalone Conky)...")
			if err := GlobalDaemon.StartConkyDirectBackground(); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			time.Sleep(300 * time.Millisecond)
			running, pid, _, engine := GlobalDaemon.Status()
			if running {
				fmt.Printf("✓ Conky running (PID: %s, Engine: %s)\n", pid, engine)
			} else {
				fmt.Println("Warning: process launched but not detected in pgrep yet.")
			}
			return

		case "stop":
			fmt.Println("Stopping Weget Desktop Widget...")
			if err := GlobalDaemon.Stop(); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			fmt.Println("✓ Weget stopped.")
			return

		case "restart":
			fmt.Println("Restarting Weget Desktop Widget...")
			if err := GlobalDaemon.Restart(); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			time.Sleep(400 * time.Millisecond)
			running, pid, _, engine := GlobalDaemon.Status()
			if running {
				fmt.Printf("✓ Weget restarted (PID: %s, Engine: %s)\n", pid, engine)
			} else {
				fmt.Println("Warning: process restarted but not detected yet.")
			}
			return

		case "status":
			running, pid, uptime, engine := GlobalDaemon.Status()
			if running {
				fmt.Printf("Status: RUNNING (PID %s)\nEngine: %s\nUptime: %s\n", pid, engine, uptime)
			} else {
				fmt.Println("Status: STOPPED")
			}
			return

		case "autostart":
			action := "status"
			if len(os.Args) > 2 {
				action = strings.ToLower(os.Args[2])
			}
			switch action {
			case "enable", "on", "1":
				if err := EnableAutostart(); err != nil {
					fmt.Fprintf(os.Stderr, "Error enabling autostart: %v\n", err)
					os.Exit(1)
				}
				fmt.Printf("✓ Autostart enabled via XDG Desktop Entry\n  File: %s\n  Exec: %s\n", getAutostartFilePath(), GetAutostartExecPath())
			case "disable", "off", "0":
				if err := DisableAutostart(); err != nil {
					fmt.Fprintf(os.Stderr, "Error disabling autostart: %v\n", err)
					os.Exit(1)
				}
				fmt.Println("✓ Autostart disabled (entry removed from ~/.config/autostart)")
			case "toggle":
				enabled := IsAutostartEnabled()
				if err := SetAutostart(!enabled); err != nil {
					fmt.Fprintf(os.Stderr, "Error toggling autostart: %v\n", err)
					os.Exit(1)
				}
				if !enabled {
					fmt.Printf("✓ Autostart enabled (%s)\n", getAutostartFilePath())
				} else {
					fmt.Println("✓ Autostart disabled")
				}
			case "status":
				if IsAutostartEnabled() {
					fmt.Printf("Autostart: ENABLED\nEntry: %s\nExec:  %s\n", getAutostartFilePath(), GetAutostartExecPath())
				} else {
					fmt.Println("Autostart: DISABLED")
				}
			default:
				fmt.Fprintf(os.Stderr, "Unknown autostart action: %s (use enable, disable, toggle, or status)\n", action)
				os.Exit(1)
			}
			return

		case "daemon":
			fmt.Printf("Starting Weget Headless Supervisor v%s...\n", Version)
			go GlobalDaemon.StartTelemetryLoop()
			if err := GlobalDaemon.Start(); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			sigChan := make(chan os.Signal, 1)
			signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
			<-sigChan
			_ = GlobalDaemon.Stop()
			return

		case "version", "-v", "--version":
			fmt.Printf("Weget v%s (Inbuilt Cairo/Conky Runtime)\n", Version)
			return

		case "help", "-h", "--help":
			printUsage()
			return

		default:
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", cmd)
			printUsage()
			os.Exit(1)
		}
	}

	// Default: Start Telemetry loop & Launch UI Server
	go GlobalDaemon.StartTelemetryLoop()

	// Automatically start widget if not already running
	if running, _, _, _ := GlobalDaemon.Status(); !running {
		go func() {
			if err := GlobalDaemon.Start(); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: unable to start widget engine: %v\n", err)
			}
		}()
	}

	subFS, err := fs.Sub(uiFS, "ui")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error embedding UI: %v\n", err)
		os.Exit(1)
	}

	mux := http.NewServeMux()
	SetupAPIRoutes(mux)
	ServeStatic(mux, http.FS(subFS))

	// Listen on fixed local port 46381 with fallback
	listener, err := net.Listen("tcp", "127.0.0.1:46381")
	if err != nil {
		listener, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error binding local port: %v\n", err)
			os.Exit(1)
		}
	}
	port := listener.Addr().(*net.TCPAddr).Port
	url := fmt.Sprintf("http://127.0.0.1:%d/", port)

	go func() {
		if err := http.Serve(listener, mux); err != nil {
			fmt.Fprintf(os.Stderr, "Server exited: %v\n", err)
		}
	}()

	iconPath := findAppIcon()
	launchAppWindow(url, "Weget — Modern Desktop Widgets", iconPath, 840, 700)
}
