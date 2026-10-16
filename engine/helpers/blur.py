#!/usr/bin/env python3
import os
import subprocess
import sys
from PIL import Image, ImageFilter

def get_wallpaper_path():
    try:
        out = subprocess.check_output(
            ['gsettings', 'get', 'org.gnome.desktop.background', 'picture-uri-dark'],
            stderr=subprocess.DEVNULL
        ).decode().strip().strip("'")
        if out.startswith('file://'):
            out = out[7:]
        if os.path.exists(out):
            return out
    except Exception:
        pass

    try:
        out = subprocess.check_output(
            ['gsettings', 'get', 'org.gnome.desktop.background', 'picture-uri'],
            stderr=subprocess.DEVNULL
        ).decode().strip().strip("'")
        if out.startswith('file://'):
            out = out[7:]
        if os.path.exists(out):
            return out
    except Exception:
        pass

    fallbacks = [
        os.path.expanduser('~/.config/background'),
        '/usr/share/backgrounds/ubuntu-wallpaper-d.png',
        '/usr/share/backgrounds/warty-final-ubuntu.png'
    ]
    for fb in fallbacks:
        if os.path.exists(fb):
            return fb
    return ""

def get_window_geometry():
    try:
        out = subprocess.check_output(['xwininfo', '-name', 'weget_macwidget'], stderr=subprocess.DEVNULL).decode()
        x, y, w, h = 0, 0, 0, 0
        for line in out.splitlines():
            line = line.strip()
            if line.startswith('Absolute upper-left X:'):
                x = int(line.split(':')[1].strip())
            elif line.startswith('Absolute upper-left Y:'):
                y = int(line.split(':')[1].strip())
            elif line.startswith('Width:'):
                w = int(line.split(':')[1].strip())
            elif line.startswith('Height:'):
                h = int(line.split(':')[1].strip())
        if w > 0 and h > 0:
            return x, y, w, h
    except Exception:
        pass
    return None

def get_screen_resolution():
    try:
        res = subprocess.check_output(['xrandr'], stderr=subprocess.DEVNULL).decode()
        for line in res.splitlines():
            if (' connected primary' in line) or (' connected' in line and '+' in line):
                parts = line.split()
                for p in parts:
                    if 'x' in p and '+' in p:
                        dims = p.split('+')[0]
                        sw, sh = dims.split('x')
                        return int(sw), int(sh)
    except Exception:
        pass
    return 1920, 1080

def get_blur_radius():
    settings_file = os.path.expanduser('~/.config/conky/macwidget/settings/settings.json')
    try:
        import json
        if os.path.exists(settings_file):
            with open(settings_file, 'r') as f:
                d = json.load(f)
                r = int(d.get('blur_radius', 30))
                if r > 0:
                    return r
    except Exception:
        pass
    return 30

def get_settings_geometry(sw, sh):
    settings_file = os.path.expanduser('~/.config/conky/macwidget/settings/settings.json')
    scale = 1.0
    row_count = 4
    pos = 'top_right'
    gx = 26
    gy = 54
    try:
        import json
        if os.path.exists(settings_file):
            with open(settings_file, 'r') as f:
                d = json.load(f)
                scale = float(d.get('scale', 1.0))
                rows = d.get('row_order', [])
                if rows and isinstance(rows, list):
                    row_count = len(rows)
                pos = d.get('position', 'top_right')
                gx = int(d.get('gap_x', 26))
                gy = int(d.get('gap_y', 54))
    except Exception:
        pass

    w = int(350 * scale)
    h = int((row_count * 155 + 10) * scale)
    x = sw - w - gx
    y = gy
    if 'left' in pos:
        x = gx
    elif 'middle' in pos and 'top' not in pos and 'bottom' not in pos:
        x = (sw - w) // 2
    if 'top' in pos:
        y = 34 + gy
    elif 'bottom' in pos:
        y = sh - h - gy
    elif 'middle' in pos and ('left' in pos or 'right' in pos or pos == 'middle_middle'):
        y = (sh - h) // 2
    return max(0, x), max(0, y), max(100, w), max(100, h)

def generate_blur():
    wp = get_wallpaper_path()
    if not wp or not os.path.exists(wp):
        return False

    sw, sh = get_screen_resolution()
    geom = get_window_geometry()
    if geom:
        win_x, win_y, win_w, win_h = geom
    else:
        win_x, win_y, win_w, win_h = get_settings_geometry(sw, sh)

    target_w = max(100, win_w)
    target_h = max(100, win_h)

    try:
        img = Image.open(wp).convert('RGB')
        img_scaled = img.resize((sw, sh), Image.Resampling.BILINEAR)

        x1 = max(0, min(win_x, sw - 10))
        y1 = max(0, min(win_y, sh - 10))
        x2 = min(sw, max(x1 + 10, win_x + target_w))
        y2 = min(sh, max(y1 + 10, win_y + target_h))
        crop = img_scaled.crop((x1, y1, x2, y2))

        # Downscale for smooth Dual-Kawase / Gaussian blur
        radius = get_blur_radius()
        small_radius = max(2, radius // 4)
        small_w = max(1, target_w // 4)
        small_h = max(1, target_h // 4)
        small = crop.resize((small_w, small_h), Image.Resampling.BILINEAR)
        blurred_small = small.filter(ImageFilter.GaussianBlur(radius=small_radius))
        blurred = blurred_small.resize((target_w, target_h), Image.Resampling.BILINEAR)

        cache_dir = os.path.expanduser('~/.cache/weget')
        os.makedirs(cache_dir, exist_ok=True)
        out_path = os.path.join(cache_dir, 'blurred_wallpaper.png')
        tmp_path = out_path + '.tmp'
        blurred.save(tmp_path, format='PNG')
        os.replace(tmp_path, out_path)
        return True
    except Exception as e:
        sys.stderr.write(f"Blur generation failed: {e}\n")
        return False

if __name__ == '__main__':
    generate_blur()
    try:
        from palette import save_wallpaper_palette
        save_wallpaper_palette()
    except Exception:
        pass
