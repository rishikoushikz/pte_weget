package main

import (
	"embed"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/exec"
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
  weget                Launch the Weget Settings UI and start widget
  weget start          Start the desktop widget daemon natively
  weget stop           Stop the desktop widget daemon natively
  weget restart        Restart the desktop widget daemon
  weget status         Show running status, PID, and engine mode
  weget daemon         Run headless background telemetry and widget supervisor
  weget version        Show version info
`, Version)
}

func main() {
	if len(os.Args) > 1 {
		cmd := os.Args[1]
		switch cmd {
		case "start":
			fmt.Println("Starting Weget Desktop Widget...")
			// Launch headless daemon in background if not already running
			if out, err := exec.Command("pgrep", "-f", "weget daemon").Output(); err != nil || len(strings.TrimSpace(string(out))) == 0 {
				exe, err := os.Executable()
				if err == nil {
					cmd := exec.Command(exe, "daemon")
					cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
					_ = cmd.Start()
				}
			} else {
				_ = GlobalDaemon.Start()
			}
			time.Sleep(500 * time.Millisecond)
			running, pid, _, engine := GlobalDaemon.Status()
			if running {
				fmt.Printf("✓ Weget running (PID: %s, Engine: %s)\n", pid, engine)
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
			_ = GlobalDaemon.Start()
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

	iconPath := filepath.Join(os.Getenv("HOME"), ".local/share/icons/hicolor/256x256/apps/weget.png")
	launchAppWindow(url, "Weget — Modern Desktop Widgets", iconPath, 840, 700)
}
