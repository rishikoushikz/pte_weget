//go:build !cgo

package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
)

func findWebviewHelper() string {
	candidates := []string{
		filepath.Join(os.Getenv("HOME"), ".config/conky/macwidget/helpers/webview.py"),
		"/usr/share/weget/helpers/webview.py",
		"/app/share/weget/helpers/webview.py",
		"engine/helpers/webview.py",
		"helpers/webview.py",
		"../helpers/webview.py",
	}

	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(dir, "engine/helpers/webview.py"),
			filepath.Join(dir, "helpers/webview.py"),
			filepath.Join(dir, "../helpers/webview.py"),
		)
	}

	for _, p := range candidates {
		if abs, err := filepath.Abs(p); err == nil {
			if info, err := os.Stat(abs); err == nil && !info.IsDir() {
				return abs
			}
		}
	}
	return ""
}

func launchAppWindow(url, title, iconPath string, width, height int) {
	fmt.Printf("Weget Ecosystem Manager running at: %s\n", url)

	webviewHelper := findWebviewHelper()
	if webviewHelper != "" {
		if python, err := exec.LookPath("python3"); err == nil {
			cmd := exec.Command(python, webviewHelper, url, title, iconPath, strconv.Itoa(width), strconv.Itoa(height))
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr

			// Handle termination signals while window is open
			sigChan := make(chan os.Signal, 1)
			signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
			go func() {
				<-sigChan
				if cmd.Process != nil {
					cmd.Process.Kill()
				}
			}()

			fmt.Println("Launching native WebKitGTK desktop window...")
			if err := cmd.Run(); err == nil {
				fmt.Println("\nWeget window closed. Shutting down Weget Manager...")
				return
			}
			fmt.Fprintf(os.Stderr, "Native window exited or WebKit2GTK unavailable: %v\n", err)
		}
	}

	// Fallback to browser if native window helper is not available
	fmt.Println("Opening in default browser fallback...")
	if err := exec.Command("xdg-open", url).Start(); err != nil {
		fmt.Fprintf(os.Stderr, "Could not open browser automatically: %v. Please open %s manually.\n", err, url)
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan
	fmt.Println("\nShutting down Weget Manager...")
}
