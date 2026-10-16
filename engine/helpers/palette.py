#!/usr/bin/env python3
import colorsys
import json
import os
import subprocess
import sys
from PIL import Image

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

def rgb_to_hex(r, g, b):
    return f"#{int(r):02X}{int(g):02X}{int(b):02X}"

def hex_to_rgb(hex_str):
    h = hex_str.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def extract_wallpaper_palette(wallpaper_path=None):
    if not wallpaper_path:
        wallpaper_path = get_wallpaper_path()

    if not wallpaper_path or not os.path.exists(wallpaper_path):
        # Fallback default dark palette
        return {
            "name": "Wallpaper Adaptive",
            "is_light": False,
            "bg_solid": "#14171E",
            "bg_glass": "#14171E",
            "sub_card_solid": "#0E1117",
            "sub_card_glass": "#FFFFFF",
            "sub_card_glass_a": 0.08,
            "border": "#38BDF8",
            "border_a": 0.18,
            "text_primary": "#F8FAFC",
            "text_muted": "#94A3B8",
            "text_dim": "#475569",
            "red": "#F43F5E",
            "blue": "#38BDF8",
            "green": "#10B981",
            "amber": "#F59E0B",
            "purple": "#A855F7"
        }

    try:
        img = Image.open(wallpaper_path).convert('RGB')
    except Exception:
        return extract_wallpaper_palette("")

    # Fast downscale
    img.thumbnail((160, 160), Image.Resampling.LANCZOS)
    if hasattr(img, 'get_flattened_data'):
        pixels = [tuple(p[:3]) for p in img.get_flattened_data()]
    else:
        pixels = list(img.getdata())
    total_px = len(pixels)

    # 1. Calculate Average Luminance & Dominant Hue
    total_luma = 0
    hue_weights = {}
    for r, g, b in pixels:
        luma = 0.299 * r + 0.587 * g + 0.114 * b
        total_luma += luma
        h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
        if s > 0.18 and v > 0.18:
            h_bucket = int(h * 36) * 10  # 36 buckets (10 deg each)
            hue_weights[h_bucket] = hue_weights.get(h_bucket, 0) + (s * v)

    avg_luma = total_luma / total_px if total_px > 0 else 100
    is_light = avg_luma > 140

    dominant_hue = 215  # default azure/cyan
    if hue_weights:
        dominant_hue = max(hue_weights.items(), key=lambda x: x[1])[0]

    # 2. Extract Vibrant Color Clusters using Adaptive Quantization
    q_img = img.quantize(colors=32, method=Image.Quantize.FASTOCTREE)
    palette_data = q_img.getpalette()
    counts = q_img.histogram()

    scored_colors = []
    for i in range(min(32, len(counts))):
        count = counts[i]
        if count == 0:
            continue
        r = palette_data[i * 3]
        g = palette_data[i * 3 + 1]
        b = palette_data[i * 3 + 2]
        h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
        
        # Vibrancy score: favor distinct saturation and balanced value
        if s < 0.18 or v < 0.18 or (s < 0.22 and v > 0.88):
            continue

        sat_boost = s ** 1.3
        val_boost = 1.0 - abs(v - 0.65)
        score = count * sat_boost * val_boost
        scored_colors.append((score, r, g, b, h, s, v))

    scored_colors.sort(key=lambda x: x[0], reverse=True)

    # 3. Categorize into 5 Signature Accent Roles
    # Hue ranges (0 to 1):
    # Red/Coral: 0.94 - 1.0 or 0.0 - 0.06 (approx 340-20 deg)
    # Amber/Gold: 0.06 - 0.18 (approx 20-65 deg)
    # Green/Emerald: 0.22 - 0.45 (approx 80-165 deg)
    # Blue/Cyan: 0.48 - 0.70 (approx 175-255 deg)
    # Purple/Violet: 0.72 - 0.92 (approx 260-330 deg)
    accents = {
        "red": None,
        "amber": None,
        "green": None,
        "blue": None,
        "purple": None
    }

    def assign_accent(target_h_min, target_h_max):
        for item in scored_colors:
            h = item[4]
            if (target_h_min <= h <= target_h_max) or (target_h_min > target_h_max and (h >= target_h_min or h <= target_h_max)):
                # Boost saturation and lightness for clean dark/light display
                s = min(1.0, item[5] * 1.20 + 0.10)
                v = 0.94 if not is_light else 0.78
                rgb = colorsys.hsv_to_rgb(item[4], s, v)
                return rgb_to_hex(rgb[0] * 255, rgb[1] * 255, rgb[2] * 255)
        return None

    accents["red"]    = assign_accent(0.94, 0.06)
    accents["amber"]  = assign_accent(0.06, 0.18)
    accents["green"]  = assign_accent(0.22, 0.45)
    accents["blue"]   = assign_accent(0.48, 0.70)
    accents["purple"] = assign_accent(0.72, 0.92)

    # Fallback missing accents derived with harmonious natural target hues
    def fallback_accent(hue_deg, sat=0.82, val=0.94):
        rgb = colorsys.hsv_to_rgb((hue_deg % 360) / 360.0, sat, val if not is_light else 0.78)
        return rgb_to_hex(rgb[0] * 255, rgb[1] * 255, rgb[2] * 255)

    if not accents["blue"]:
        accents["blue"] = fallback_accent(dominant_hue if (180 <= dominant_hue <= 250) else 212)
    if not accents["red"]:
        accents["red"] = fallback_accent(354)
    if not accents["amber"]:
        accents["amber"] = fallback_accent(38)
    if not accents["green"]:
        accents["green"] = fallback_accent(142)
    if not accents["purple"]:
        accents["purple"] = fallback_accent(275)

    # 4. Synthesize Harmonious Surfaces & Borders
    dom_h_norm = (dominant_hue % 360) / 360.0

    if not is_light:
        # Deep tinted dark mode surface
        bg_rgb = colorsys.hsv_to_rgb(dom_h_norm, 0.24, 0.10)
        sub_rgb = colorsys.hsv_to_rgb(dom_h_norm, 0.28, 0.07)
        bg_solid = rgb_to_hex(bg_rgb[0] * 255, bg_rgb[1] * 255, bg_rgb[2] * 255)
        sub_solid = rgb_to_hex(sub_rgb[0] * 255, sub_rgb[1] * 255, sub_rgb[2] * 255)
        border_hex = accents["blue"]
        text_primary = "#F8FAFC"
        text_muted = "#94A3B8"
        text_dim = "#475569"
        border_alpha = 0.20
        sub_glass_alpha = 0.14
    else:
        # Crisp tinted light mode surface
        bg_rgb = colorsys.hsv_to_rgb(dom_h_norm, 0.08, 0.98)
        sub_rgb = colorsys.hsv_to_rgb(dom_h_norm, 0.12, 0.92)
        bg_solid = rgb_to_hex(bg_rgb[0] * 255, bg_rgb[1] * 255, bg_rgb[2] * 255)
        sub_solid = rgb_to_hex(sub_rgb[0] * 255, sub_rgb[1] * 255, sub_rgb[2] * 255)
        border_hex = accents["blue"]
        text_primary = "#0F172A"
        text_muted = "#475569"
        text_dim = "#94A3B8"
        border_alpha = 0.14
        sub_glass_alpha = 0.06

    palette = {
        "name": "Wallpaper Adaptive",
        "is_light": is_light,
        "wallpaper_path": wallpaper_path,
        "bg_solid": bg_solid,
        "bg_glass": bg_solid,
        "sub_card_solid": sub_solid,
        "sub_card_glass": accents["blue"],
        "sub_card_glass_a": sub_glass_alpha,
        "border": border_hex,
        "border_a": border_alpha,
        "text_primary": text_primary,
        "text_muted": text_muted,
        "text_dim": text_dim,
        "red": accents["red"],
        "blue": accents["blue"],
        "green": accents["green"],
        "amber": accents["amber"],
        "purple": accents["purple"]
    }

    return palette

def save_wallpaper_palette(palette=None):
    if palette is None:
        palette = extract_wallpaper_palette()

    target_dir = os.path.expanduser("~/.config/conky/macwidget/settings")
    os.makedirs(target_dir, exist_ok=True)
    target_path = os.path.join(target_dir, "wallpaper_palette.json")

    with open(target_path, "w") as f:
        json.dump(palette, f, indent=2)

    return target_path, palette

if __name__ == "__main__":
    wp = sys.argv[1] if len(sys.argv) > 1 else None
    path, pal = save_wallpaper_palette(extract_wallpaper_palette(wp))
    print(json.dumps(pal, indent=2))
