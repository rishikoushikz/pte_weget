.PHONY: all build run widget start stop restart status autostart install uninstall deb rpm appimage flatpak flatpak-bundle tarball packages clean help

PYTHON := python3

all: build

help:
	@echo "Weget — Modern Desktop Widget Ecosystem"
	@echo ""
	@echo "Development & Lifecycle:"
	@echo "  make run        - Build and launch the Weget UI manager"
	@echo "  make widget     - Run standalone desktop widget directly"
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
	@python3 package/builder.py build

run:
	@python3 package/builder.py run

widget:
	@python3 package/builder.py widget

start:
	@python3 package/builder.py start

stop:
	@python3 package/builder.py stop

restart:
	@python3 package/builder.py restart

status:
	@python3 package/builder.py status

autostart:
	@python3 package/builder.py autostart $(filter-out $@,$(MAKECMDGOALS))

install:
	@python3 package/builder.py install

uninstall:
	@python3 package/builder.py uninstall

deb:
	@python3 package/builder.py deb

rpm:
	@python3 package/builder.py rpm

appimage:
	@python3 package/builder.py appimage

flatpak:
	@python3 package/builder.py flatpak

flatpak-bundle:
	@python3 package/builder.py flatpak-bundle

tarball:
	@python3 package/builder.py tarball

packages:
	@python3 package/builder.py packages

clean:
	@python3 package/builder.py clean
