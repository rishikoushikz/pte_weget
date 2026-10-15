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

def generate_blur():
    wp = get_wallpaper_path()
    if not wp or not os.path.exists(wp):
        return False

    sw, sh = get_screen_resolution()
    geom = get_window_geometry()
    if geom:
        win_x, win_y, win_w, win_h = geom
    else:
        win_w, win_h = 350, 820
        win_x = sw - win_w - 26
        win_y = 54

    try:
        img = Image.open(wp).convert('RGB')
        img_scaled = img.resize((sw, sh), Image.Resampling.BILINEAR)

        x1 = max(0, min(win_x, sw - 10))
        y1 = max(0, min(win_y, sh - 10))
        x2 = min(sw, max(x1 + 10, win_x + win_w))
        y2 = min(sh, max(y1 + 10, win_y + win_h))
        crop = img_scaled.crop((x1, y1, x2, y2))

        # Downscale for smooth Dual-Kawase / Gaussian blur
        radius = get_blur_radius()
        small_radius = max(2, radius // 4)
        small = crop.resize((max(1, 350 // 4), max(1, 820 // 4)), Image.Resampling.BILINEAR)
        blurred_small = small.filter(ImageFilter.GaussianBlur(radius=small_radius))
        blurred = blurred_small.resize((350, 820), Image.Resampling.BILINEAR)

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
