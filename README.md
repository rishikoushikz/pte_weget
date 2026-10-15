# Weget

A native Linux desktop widget manager built in Go with a bundled Conky / Cairo runtime engine.

---

## Key Features

- **Inbuilt Conky Runtime Engine**: Conky and all required Cairo, Xlib, and RSVG plugin libraries are bundled within Weget (`engine/conky/`), so Conky does not need to be installed separately.
- **Async Telemetry**: weather, media MPRIS, Wi-Fi SSID, and quotes are polled in background Go goroutines and written to a JSON cache; Lua reads the cache in the render loop.
- **Unified Build System**: a single root `Makefile` and `package/builder.py` manage dev runs, daemon controls, and package exports.
- **Multi-Format Packaging**: build targets for `.deb`, `.rpm`, `AppImage`, and `Flatpak` with bundled engines.
- **9 Module Families × 3 Variants**: 27 modular widgets covering Network, Calendar, Analog Clock, Digital Clock, Storage, Rings Meter, Weather, Quotes, and Media Player across 1x1 Minimal, 1x1 Detailed, and 2x1 Wide layouts.

---

## Architecture Overview

```mermaid
graph TD
    UI[Weget App: Native Go Manager] -->|REST API| Config[engine/settings/settings.json]
    Daemon[Go Daemon & Telemetry Engine] -->|Async Poller| Cache[/tmp/weget_telemetry.json]
    Engine[Bundled Conky Cairo Engine: engine/conky] -->|Read Cache| Lua[engine/macwidget.lua]
    Lua -->|Pure Cairo Vector Drawing| Desktop[Desktop Widget Window]
```

---

## Unified Build & Management

Manage Weget using the root `Makefile` (or `package/builder.py`):

### Development & Execution
```bash
make run        # Build and launch the Weget UI manager
make build      # Compile the Weget binary
make start      # Start desktop widgets natively
make stop       # Stop desktop widgets
make restart    # Restart desktop widgets
make status     # Show daemon running status, PID, and engine mode
```

### System Installation (User Mode)
```bash
make install    # Install binary, bundled engine, assets, and desktop file to ~/.local
make uninstall  # Cleanly remove Weget from ~/.local
```

### Multi-Format Package Export
```bash
make deb             # Build Debian/Ubuntu package: dist/weget_0.1_amd64.deb
make rpm             # Generate RPM spec & archive: dist/weget-0.1.tar.gz & dist/weget.spec
make appimage        # Build universal AppImage: dist/Weget-0.1-x86_64.AppImage
make flatpak         # Generate Flatpak manifest: dist/org.weget.Weget.yml
make flatpak-bundle  # Build the .flatpak bundle: dist/Weget-0.1.flatpak
make tarball         # Portable binary tarball: dist/weget-0.1-x86_64.tar.gz
make packages        # Build every package format at once
```

Set `WEGET_VERSION` to override the version baked into the binary and package names
(used by CI to derive the version from the git tag):
```bash
WEGET_VERSION=0.2.0 make packages
```

---

## Releases & CI

Two GitHub Actions workflows live in `.github/workflows/`:

- **`ci.yml`** — on every push to `main` and every pull request: installs the GTK/WebKit
  build deps, runs `go vet`, builds the binary, and runs a smoke test.
- **`release.yml`** — on a `v*` tag (or manually via *workflow_dispatch*): builds every
  package format and publishes them to a GitHub Release.

To cut a release, bump the version and push a tag:
```bash
git tag v0.2.0
git push origin v0.2.0
```
The workflow derives the version from the tag (`v0.2.0` → `0.2.0`), builds the `.deb`,
`.rpm` (+ spec/source), `.AppImage`, `.flatpak`, and portable `.tar.gz`, and attaches them
to the release with auto-generated notes.

---

## CLI Usage

The `weget` binary provides native subcommands for process management:

```bash
weget start      # Start widgets in background
weget stop       # Stop widgets
weget restart    # Restart widgets instantly
weget status     # Display running state, PID, uptime, and engine mode
weget daemon     # Run headless supervisor and background telemetry loop
weget version    # Print version and engine build
```

---

## Module Catalog (9 Families × 3 Formats)

| Family | 1x1 Minimal | 1x1 Detailed | 2x1 Wide |
| :--- | :--- | :--- | :--- |
| **Network** | `NETW_1x1_MIN` | `NETW_1x1_DET` | `NETW_2x1_WID` |
| **Calendar** | `CALN_1x1_MIN` | `CALN_1x1_DET` | `CALN_2x1_WID` |
| **Analog Clock** | `CLKA_1x1_MIN` | `CLKA_1x1_DET` | `CLKA_2x1_WID` |
| **Digital Clock** | `CLKD_1x1_MIN` | `CLKD_1x1_DET` | `CLKD_2x1_WID` |
| **Storage** | `STOR_1x1_MIN` | `STOR_1x1_DET` | `STOR_2x1_WID` |
| **Rings Meter** | `RING_1x1_MIN` | `RING_1x1_DET` | `RING_2x1_WID` |
| **Weather** | `WEAT_1x1_MIN` | `WEAT_1x1_DET` | `WEAT_2x1_WID` |
| **Inspiration Quote**| `QUOT_1x1_MIN` | `QUOT_1x1_DET` | `QUOT_2x1_WID` |
| **Media Player** | `MEDI_1x1_MIN` | `MEDI_1x1_DET` | `MEDI_2x1_WID` |

---

## Directory Layout

- **`app/`**: Native Go manager, embedded WebKit UI, daemon supervisor, and telemetry pollers.
- **`engine/`**: Self-contained runtime — bundled Conky binary, config, renderer, helpers, and settings.
  - **`engine/conky/`**: Bundled Conky binary and Cairo/RSVG plugins.
  - **`engine/conky.conf`**: Desktop window and Cairo hook configuration.
  - **`engine/macwidget.lua`**: Cairo canvas rendering for all 27 widgets.
  - **`engine/helpers/`**: Runtime Python helpers (media control, blur generation, webview).
  - **`engine/settings/`**: Default user settings and slot assignment matrix.
- **`package/`**: Packaging templates (`.deb`, `.rpm`, AppImage, Flatpak) and `builder.py`, the unified build/install tool.
- **`assets/`**: Application icons and branding.
- **`docs/`**: Design references and showcase pages.
- **`dist/`**: Exported distribution packages (`.deb`, `.rpm`, `.AppImage`, Flatpak).
- **`Makefile`**: Root entry point wrapping `package/builder.py`.
