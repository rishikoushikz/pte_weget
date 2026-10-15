.PHONY: all build run start stop restart status autostart install uninstall deb rpm appimage flatpak flatpak-bundle tarball packages clean help

PYTHON ?= python3

all: build

help:
	@echo "Weget — Modern Desktop Widget Ecosystem"
	@echo ""
	@echo "Development & Lifecycle:"
	@echo "  make run        - Build and launch the Weget UI manager"
	@echo "  make build      - Compile the Weget binary"
	@echo "  make start      - Start desktop widgets natively"
	@echo "  make stop       - Stop desktop widgets"
	@echo "  make restart    - Restart desktop widgets"
	@echo "  make status     - Check widget daemon status"
	@echo "  make autostart  - Check or configure login autostart (no .sh)"
	@echo ""
	@echo "System Installation:"
	@echo "  make install    - Install to ~/.local (no root required)"
	@echo "  make uninstall  - Remove from ~/.local"
	@echo ""
	@echo "Package Distribution (with Inbuilt Conky Engine):"
	@echo "  make deb        - Export Debian package (.deb)"
	@echo "  make rpm        - Export RPM spec and archive (.rpm)"
	@echo "  make appimage   - Export universal AppImage (.AppImage)"
	@echo "  make flatpak    - Export Flatpak manifest & metainfo"
	@echo "  make flatpak-bundle - Build the .flatpak bundle"
	@echo "  make tarball    - Build portable binary tarball (.tar.gz)"
	@echo "  make packages   - Build all package formats"
	@echo "  make clean      - Clean build artifacts"

build:
	@$(PYTHON) package/builder.py build

run:
	@$(PYTHON) package/builder.py run

start:
	@$(PYTHON) package/builder.py start

stop:
	@$(PYTHON) package/builder.py stop

restart:
	@$(PYTHON) package/builder.py restart

status:
	@$(PYTHON) package/builder.py status

autostart:
	@$(PYTHON) package/builder.py autostart $(filter-out $@,$(MAKECMDGOALS))

install:
	@$(PYTHON) package/builder.py install

uninstall:
	@$(PYTHON) package/builder.py uninstall

deb:
	@$(PYTHON) package/builder.py deb

rpm:
	@$(PYTHON) package/builder.py rpm

appimage:
	@$(PYTHON) package/builder.py appimage

flatpak:
	@$(PYTHON) package/builder.py flatpak

flatpak-bundle:
	@$(PYTHON) package/builder.py flatpak-bundle

tarball:
	@$(PYTHON) package/builder.py tarball

packages:
	@$(PYTHON) package/builder.py packages

clean:
	@$(PYTHON) package/builder.py clean
