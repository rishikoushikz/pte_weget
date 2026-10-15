#!/usr/bin/env python3
"""
Weget — Native Desktop Window Launcher using WebKit2GTK
Provides a dedicated standalone desktop application window for the Weget Go engine.
"""

import sys
import os
import signal

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("WebKit2", "4.1")
    from gi.repository import Gtk, WebKit2, GLib
except Exception as e:
    sys.stderr.write(f"WebKit2GTK initialization error: {e}\n")
    sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: webview.py <url> [title] [icon_path] [width] [height]")
        sys.exit(1)

    url = sys.argv[1]
    title = sys.argv[2] if len(sys.argv) > 2 else "Weget — Modern Desktop Widgets"
    icon_path = sys.argv[3] if len(sys.argv) > 3 else ""
    width = int(sys.argv[4]) if len(sys.argv) > 4 else 820
    height = int(sys.argv[5]) if len(sys.argv) > 5 else 680

    # Ensure application identity and WM_CLASS / Wayland app_id are set
    # This links the running window to weget.desktop on dock, taskbar, and alt-tab
    app_id = os.environ.get("FLATPAK_ID", "weget")
    GLib.set_prgname(app_id)
    GLib.set_application_name("Weget")

    win = Gtk.Window(title=title)
    win.set_default_size(width, height)
    win.set_position(Gtk.WindowPosition.CENTER)

    # Prefer dark theme for window decorations and controls
    gtk_settings = Gtk.Settings.get_default()
    if gtk_settings:
        gtk_settings.set_property("gtk-application-prefer-dark-theme", True)

    icon_loaded = False
    if icon_path and os.path.exists(icon_path):
        try:
            win.set_icon_from_file(icon_path)
            Gtk.Window.set_default_icon_from_file(icon_path)
            icon_loaded = True
        except Exception:
            pass

    if not icon_loaded:
        for candidate in [app_id, "weget", "org.weget.Weget"]:
            try:
                win.set_icon_name(candidate)
                Gtk.Window.set_default_icon_name(candidate)
                break
            except Exception:
                continue

    # Configure WebKit settings
    settings = WebKit2.Settings()
    settings.set_enable_javascript(True)
    settings.set_enable_developer_extras(False)

    view = WebKit2.WebView.new_with_settings(settings)
    view.load_uri(url)
    win.add(view)

    # Clean shutdown on window close
    win.connect("destroy", Gtk.main_quit)

    # Enable Ctrl+C signal handling inside GTK loop
    signal.signal(signal.SIGINT, lambda *_: Gtk.main_quit())
    GLib.timeout_add(200, lambda: True)

    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
