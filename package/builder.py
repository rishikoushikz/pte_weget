#!/usr/bin/env python3
"""
Weget Unified Build System & Multi-Format Exporter
Builds Weget Go binary and packages:
  - deb: Debian / Ubuntu package (.deb)
  - rpm: RedHat / Fedora / openSUSE package (.rpm & .spec)
  - appimage: Universal Linux AppImage (.AppImage)
  - flatpak: Flatpak bundle / manifest
All packages bundle the self-contained Cairo/Conky runtime engine.
"""

import sys
import os
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

VERSION = os.environ.get("WEGET_VERSION", "0.1")
PKG_NAME = "weget"
ROOT_DIR = Path(__file__).resolve().parent.parent
DIST_DIR = ROOT_DIR / "dist"
ENGINE_DIR = ROOT_DIR / "engine" / "conky"
# Runtime config/lua live alongside the bundled engine under engine/.
RUNTIME_DIR = ROOT_DIR / "engine"


def log(msg):
    print(f"\033[1;34m[weget-build]\033[0m {msg}")


def log_ok(msg):
    print(f"\033[1;32m[✓]\033[0m {msg}")


def log_err(msg):
    print(f"\033[1;31m[✗]\033[0m {msg}", file=sys.stderr)


def run_cmd(cmd, cwd=None, env=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    res = subprocess.run(cmd, cwd=cwd, env=merged_env, shell=isinstance(cmd, str))
    if res.returncode != 0:
        raise RuntimeError(f"Command failed with code {res.returncode}: {cmd}")


def build_binary():
    log("Compiling Weget binary from app...")
    go_app_dir = ROOT_DIR / "app"
    tmp_bin = go_app_dir / "weget"
    run_cmd(["go", "build", "-trimpath", "-ldflags", f"-s -w -X main.Version={VERSION}", "-o", str(tmp_bin), "."], cwd=go_app_dir)
    target_bin = ROOT_DIR / "weget"
    # Atomic replace to prevent "Text file busy"
    tmp_target = ROOT_DIR / "weget.tmp"
    shutil.copy2(tmp_bin, tmp_target)
    os.chmod(tmp_target, 0o755)
    os.replace(tmp_target, target_bin)
    log_ok(f"Compiled binary: {target_bin}")



def stage_package_tree(target_root: Path):
    """
    Populates target_root with standard Linux hierarchy including bundled conky engine.
    """
    bin_dir = target_root / "usr" / "bin"
    lib_engine_bin = target_root / "usr" / "lib" / "weget" / "engine" / "bin"
    lib_engine_lib = target_root / "usr" / "lib" / "weget" / "engine" / "lib"
    share_dir = target_root / "usr" / "share" / "weget"
    apps_dir = target_root / "usr" / "share" / "applications"
    icons_dir = target_root / "usr" / "share" / "icons" / "hicolor" / "256x256" / "apps"

    for d in [bin_dir, lib_engine_bin, lib_engine_lib, share_dir, apps_dir, icons_dir]:
        d.mkdir(parents=True, exist_ok=True)

    # 1. Main Weget binary
    if not (ROOT_DIR / "weget").exists():
        build_binary()
    shutil.copy2(ROOT_DIR / "weget", bin_dir / "weget")
    os.chmod(bin_dir / "weget", 0o755)

    # 2. Bundled Conky engine & cairo libraries
    conky_bin = ENGINE_DIR / "bin" / "conky"
    if conky_bin.exists():
        shutil.copy2(conky_bin, lib_engine_bin / "conky")
        os.chmod(lib_engine_bin / "conky", 0o755)

    conky_lib = ENGINE_DIR / "lib"
    if conky_lib.exists():
        for so in conky_lib.glob("*.so"):
            shutil.copy2(so, lib_engine_lib / so.name)
            os.chmod(lib_engine_lib / so.name, 0o644)

    # 3. Lua widget scripts & configs
    shutil.copy2(RUNTIME_DIR / "macwidget.lua", share_dir / "macwidget.lua")
    shutil.copy2(RUNTIME_DIR / "conky.conf", share_dir / "conky.conf")

    if (RUNTIME_DIR / "settings").exists():
        settings_target = share_dir / "settings"
        settings_target.mkdir(exist_ok=True)
        for s in (RUNTIME_DIR / "settings").glob("*.json"):
            shutil.copy2(s, settings_target / s.name)

    if (RUNTIME_DIR / "helpers").exists():
        helpers_target = share_dir / "helpers"
        helpers_target.mkdir(exist_ok=True)
        for h in (RUNTIME_DIR / "helpers").glob("*"):
            shutil.copy2(h, helpers_target / h.name)
            os.chmod(helpers_target / h.name, 0o755)

    if (ROOT_DIR / "assets").exists():
        assets_target = share_dir / "assets"
        assets_target.mkdir(exist_ok=True)
        for a in (ROOT_DIR / "assets").glob("*.*"):
            shutil.copy2(a, assets_target / a.name)

    # 4. Desktop entry & Multi-Resolution Icons
    desktop_file = apps_dir / "weget.desktop"
    desktop_content = """[Desktop Entry]
Name=Weget
GenericName=Desktop Widget System
Comment=Modern macOS-style interactive desktop widgets for Linux
Exec=weget
Icon=weget
Terminal=false
Type=Application
Categories=Utility;DesktopSettings;GTK;
StartupNotify=true
StartupWMClass=weget
Keywords=widget;desktop;system;clock;calendar;weather;conky;
"""
    desktop_file.write_text(desktop_content)

    # Multi-resolution hicolor icon suite (16x16 to 512x512)
    sizes = [16, 32, 48, 64, 128, 256, 512]
    for s in sizes:
        d = target_root / "usr" / "share" / "icons" / "hicolor" / f"{s}x{s}" / "apps"
        d.mkdir(parents=True, exist_ok=True)
        src_icon = ROOT_DIR / "assets" / "icons" / "hicolor" / f"{s}x{s}" / "apps" / "weget.png"
        if src_icon.exists():
            shutil.copy2(src_icon, d / "weget.png")
        else:
            shutil.copy2(ROOT_DIR / "assets" / "icon.png", d / "weget.png")

    # Universal pixmaps fallback
    pixmaps_dir = target_root / "usr" / "share" / "pixmaps"
    pixmaps_dir.mkdir(parents=True, exist_ok=True)
    pixmap_src = ROOT_DIR / "assets" / "icons" / "pixmaps" / "weget.png"
    if pixmap_src.exists():
        shutil.copy2(pixmap_src, pixmaps_dir / "weget.png")
    else:
        shutil.copy2(ROOT_DIR / "assets" / "icon.png", pixmaps_dir / "weget.png")


def build_deb():
    log("Building Debian package (.deb)...")
    DIST_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="weget_deb_") as tmp_dir:
        stage_dir = Path(tmp_dir) / "weget"
        stage_package_tree(stage_dir)

        # Control file
        debian_dir = stage_dir / "DEBIAN"
        debian_dir.mkdir(parents=True, exist_ok=True)
        control_file = debian_dir / "control"
        control_content = f"""Package: {PKG_NAME}
Version: {VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Weget Project <support@weget.org>
Description: Modern macOS-style interactive desktop widgets for Linux
 Weget provides modular Cairo desktop widgets (Clock, Calendar,
 Weather, Storage, Media, Rings, Quotes, Network) powered by an inbuilt
 Conky runtime engine with zero manual dependencies.
"""
        control_file.write_text(control_content)

        # Post-install hook: update desktop databases & icons
        postinst = debian_dir / "postinst"
        postinst.write_text("""#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
    /usr/bin/update-desktop-database -q /usr/share/applications || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
""")
        os.chmod(postinst, 0o755)

        # Post-remove hook: clean icon and desktop cache
        postrm = debian_dir / "postrm"
        postrm.write_text("""#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
    /usr/bin/update-desktop-database -q /usr/share/applications || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
""")
        os.chmod(postrm, 0o755)

        output_deb = DIST_DIR / f"{PKG_NAME}_{VERSION}_amd64.deb"
        run_cmd(["dpkg-deb", "--build", "--root-owner-group", str(stage_dir), str(output_deb)])
        log_ok(f"Created Debian package: {output_deb} ({output_deb.stat().st_size // 1024} KB)")


def build_rpm():
    log("Building RPM package (.rpm) & Specfile...")
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    spec_file = DIST_DIR / "weget.spec"
    spec_content = f"""Name:           weget
Version:        {VERSION}
Release:        1%{{?dist}}
Summary:        Modern macOS-style interactive desktop widgets for Linux
License:        MIT
URL:            https://github.com/weget/weget
BuildArch:      x86_64

AutoReqProv:    no

Source0:        %{{name}}-%{{version}}.tar.gz

%description
Weget provides modular Cairo desktop widgets (Clock, Calendar,
Weather, Storage, Media, Rings, Quotes, Network) powered by an inbuilt
Conky runtime engine with zero manual dependencies.

%prep
%setup -q

%build

%install
rm -rf %{{buildroot}}
mkdir -p %{{buildroot}}/usr/bin
mkdir -p %{{buildroot}}/usr/lib/weget/engine/bin
mkdir -p %{{buildroot}}/usr/lib/weget/engine/lib
mkdir -p %{{buildroot}}/usr/share/weget
mkdir -p %{{buildroot}}/usr/share/applications
mkdir -p %{{buildroot}}/usr/share/pixmaps

install -m 755 usr/bin/weget %{{buildroot}}/usr/bin/weget
install -m 755 usr/lib/weget/engine/bin/conky %{{buildroot}}/usr/lib/weget/engine/bin/conky
install -m 644 usr/lib/weget/engine/lib/*.so %{{buildroot}}/usr/lib/weget/engine/lib/
cp -a usr/share/weget/* %{{buildroot}}/usr/share/weget/
install -m 644 usr/share/applications/weget.desktop %{{buildroot}}/usr/share/applications/weget.desktop
cp -a usr/share/icons %{{buildroot}}/usr/share/
install -m 644 usr/share/pixmaps/weget.png %{{buildroot}}/usr/share/pixmaps/weget.png

%post
/bin/touch --no-create %{{_datadir}}/icons/hicolor &>/dev/null || :
/usr/bin/update-desktop-database &>/dev/null || :

%postun
if [ $1 -eq 0 ] ; then
    /bin/touch --no-create %{{_datadir}}/icons/hicolor &>/dev/null
    /usr/bin/gtk-update-icon-cache %{{_datadir}}/icons/hicolor &>/dev/null || :
fi
/usr/bin/update-desktop-database &>/dev/null || :

%posttrans
/usr/bin/gtk-update-icon-cache %{{_datadir}}/icons/hicolor &>/dev/null || :

%files
/usr/bin/weget
/usr/lib/weget
/usr/share/weget
/usr/share/applications/weget.desktop
/usr/share/icons/hicolor/*/apps/weget.png
/usr/share/pixmaps/weget.png

%changelog
* Wed Oct 15 2026 Weget Team <support@weget.org> - {VERSION}-1
- Release {VERSION} with bundled Conky engine.
"""
    spec_file.write_text(spec_content)

    # Create portable source tarball with staging structure
    tar_output = DIST_DIR / f"{PKG_NAME}-{VERSION}.tar.gz"
    with tempfile.TemporaryDirectory(prefix="weget_rpm_") as tmp_dir:
        stage_dir = Path(tmp_dir) / f"{PKG_NAME}-{VERSION}"
        stage_package_tree(stage_dir)
        with tarfile.open(tar_output, "w:gz") as tar:
            tar.add(stage_dir, arcname=f"{PKG_NAME}-{VERSION}")

    # Build RPM directly if rpmbuild is available, or use cpio-based packaging
    if shutil.which("rpmbuild"):
        topdir = DIST_DIR / "rpmbuild"
        sources_dir = topdir / "SOURCES"
        sources_dir.mkdir(parents=True, exist_ok=True)
        # rpmbuild looks for Source0 inside %{_sourcedir}.
        shutil.copy2(tar_output, sources_dir / tar_output.name)
        try:
            run_cmd(["rpmbuild", "-bb", "--define", f"_topdir {topdir}", str(spec_file)])
            for rpm in (topdir / "RPMS").rglob("*.rpm"):
                shutil.copy2(rpm, DIST_DIR / rpm.name)
                log_ok(f"Created RPM package: {DIST_DIR / rpm.name}")
        except Exception as e:
            log(f"rpmbuild execution noted: {e}")

    # Create stand-alone binary package bundle for RPM systems
    log_ok(f"Generated RPM Spec: {spec_file}")
    log_ok(f"Generated RPM Source Archive: {tar_output}")


def build_appimage():
    log("Building AppImage package (.AppImage)...")
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    appdir = DIST_DIR / "AppDir"
    if appdir.exists():
        shutil.rmtree(appdir)
    stage_package_tree(appdir)

    # AppRun entrypoint
    apprun = appdir / "AppRun"
    apprun_script = """#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib/weget/engine/lib:${LD_LIBRARY_PATH}"
export LUA_CPATH="${HERE}/usr/lib/weget/engine/lib/lib?.so;;"
exec "${HERE}/usr/bin/weget" "$@"
"""
    apprun.write_text(apprun_script)
    os.chmod(apprun, 0o755)

    # Root desktop file and icon for AppImage specification
    shutil.copy2(appdir / "usr" / "share" / "applications" / "weget.desktop", appdir / "weget.desktop")
    shutil.copy2(appdir / "usr" / "share" / "icons" / "hicolor" / "256x256" / "apps" / "weget.png", appdir / "weget.png")
    shutil.copy2(appdir / "usr" / "share" / "icons" / "hicolor" / "256x256" / "apps" / "weget.png", appdir / ".DirIcon")

    output_appimage = DIST_DIR / f"Weget-{VERSION}-x86_64.AppImage"

    # Check for appimagetool
    appimagetool = Path(os.path.expanduser("~/.cache/weget/tools/appimagetool"))
    if not appimagetool.exists() or not os.access(appimagetool, os.X_OK):
        appimagetool = shutil.which("appimagetool")

    if appimagetool and Path(appimagetool).exists():
        env = os.environ.copy()
        env["ARCH"] = "x86_64"
        cmd = [str(appimagetool)]
        cached_runtime = Path(os.path.expanduser("~/.cache/weget/tools/runtime-x86_64"))
        if cached_runtime.exists():
            cmd.extend(["--runtime-file", str(cached_runtime)])
        cmd.extend([str(appdir), str(output_appimage)])
        run_cmd(cmd, env=env)
        log_ok(f"Created AppImage: {output_appimage} ({output_appimage.stat().st_size // 1024} KB)")
    elif shutil.which("mksquashfs"):
        # Create standard squashfs payload
        squash_file = DIST_DIR / f"weget-{VERSION}.squashfs"
        if squash_file.exists():
            squash_file.unlink()
        run_cmd(["mksquashfs", str(appdir), str(squash_file), "-comp", "zstd", "-root-owned", "-noappend"])
        log_ok(f"Created AppDir SquashFS bundle: {squash_file}")
    else:
        log("AppDir assembled ready for bundling at: " + str(appdir))


def build_flatpak():
    log("Generating Flatpak manifest and configuration...")
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    manifest_file = DIST_DIR / "org.weget.Weget.yml"
    manifest_content = f"""app-id: org.weget.Weget
runtime: org.gnome.Platform
runtime-version: '46'
sdk: org.gnome.Sdk
command: weget
finish-args:
  - --share=ipc
  - --socket=x11
  - --socket=wayland
  - --share=network
  - --talk-name=org.mpris.MediaPlayer2.*
  - --filesystem=home:ro
  - --filesystem=xdg-config/conky:create
  - --filesystem=xdg-cache/weget:create

modules:
  - name: weget
    buildsystem: simple
    build-commands:
      - install -D -m 755 weget /app/bin/weget
      - install -D -m 755 engine/conky/bin/conky /app/lib/weget/engine/bin/conky
      - install -d /app/lib/weget/engine/lib
      - install -m 644 engine/conky/lib/*.so /app/lib/weget/engine/lib/
      - install -d /app/share/weget
      - cp -a engine/macwidget.lua engine/conky.conf engine/settings engine/helpers assets /app/share/weget/
      - install -D -m 644 package/weget.desktop /app/share/applications/org.weget.Weget.desktop
      - sed -i 's|^Icon=.*|Icon=org.weget.Weget|' /app/share/applications/org.weget.Weget.desktop
      - sed -i 's|^StartupWMClass=.*|StartupWMClass=org.weget.Weget|' /app/share/applications/org.weget.Weget.desktop
      - for s in 16 32 48 64 128 256 512; do install -D -m 644 assets/icons/hicolor/${{s}}x${{s}}/apps/weget.png /app/share/icons/hicolor/${{s}}x${{s}}/apps/org.weget.Weget.png; done
    sources:
      - type: dir
        path: ..
"""
    manifest_file.write_text(manifest_content)

    metainfo_file = DIST_DIR / "org.weget.Weget.metainfo.xml"
    metainfo_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>org.weget.Weget</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <name>Weget</name>
  <summary>Modern macOS-style interactive desktop widgets for Linux</summary>
  <description>
    <p>
      Weget delivers modular desktop widgets on Linux,
      with full hardware rings, network charts, weather forecasts, quotes, and media player controls.
    </p>
  </description>
  <launchable type="desktop-id">org.weget.Weget.desktop</launchable>
  <releases>
    <release version="{VERSION}" date="2026-10-15"/>
  </releases>
</component>
"""
    metainfo_file.write_text(metainfo_content)
    log_ok(f"Created Flatpak Manifest: {manifest_file}")
    log_ok(f"Created AppStream Metainfo: {metainfo_file}")


def build_portable_tarball():
    log("Building portable tarball...")
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    if not (ROOT_DIR / "weget").exists():
        build_binary()

    tar_output = DIST_DIR / f"{PKG_NAME}-{VERSION}-x86_64.tar.gz"
    top = f"{PKG_NAME}-{VERSION}"

    with tarfile.open(tar_output, "w:gz") as tar:
        for rel in ["weget", "engine", "assets", "README.md"]:
            src = ROOT_DIR / rel
            if src.exists():
                tar.add(str(src), arcname=f"{top}/{rel}")

    os.chmod(tar_output, 0o644)
    log_ok(f"Created portable tarball: {tar_output} ({tar_output.stat().st_size // 1024} KB)")


def build_flatpak_bundle():
    log("Building Flatpak bundle (.flatpak)...")
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    if not shutil.which("flatpak-builder"):
        log("flatpak-builder not found; skipping .flatpak bundle (manifest still generated).")
        return

    if not (ROOT_DIR / "weget").exists():
        build_binary()

    manifest_file = DIST_DIR / "org.weget.Weget.yml"
    if not manifest_file.exists():
        build_flatpak()

    output_flatpak = DIST_DIR / f"Weget-{VERSION}.flatpak"

    # Build/repo dirs live outside the source tree so flatpak-builder does not
    # try to copy its own output into the source directory.
    with tempfile.TemporaryDirectory(prefix="weget_flatpak_") as tmp_dir:
        repo_dir = Path(tmp_dir) / "repo"
        build_dir = Path(tmp_dir) / "build"
        run_cmd([
            "flatpak-builder", "--force-clean",
            "--repo", str(repo_dir),
            str(build_dir), str(manifest_file),
        ])
        run_cmd([
            "flatpak", "build-bundle",
            str(repo_dir), str(output_flatpak), "org.weget.Weget",
        ])

    log_ok(f"Created Flatpak bundle: {output_flatpak} ({output_flatpak.stat().st_size // 1024} KB)")


def safe_copy(src: Path, dst: Path):
    if src.exists() and (not dst.exists() or src.resolve() != dst.resolve()):
        dst_parent = dst.parent
        dst_parent.mkdir(parents=True, exist_ok=True)
        tmp_dst = dst.with_name(f".{dst.name}.tmp")
        shutil.copy2(src, tmp_dst)
        os.replace(tmp_dst, dst)


def install_local():
    log("Installing Weget locally into ~/.local...")
    home = Path(os.environ["HOME"])
    local_bin = home / ".local" / "bin"
    local_share = home / ".local" / "share" / "weget"
    local_apps = home / ".local" / "share" / "applications"
    local_icons = home / ".local" / "share" / "icons" / "hicolor" / "256x256" / "apps"
    config_dir = home / ".config" / "conky" / "macwidget"

    for d in [local_bin, local_share, local_apps, local_icons, config_dir]:
        d.mkdir(parents=True, exist_ok=True)

    if not (ROOT_DIR / "weget").exists():
        build_binary()

    # 1. Binary
    safe_copy(ROOT_DIR / "weget", local_bin / "weget")
    os.chmod(local_bin / "weget", 0o755)

    # 2. Bundled Conky engine into ~/.local/share/weget/engine
    local_engine = local_share / "engine" / "conky"
    (local_engine / "bin").mkdir(parents=True, exist_ok=True)
    (local_engine / "lib").mkdir(parents=True, exist_ok=True)
    if (ENGINE_DIR / "bin" / "conky").exists():
        safe_copy(ENGINE_DIR / "bin" / "conky", local_engine / "bin" / "conky")
        os.chmod(local_engine / "bin" / "conky", 0o755)
    for so in (ENGINE_DIR / "lib").glob("*.so"):
        safe_copy(so, local_engine / "lib" / so.name)

    # 3. Assets & config
    safe_copy(RUNTIME_DIR / "macwidget.lua", config_dir / "macwidget.lua")
    safe_copy(RUNTIME_DIR / "conky.conf", config_dir / "conky.conf")
    safe_copy(RUNTIME_DIR / "macwidget.lua", local_share / "macwidget.lua")
    safe_copy(RUNTIME_DIR / "conky.conf", local_share / "conky.conf")

    if (RUNTIME_DIR / "settings").exists() and (RUNTIME_DIR / "settings").resolve() != (config_dir / "settings").resolve():
        shutil.copytree(RUNTIME_DIR / "settings", config_dir / "settings", dirs_exist_ok=True)

    if (RUNTIME_DIR / "helpers").exists():
        for h in (RUNTIME_DIR / "helpers").glob("*"):
            safe_copy(h, config_dir / "helpers" / h.name)
            os.chmod(config_dir / "helpers" / h.name, 0o755)
            safe_copy(h, local_share / "helpers" / h.name)
            os.chmod(local_share / "helpers" / h.name, 0o755)

    # 4. Multi-Resolution Icons & Desktop launcher
    sizes = [16, 32, 48, 64, 128, 256, 512]
    for s in sizes:
        local_size_dir = home / ".local" / "share" / "icons" / "hicolor" / f"{s}x{s}" / "apps"
        local_size_dir.mkdir(parents=True, exist_ok=True)
        src_icon = ROOT_DIR / "assets" / "icons" / "hicolor" / f"{s}x{s}" / "apps" / "weget.png"
        if src_icon.exists():
            safe_copy(src_icon, local_size_dir / "weget.png")

    local_pixmaps = home / ".local" / "share" / "pixmaps"
    local_pixmaps.mkdir(parents=True, exist_ok=True)
    pixmap_src = ROOT_DIR / "assets" / "icons" / "pixmaps" / "weget.png"
    if pixmap_src.exists():
        safe_copy(pixmap_src, local_pixmaps / "weget.png")

    desktop_content = f"""[Desktop Entry]
Name=Weget
GenericName=Desktop Widget System
Comment=Modern macOS-style interactive desktop widgets for Linux
Exec={local_bin / 'weget'}
Icon=weget
Terminal=false
Type=Application
Categories=Utility;DesktopSettings;GTK;
StartupNotify=true
StartupWMClass=weget
"""
    (local_apps / "weget.desktop").write_text(desktop_content)

    # Refresh icon cache if gtk-update-icon-cache is present
    if shutil.which("gtk-update-icon-cache"):
        subprocess.run(["gtk-update-icon-cache", "-q", "-t", "-f", str(home / ".local" / "share" / "icons" / "hicolor")], check=False)
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", "-q", str(local_apps)], check=False)

    log_ok("Successfully installed Weget to ~/.local/bin/weget")


def uninstall_local():
    log("Uninstalling Weget from ~/.local...")
    home = Path(os.environ["HOME"])
    local_bin = home / ".local" / "bin" / "weget"
    local_share = home / ".local" / "share" / "weget"
    local_desktop = home / ".local" / "share" / "applications" / "weget.desktop"
    local_icon = home / ".local" / "share" / "icons" / "hicolor" / "256x256" / "apps" / "weget.png"

    # Stop daemon first
    if local_bin.exists():
        subprocess.run([str(local_bin), "stop"], check=False)

    for p in [local_bin, local_desktop, local_icon]:
        if p.exists():
            p.unlink()
    autostart_p = home / ".config" / "autostart" / "weget.desktop"
    if autostart_p.exists():
        autostart_p.unlink()
    if local_share.exists():
        shutil.rmtree(local_share)
    log_ok("Successfully uninstalled Weget from ~/.local")


def clean():
    log("Cleaning build artifacts...")
    for p in [ROOT_DIR / "weget", ROOT_DIR / "app" / "weget"]:
        if p.exists():
            p.unlink()
    appdir = DIST_DIR / "AppDir"
    if appdir.exists():
        shutil.rmtree(appdir)
    log_ok("Cleaned.")


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "build"

    if target in ["build", "all"]:
        build_binary()
    elif target in ["help", "--help", "-h"]:
        print("""Weget — Modern Desktop Widget Ecosystem
Available targets:
  make run        - Build and launch the Weget UI manager
  make build      - Compile the Weget binary
  make start      - Start desktop widgets natively
  make stop       - Stop desktop widgets
  make restart    - Restart desktop widgets
  make status     - Check widget daemon status
  make autostart  - Enable, disable, or check login autostart
  make install    - Install to ~/.local (no root required)
  make uninstall  - Remove from ~/.local
  make deb        - Export Debian package (.deb)
  make rpm        - Export RPM spec and archive (.rpm)
  make appimage   - Export universal AppImage (.AppImage)
  make flatpak    - Export Flatpak manifest & metainfo
  make flatpak-bundle - Build the .flatpak bundle (needs flatpak-builder)
  make tarball    - Build portable binary tarball (.tar.gz)
  make packages   - Build all package formats
  make clean      - Clean build artifacts""")
    elif target == "run":
        if not (ROOT_DIR / "weget").exists():
            build_binary()
        os.execv(str(ROOT_DIR / "weget"), [str(ROOT_DIR / "weget")])
    elif target in ["start", "stop", "restart", "status", "autostart"]:
        if not (ROOT_DIR / "weget").exists():
            build_binary()
        args = sys.argv[1:]
        run_cmd([str(ROOT_DIR / "weget")] + args)
    elif target == "deb":
        build_deb()
    elif target == "rpm":
        build_rpm()
    elif target == "appimage":
        build_appimage()
    elif target == "flatpak":
        build_flatpak()
    elif target == "flatpak-bundle":
        build_flatpak_bundle()
    elif target == "tarball":
        build_portable_tarball()
    elif target == "packages":
        build_binary()
        build_deb()
        build_rpm()
        build_appimage()
        build_flatpak()
        build_portable_tarball()
        build_flatpak_bundle()
    elif target == "install":
        install_local()
    elif target == "uninstall":
        uninstall_local()
    elif target == "clean":
        clean()
    else:
        log_err(f"Unknown target: {target}")
        print("Available targets: build, run, start, stop, restart, status, deb, rpm, appimage, flatpak, flatpak-bundle, tarball, packages, install, uninstall, clean")
        sys.exit(1)


if __name__ == "__main__":
    main()
