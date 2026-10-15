#!/usr/bin/env python3
"""
Weget Native MPRIS2 Media Controller
Zero external dependencies (pure Python D-Bus / gdbus).
Detects Spotify, Waterfox, Firefox, Chrome, Chromium, Brave, VLC, MPV, etc.
"""
import sys
import os
import json
import subprocess

def get_session_mpris_players_dbus():
    try:
        import dbus
        bus = dbus.SessionBus()
        return [str(n) for n in bus.list_names() if str(n).startswith("org.mpris.MediaPlayer2.")]
    except Exception:
        return []

def get_session_mpris_players_gdbus():
    try:
        out = subprocess.check_output(
            ["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus",
             "--object-path", "/org/freedesktop/DBus",
             "--method", "org.freedesktop.DBus.ListNames"],
            stderr=subprocess.DEVNULL, text=True, timeout=1
        )
        import re
        return re.findall(r"'org\.mpris\.MediaPlayer2\.[^']+'", out)
    except Exception:
        return []

def get_players():
    players = get_session_mpris_players_dbus()
    if not players:
        players = get_session_mpris_players_gdbus()
    return players

def query_media_dbus():
    import dbus
    bus = dbus.SessionBus()
    players = [str(n) for n in bus.list_names() if str(n).startswith("org.mpris.MediaPlayer2.")]
    if not players:
        return None

    active = None
    for p_name in players:
        try:
            p_obj = bus.get_object(p_name, "/org/mpris/MediaPlayer2")
            props = dbus.Interface(p_obj, "org.freedesktop.DBus.Properties")
            st = str(props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
            if st == "Playing":
                active = (p_name, p_obj, props, st)
                break
            elif not active and st == "Paused":
                active = (p_name, p_obj, props, st)
        except Exception:
            continue

    if not active:
        try:
            p_obj = bus.get_object(players[0], "/org/mpris/MediaPlayer2")
            props = dbus.Interface(p_obj, "org.freedesktop.DBus.Properties")
            st = str(props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
            active = (players[0], p_obj, props, st)
        except Exception:
            return None

    p_name, p_obj, props, status = active
    is_playing = (status == "Playing")

    try:
        meta = props.Get("org.mpris.MediaPlayer2.Player", "Metadata")
    except Exception:
        meta = {}

    title = str(meta.get("xesam:title", "Unknown Track")).strip()
    if not title:
        title = "Unknown Track"

    artist = "Weget Audio Engine"
    raw_artists = meta.get("xesam:artist")
    if raw_artists:
        if isinstance(raw_artists, (list, tuple, dbus.Array)) and len(raw_artists) > 0:
            artist = str(raw_artists[0]).strip()
        else:
            artist = str(raw_artists).strip()
    elif meta.get("xesam:albumArtist"):
        artist = str(meta.get("xesam:albumArtist")).strip()

    # Track length (microseconds)
    length_us = 0
    try:
        length_us = int(meta.get("mpris:length", 0))
    except Exception:
        pass
    len_sec = length_us / 1000000.0

    # Track position (microseconds)
    pos_sec = 0.0
    try:
        pos_us = int(props.Get("org.mpris.MediaPlayer2.Player", "Position"))
        pos_sec = pos_us / 1000000.0
    except Exception:
        pass

    prog = 0.0
    time_str = "--:--"
    if len_sec > 0:
        prog = min(1.0, max(0.0, pos_sec / len_sec))
        pm, ps = int(pos_sec // 60), int(pos_sec % 60)
        lm, ls = int(len_sec // 60), int(len_sec % 60)
        time_str = f"{pm:02d}:{ps:02d} / {lm:02d}:{ls:02d}"

    return {
        "status": status,
        "is_playing": is_playing,
        "title": title[:30],
        "artist": artist[:26],
        "progress": round(prog, 3),
        "time": time_str,
        "player": p_name
    }

def send_control_dbus(action):
    import dbus
    bus = dbus.SessionBus()
    players = [str(n) for n in bus.list_names() if str(n).startswith("org.mpris.MediaPlayer2.")]
    if not players:
        return False

    # Target playing player, or first paused
    target = players[0]
    for p_name in players:
        try:
            p_obj = bus.get_object(p_name, "/org/mpris/MediaPlayer2")
            props = dbus.Interface(p_obj, "org.freedesktop.DBus.Properties")
            if str(props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus")) == "Playing":
                target = p_name
                break
        except Exception:
            continue

    try:
        p_obj = bus.get_object(target, "/org/mpris/MediaPlayer2")
        player_iface = dbus.Interface(p_obj, "org.mpris.MediaPlayer2.Player")
        if action in ("play-pause", "toggle"):
            player_iface.PlayPause()
        elif action == "play":
            player_iface.Play()
        elif action == "pause":
            player_iface.Pause()
        elif action == "next":
            player_iface.Next()
        elif action in ("prev", "previous"):
            player_iface.Previous()
        return True
    except Exception:
        return False

def default_idle():
    return {
        "status": "󰓛 Idle",
        "is_playing": False,
        "title": "No Media Playing",
        "artist": "Weget Audio Engine",
        "progress": 0.0,
        "time": "--:--"
    }

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "json"

    if action in ("play-pause", "toggle", "play", "pause", "next", "prev", "previous"):
        if not send_control_dbus(action):
            # Fallback to playerctl if installed
            if os.system(f"which playerctl >/dev/null 2>&1") == 0:
                os.system(f"playerctl {action} 2>/dev/null")
        sys.exit(0)

    # Query info
    info = None
    try:
        info = query_media_dbus()
    except Exception:
        pass

    if not info:
        info = default_idle()

    status_str = "󰓛 Idle"
    if info.get("is_playing"):
        status_str = "󰐊 Playing"
    elif info.get("status") == "Paused":
        status_str = "󰏤 Paused"

    if action == "json":
        print(json.dumps({
            "status": status_str,
            "is_playing": info.get("is_playing", False),
            "title": info.get("title", "No Media Playing"),
            "artist": info.get("artist", "Weget Audio Engine"),
            "progress": info.get("progress", 0.0),
            "time": info.get("time", "--:--")
        }))
    elif action == "status":
        print(status_str)
    elif action == "title":
        print(info.get("title", "No Media Playing"))
    elif action == "artist":
        print(info.get("artist", "Weget Audio Engine"))
    elif action == "progress":
        print(f"{info.get('progress', 0.0):.3f}")
    elif action == "time":
        print(info.get("time", "--:--"))
    else:
        print(info.get("status", "Idle"))

if __name__ == "__main__":
    main()
