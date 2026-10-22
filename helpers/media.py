#!/usr/bin/env python3
"""
Weget Native MPRIS2 Multi-Player Media Controller
Zero external dependencies (pure Python D-Bus / gdbus).
Detects Spotify, Waterfox, Firefox, Chrome, Chromium, Brave, VLC, MPV, etc.
Supports multi-player carousel navigation, persistent selection, and targeted controls.
"""
import sys
import os
import json
import re
import subprocess
import time

SELECTED_PLAYER_FILE = "/tmp/weget_media_selected"
TELEMETRY_CACHE_FILE = "/tmp/weget_telemetry.json"

PLAYER_METADATA_MAP = {
    "spotify": ("Spotify", "󰓇"),
    "brave": ("Brave", "󰖟"),
    "firefox": ("Firefox", "󰈹"),
    "waterfox": ("Waterfox", "󰈹"),
    "chrome": ("Chrome", "󰊯"),
    "chromium": ("Chromium", "󰊯"),
    "vlc": ("VLC", "󰕼"),
    "mpv": ("MPV", "󰐊"),
    "amberol": ("Amberol", ""),
    "rhythmbox": ("Rhythmbox", ""),
    "audacious": ("Audacious", ""),
    "elisa": ("Elisa", ""),
    "clementine": ("Clementine", ""),
    "apple_music": ("Apple Music", "󰓇"),
    "tidal": ("TIDAL", "󰓇"),
}

def identify_player(bus_name):
    clean = bus_name.replace("org.mpris.MediaPlayer2.", "")
    lower = clean.lower()
    for key, (name, icon) in PLAYER_METADATA_MAP.items():
        if key in lower:
            return name, icon
    # Extract base name before any instance suffix
    base = clean.split(".")[0].split("_")[0]
    return base.capitalize(), "󰝚"

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
            stderr=subprocess.DEVNULL, text=True, timeout=1.5
        )
        return [p.strip("'") for p in re.findall(r"'org\.mpris\.MediaPlayer2\.[^']+'", out)]
    except Exception:
        return []

def get_players():
    players = get_session_mpris_players_dbus()
    if not players:
        players = get_session_mpris_players_gdbus()
    return players

def parse_player_data(bus, p_name):
    import dbus
    try:
        p_obj = bus.get_object(p_name, "/org/mpris/MediaPlayer2")
        props = dbus.Interface(p_obj, "org.freedesktop.DBus.Properties")
        st = str(props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
    except Exception:
        return None

    is_playing = (st == "Playing")

    try:
        meta = props.Get("org.mpris.MediaPlayer2.Player", "Metadata")
    except Exception:
        meta = {}

    title = str(meta.get("xesam:title", "")).strip()
    artist = ""
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

    p_name_clean, p_icon = identify_player(p_name)

    # Detect if track is valid or empty
    has_media = bool(title or artist or is_playing or st == "Paused")
    if not title:
        title = "No Track Title" if has_media else "Unknown Track"
    if not artist:
        artist = p_name_clean

    # Clean emojis (SMP plane) which Cairo toy font cannot render
    title = re.sub(r'[\U00010000-\U0010ffff]', '', title).strip()
    artist = re.sub(r'[\U00010000-\U0010ffff]', '', artist).strip()

    if len(title) > 27:
        display_title = title[:26].rstrip() + "…"
    else:
        display_title = title

    if len(artist) > 26:
        display_artist = artist[:25].rstrip() + "…"
    else:
        display_artist = artist

    return {
        "id": p_name,
        "name": p_name_clean,
        "icon": p_icon,
        "status": st,
        "is_playing": is_playing,
        "title": display_title,
        "artist": display_artist,
        "progress": round(prog, 3),
        "time": time_str,
        "has_media": has_media
    }

def get_all_active_players_dbus():
    try:
        import dbus
        bus = dbus.SessionBus()
    except Exception:
        return []

    player_names = [str(n) for n in bus.list_names() if str(n).startswith("org.mpris.MediaPlayer2.")]
    if not player_names:
        return []

    active_list = []
    dead_list = []

    for p_name in player_names:
        info = parse_player_data(bus, p_name)
        if not info:
            continue
        # Check if actually playing or paused with title
        if info["is_playing"] or (info["status"] == "Paused" and info["title"] not in ("Unknown Track", "No Track Title")):
            active_list.append(info)
        elif info["has_media"] and info["status"] != "Stopped":
            active_list.append(info)
        else:
            dead_list.append(info)

    # If nothing actively playing/paused, include available players with metadata
    if not active_list:
        for d in dead_list:
            if d["title"] != "Unknown Track":
                active_list.append(d)

    # Sort: Playing players first, then Paused, then others
    def sort_key(p):
        if p["is_playing"]:
            return 0
        if p["status"] == "Paused":
            return 1
        return 2

    active_list.sort(key=sort_key)
    return active_list

def get_selected_player_id():
    try:
        if os.path.exists(SELECTED_PLAYER_FILE):
            with open(SELECTED_PLAYER_FILE, "r") as f:
                return f.read().strip()
    except Exception:
        pass
    return ""

def set_selected_player_id(player_id):
    try:
        with open(SELECTED_PLAYER_FILE, "w") as f:
            f.write(player_id.strip())
    except Exception:
        pass

def cycle_player(direction=1):
    players = get_all_active_players_dbus()
    if not players:
        return None
    if len(players) == 1:
        set_selected_player_id(players[0]["id"])
        return players[0]

    current_id = get_selected_player_id()
    cur_idx = 0
    for idx, p in enumerate(players):
        if p["id"] == current_id:
            cur_idx = idx
            break

    new_idx = (cur_idx + direction) % len(players)
    chosen = players[new_idx]
    set_selected_player_id(chosen["id"])
    sync_telemetry_quick(chosen, players, new_idx)
    return chosen

def sync_telemetry_quick(selected, all_players, current_idx):
    """Write immediately to /tmp/weget_telemetry.json and ~/.cache/weget/telemetry.json for zero-latency UI update."""
    try:
        current_data = {}
        if os.path.exists(TELEMETRY_CACHE_FILE):
            try:
                with open(TELEMETRY_CACHE_FILE, "r") as f:
                    current_data = json.load(f)
            except Exception:
                current_data = {}

        status_str = "󰓛 Idle"
        if selected.get("is_playing"):
            status_str = "󰐊 Playing"
        elif selected.get("status") == "Paused":
            status_str = "󰏤 Paused"

        current_data["media"] = {
            "status": status_str,
            "is_playing": selected.get("is_playing", False),
            "title": selected.get("title", "No Media Playing"),
            "artist": selected.get("artist", "Weget Audio Engine"),
            "progress": selected.get("progress", 0.0),
            "time": selected.get("time", "--:--"),
            "player": selected.get("id", ""),
            "player_name": selected.get("name", "Audio"),
            "player_icon": selected.get("icon", "󰝚"),
            "player_index": current_idx + 1 if all_players else 1,
            "total_players": len(all_players)
        }
        current_data["updated"] = int(time.time())

        paths = [
            TELEMETRY_CACHE_FILE,
            os.path.expanduser("~/.cache/weget/telemetry.json")
        ]
        for p in paths:
            try:
                os.makedirs(os.path.dirname(p), exist_ok=True)
                tmp = p + ".tmp"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(current_data, f, indent=2, ensure_ascii=False)
                os.replace(tmp, p)
            except Exception:
                pass
    except Exception:
        pass

def query_media():
    players = get_all_active_players_dbus()
    if not players:
        return default_idle(), [], 0

    selected_id = get_selected_player_id()
    selected_idx = 0

    # Look for saved player
    found = False
    for idx, p in enumerate(players):
        if p["id"] == selected_id:
            selected_idx = idx
            found = True
            break

    if not found:
        # Default to first playing or first available
        selected_idx = 0
        set_selected_player_id(players[0]["id"])

    chosen = players[selected_idx]
    return chosen, players, selected_idx

def send_control_dbus(action, target_id=None):
    import dbus
    bus = dbus.SessionBus()

    # Determine target
    if not target_id:
        target_id = get_selected_player_id()

    players = [str(n) for n in bus.list_names() if str(n).startswith("org.mpris.MediaPlayer2.")]
    if not players:
        return False

    if target_id not in players:
        # Find active playing or paused player
        target_id = None
        for p_name in players:
            try:
                p_obj = bus.get_object(p_name, "/org/mpris/MediaPlayer2")
                props = dbus.Interface(p_obj, "org.freedesktop.DBus.Properties")
                st = str(props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
                if st == "Playing":
                    target_id = p_name
                    break
                elif not target_id and st == "Paused":
                    target_id = p_name
            except Exception:
                continue

        if not target_id:
            target_id = players[0]

    try:
        p_obj = bus.get_object(target_id, "/org/mpris/MediaPlayer2")
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

        # Update telemetry quickly
        info = parse_player_data(bus, target_id)
        if info:
            if action in ("play-pause", "toggle"):
                info["is_playing"] = not info["is_playing"]
                info["status"] = "Playing" if info["is_playing"] else "Paused"
            elif action == "play":
                info["is_playing"] = True
                info["status"] = "Playing"
            elif action == "pause":
                info["is_playing"] = False
                info["status"] = "Paused"
            sync_telemetry_quick(info, [info], 0)

        return True
    except Exception:
        return False

def default_idle():
    return {
        "id": "",
        "name": "Weget Audio",
        "icon": "󰓛",
        "status": "󰓛 Idle",
        "is_playing": False,
        "title": "No Media Playing",
        "artist": "Weget Audio Engine",
        "progress": 0.0,
        "time": "--:--",
        "has_media": False
    }

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "json"
    target_arg = sys.argv[2] if len(sys.argv) > 2 else None

    if action == "player-next":
        cycle_player(1)
        sys.exit(0)
    elif action in ("player-prev", "player-previous"):
        cycle_player(-1)
        sys.exit(0)
    elif action == "select" and target_arg:
        set_selected_player_id(target_arg)
        sys.exit(0)

    if action in ("sync", "update"):
        chosen, all_players, chosen_idx = query_media()
        sync_telemetry_quick(chosen, all_players, chosen_idx)
        sys.exit(0)

    if action in ("play-pause", "toggle", "play", "pause", "next", "prev", "previous"):
        if not send_control_dbus(action, target_arg):
            # Fallback to playerctl if installed
            if os.system("which playerctl >/dev/null 2>&1") == 0:
                os.system(f"playerctl {action} 2>/dev/null")
            time.sleep(0.04)
            chosen, all_players, chosen_idx = query_media()
            sync_telemetry_quick(chosen, all_players, chosen_idx)
        sys.exit(0)

    # Query info
    chosen, all_players, chosen_idx = query_media()

    status_str = "󰓛 Idle"
    if chosen.get("is_playing"):
        status_str = "󰐊 Playing"
    elif chosen.get("status") == "Paused":
        status_str = "󰏤 Paused"

    payload = {
        "status": status_str,
        "is_playing": chosen.get("is_playing", False),
        "title": chosen.get("title", "No Media Playing"),
        "artist": chosen.get("artist", "Weget Audio Engine"),
        "progress": chosen.get("progress", 0.0),
        "time": chosen.get("time", "--:--"),
        "player": chosen.get("id", ""),
        "player_name": chosen.get("name", "Audio"),
        "player_icon": chosen.get("icon", "󰝚"),
        "player_index": chosen_idx + 1 if all_players else 1,
        "total_players": len(all_players) if all_players else 0,
        "players": [
            {
                "id": p["id"],
                "name": p["name"],
                "icon": p["icon"],
                "status": p["status"],
                "is_playing": p["is_playing"],
                "title": p["title"],
                "artist": p["artist"]
            }
            for p in all_players
        ]
    }

    if action == "json":
        print(json.dumps(payload, ensure_ascii=False))
    elif action == "status":
        print(status_str)
    elif action == "title":
        print(chosen.get("title", "No Media Playing"))
    elif action == "artist":
        print(chosen.get("artist", "Weget Audio Engine"))
    elif action == "progress":
        print(f"{chosen.get('progress', 0.0):.3f}")
    elif action == "time":
        print(chosen.get("time", "--:--"))
    elif action == "players":
        print(json.dumps(payload["players"], ensure_ascii=False))
    else:
        print(chosen.get("status", "Idle"))

if __name__ == "__main__":
    main()
