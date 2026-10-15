# Apple Liquid Glass iOS 26 — Weget Design System & Spec

Extracted directly from Figma Community Kit **Apple Liquid Glass iOS 26 (Control Center UI Kit)**:  
`https://www.figma.com/design/Hb5e6eLIVUqvDVaXYMKLOb/...` (Node `#105:23` / `#8001:107`)

---

## 1. The Fundamental Law of Liquid Glass

> **The Apple Empty Layer Rule:**  
> *"Glass goes on an empty background layer BEHIND content — never on the frame holding icons."*

If a frame holding icons or typography has `backdrop-filter` or blur applied directly, its child text and glyphs become optically distorted and soft.  
In Apple Liquid Glass:
- **Layer 1:** Ambient elevated drop shadows (`0 14px 34px rgba(0,0,0,0.28)` + `0 2px 8px rgba(0,0,0,0.16)`)
- **Layer 2:** Base optical tint (`#242424` at ~54% opacity in Regular mode; `rgba(255,255,255,0.08)` in Clear mode)
- **Layer 3:** Inset 315° specular meniscus light reflection (`::before` refractive curve)
- **Layer 4:** Diamond-cut razor-thin 1px perimeter crystalline rim (`rgba(255,255,255,0.22)`)
- **Layer 5 (Top):** Content layer with `position: relative; z-index: 2` — typography, icons, dials, and progress bars remain 100% crisp.

---

## 2. Design Tokens & CSS Variables

```css
:root {
  /* Material Tokens - Regular (Over Desktop Wallpapers & Dark Surfaces) */
  --glass-bg-regular: rgba(36, 36, 36, 0.52);
  --glass-blur-regular: 28px;
  --glass-saturate-regular: 190%;
  --glass-rim-regular: rgba(255, 255, 255, 0.22);
  --glass-top-light-regular: rgba(255, 255, 255, 0.45);
  --glass-shadow-regular: 0 14px 34px rgba(0, 0, 0, 0.28), 0 2px 8px rgba(0, 0, 0, 0.16);

  /* Material Tokens - Clear (Over Photos, Media Artwork, and Vibrant Color) */
  --glass-bg-clear: rgba(255, 255, 255, 0.08);
  --glass-blur-clear: 24px;
  --glass-saturate-clear: 180%;
  --glass-rim-clear: rgba(255, 255, 255, 0.35);
  --glass-top-light-clear: rgba(255, 255, 255, 0.65);
  --glass-shadow-clear: 0 18px 40px rgba(0, 0, 0, 0.22), 0 4px 12px rgba(0, 0, 0, 0.12);

  /* Inner Wells & Tints (Figma fill_87a9adb8) */
  --glass-well-bg: rgba(255, 255, 255, 0.08);
  --glass-well-border: rgba(255, 255, 255, 0.12);

  /* Accents */
  --glass-accent-blue: #0088FF;
  --glass-accent-green: #34C759;
  --glass-accent-orange: #FF9500;
  --glass-accent-red: #FF3B30;
  --glass-accent-purple: #AF52DE;
}
```

---

## 3. Web & CSS Implementation

```css
.liquid-glass {
  position: relative;
  isolation: isolate;
  background: var(--glass-bg-regular);
  backdrop-filter: blur(var(--glass-blur-regular)) saturate(var(--glass-saturate-regular));
  -webkit-backdrop-filter: blur(var(--glass-blur-regular)) saturate(var(--glass-saturate-regular));
  border: 1px solid var(--glass-rim-regular);
  box-shadow: 
    var(--glass-shadow-regular),
    inset 0 1px 1.5px 0 var(--glass-top-light-regular),
    inset 0 -1px 1px 0 rgba(0, 0, 0, 0.25),
    inset 0 0 14px 0 rgba(255, 255, 255, 0.05);
}

/* 315° Inset Meniscus Refraction Curve (Top Specular Highlight) */
.liquid-glass::before {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  border-radius: inherit;
  background: linear-gradient(
    175deg,
    rgba(255, 255, 255, 0.32) 0%,
    rgba(255, 255, 255, 0.10) 24%,
    rgba(255, 255, 255, 0.00) 55%
  );
  z-index: 1;
}

.liquid-glass > * {
  position: relative;
  z-index: 2;
}
```

---

## 4. Pure Cairo Desktop Engine (`macwidget.lua`)

Rendered natively on Linux X11/Wayland with pure Cairo:

```lua
local function draw_card(cr, x, y, w, h)
    if SETTINGS.color_mode == "glass" then
        local r = CARD_RADIUS
        local cx = x + 0.5
        local cy = y + 0.5
        local cw = w - 1
        local ch = h - 1

        -- Pass 1: Soft elevated drop shadow
        rounded_rect(cr, cx, cy + 4, cw, ch, r)
        cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.12)
        cairo_fill(cr)

        rounded_rect(cr, cx, cy + 2, cw, ch, r)
        cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.16)
        cairo_fill(cr)

        -- Pass 2: Apple iOS 26 Liquid Glass Translucent Base Fill (Figma #242424)
        local glass = cairo_pattern_create_linear(cx, cy, cx, cy + ch)
        cairo_pattern_add_color_stop_rgba(glass, 0.0,  0.15, 0.15, 0.17, 0.58)
        cairo_pattern_add_color_stop_rgba(glass, 0.40, 0.13, 0.13, 0.15, 0.52)
        cairo_pattern_add_color_stop_rgba(glass, 1.0,  0.11, 0.11, 0.13, 0.55)
        rounded_rect(cr, cx, cy, cw, ch, r)
        cairo_set_source(cr, glass)
        cairo_fill(cr)
        cairo_pattern_destroy(glass)

        -- Pass 3: Inset 315° Meniscus Specular Catchlight
        if ch > 20 and cw > 20 then
            rounded_rect(cr, cx + 1.0, cy + 1.0, cw - 2.0, ch - 2.0, math.max(4, r - 1.0))
            local meniscus = cairo_pattern_create_linear(cx, cy, cx, cy + math.min(ch * 0.45, 50))
            cairo_pattern_add_color_stop_rgba(meniscus, 0.0,  1.0, 1.0, 1.0, 0.38)
            cairo_pattern_add_color_stop_rgba(meniscus, 0.25, 1.0, 1.0, 1.0, 0.12)
            cairo_pattern_add_color_stop_rgba(meniscus, 1.0,  1.0, 1.0, 1.0, 0.00)
            cairo_set_source(cr, meniscus)
            cairo_set_line_width(cr, 1.0)
            cairo_stroke(cr)
            cairo_pattern_destroy(meniscus)
        end

        -- Pass 4: Razor-Thin Crystalline Outer Bevel
        rounded_rect(cr, cx, cy, cw, ch, r)
        local rim = cairo_pattern_create_linear(cx, cy, cx + cw * 0.6, cy + ch)
        cairo_pattern_add_color_stop_rgba(rim, 0.0,  1.0, 1.0, 1.0, 0.32)
        cairo_pattern_add_color_stop_rgba(rim, 0.35, 1.0, 1.0, 1.0, 0.18)
        cairo_pattern_add_color_stop_rgba(rim, 0.70, 1.0, 1.0, 1.0, 0.08)
        cairo_pattern_add_color_stop_rgba(rim, 1.0,  1.0, 1.0, 1.0, 0.22)
        cairo_set_source(cr, rim)
        cairo_set_line_width(cr, 0.85)
        cairo_stroke(cr)
        cairo_pattern_destroy(rim)
    end
end
```
