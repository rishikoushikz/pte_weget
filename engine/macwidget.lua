-- =======================================================================
-- Weget Core Engine — Pure Cairo Render
-- Categorized 9-Module Architecture supporting 3 Formats per Module (27 Renderers)
-- =======================================================================
pcall(require, 'cairo_xlib')
require 'cairo'

local LOGICAL_W = 350
local CARD_RADIUS = 24

-- Default Configuration
local SETTINGS = {
    color_mode = "dark",
    glass_effect = true,
    blur_radius = 30,
    blur_opacity = 0.60,
    widget_border = true,
    scale = 1.0,
    time_format = "24h",
    measurement_system = "metric",
    location = "Mumbai",
    slots = {
        A1 = "CALN_2x1_WID",
        A2 = "EMPTY",
        B1 = "WEAT_1x1_MIN",
        B2 = "RING_1x1_MIN",
        C1 = "NETW_2x1_WID",
        C2 = "EMPTY",
        D1 = "MEDI_2x1_WID",
        D2 = "EMPTY"
    }
}

-- Palette
local BG_COLOR     = { r = 0.086, g = 0.086, b = 0.102, a = 0.94 }
local BORDER_COLOR = { r = 1.000, g = 1.000, b = 1.000, a = 0.08 }
local TEXT_PRIMARY = { r = 0.960, g = 0.960, b = 0.970, a = 1.00 }
local TEXT_MUTED   = { r = 0.525, g = 0.525, b = 0.545, a = 1.00 }
local TEXT_DIM     = { r = 0.227, g = 0.227, b = 0.235, a = 1.00 }
local SUB_CARD_BG  = { r = 0.065, g = 0.065, b = 0.078, a = 0.85 }

-- Accents
local CORAL_RED    = { r = 1.000, g = 0.353, b = 0.322, a = 1.00 } -- #FF5A52
local BLUE_ROOT    = { r = 0.039, g = 0.518, b = 1.000, a = 1.00 } -- #0A84FF
local GREEN_HOME   = { r = 0.188, g = 0.820, b = 0.345, a = 1.00 } -- #30D158
local AMBER_CPU    = { r = 1.000, g = 0.624, b = 0.039, a = 1.00 } -- #FF9F0A
local PURPLE_MEDIA = { r = 0.749, g = 0.353, b = 0.949, a = 1.00 } -- #BF5AF2

-- Network History
local NET_BUFFER_LEN = 38
local net_up_history = {}
local net_down_history = {}
for i = 1, NET_BUFFER_LEN do
    net_up_history[i] = 0.0
    net_down_history[i] = 0.0
end

-- Click Zones
local CLICK_ZONES = {}

-- Dynamic Hardware Sensor Detection
local HWMON_TEMP_VAR = (function()
    for i = 0, 8 do
        local f = io.open("/sys/class/hwmon/hwmon" .. i .. "/temp1_input", "r")
        if f then
            f:close()
            return string.format("${hwmon %d temp 1}", i)
        end
    end
    return "${acpitemp}"
end)()

-- Watcher
local last_settings_str = ""
local settings_path = os.getenv("HOME") .. "/.config/conky/macwidget/settings/settings.json"

local blur_surface = nil
local blur_surface_failed = false
local blur_retry_count = 0
local blur_file = os.getenv("HOME") .. "/.cache/weget/blurred_wallpaper.png"

local function apply_theme(mode, border_enabled, glass_effect)
    local opacity = SETTINGS.blur_opacity or 0.60
    if glass_effect then
        if mode == "light" then
            -- Light Frosted Acrylic: Translucent white with dark crisp text
            BG_COLOR     = { r = 0.965, g = 0.965, b = 0.972, a = opacity }
            BORDER_COLOR = { r = 0.000, g = 0.000, b = 0.000, a = border_enabled and 0.06 or 0.0 }
            TEXT_PRIMARY = { r = 0.100, g = 0.100, b = 0.110, a = 1.00 }
            TEXT_MUTED   = { r = 0.400, g = 0.400, b = 0.420, a = 1.00 }
            TEXT_DIM     = { r = 0.700, g = 0.700, b = 0.720, a = 1.00 }
            SUB_CARD_BG  = { r = 0.000, g = 0.000, b = 0.000, a = 0.05 }
        else
            -- Dark Smoke Acrylic: Clean #1A1A1C translucent acrylic
            BG_COLOR     = { r = 0.102, g = 0.102, b = 0.110, a = opacity }
            BORDER_COLOR = { r = 1.000, g = 1.000, b = 1.000, a = border_enabled and 0.08 or 0.0 }
            TEXT_PRIMARY = { r = 1.000, g = 1.000, b = 1.000, a = 1.00 }
            TEXT_MUTED   = { r = 0.557, g = 0.557, b = 0.576, a = 1.00 }
            TEXT_DIM     = { r = 0.380, g = 0.380, b = 0.400, a = 1.00 }
            SUB_CARD_BG  = { r = 1.000, g = 1.000, b = 1.000, a = 0.08 }
        end
    elseif mode == "light" then
        BG_COLOR     = { r = 1.000, g = 1.000, b = 1.000, a = 0.96 }
        BORDER_COLOR = { r = 0.000, g = 0.000, b = 0.000, a = border_enabled and 0.08 or 0.0 }
        TEXT_PRIMARY = { r = 0.110, g = 0.110, b = 0.118, a = 1.00 }
        TEXT_MUTED   = { r = 0.388, g = 0.388, b = 0.400, a = 1.00 }
        TEXT_DIM     = { r = 0.850, g = 0.850, b = 0.870, a = 1.00 }
        SUB_CARD_BG  = { r = 0.930, g = 0.930, b = 0.940, a = 0.90 }
    else
        BG_COLOR     = { r = 0.086, g = 0.086, b = 0.102, a = 0.94 }
        BORDER_COLOR = { r = 1.000, g = 1.000, b = 1.000, a = border_enabled and 0.08 or 0.0 }
        TEXT_PRIMARY = { r = 0.960, g = 0.960, b = 0.970, a = 1.00 }
        TEXT_MUTED   = { r = 0.525, g = 0.525, b = 0.545, a = 1.00 }
        TEXT_DIM     = { r = 0.227, g = 0.227, b = 0.235, a = 1.00 }
        SUB_CARD_BG  = { r = 0.065, g = 0.065, b = 0.078, a = 0.85 }
    end
end

local function check_hot_reload()
    local f = io.open(settings_path, "r")
    if not f then return end
    local content = f:read("*a")
    f:close()

    if content and content ~= last_settings_str then
        last_settings_str = content

        local c_mode = content:match('"color_mode"%s*:%s*"([^"]+)"')
        if c_mode then SETTINGS.color_mode = c_mode end

        local g_effect = content:match('"glass_effect"%s*:%s*(%a+)')
        if g_effect ~= nil then
            SETTINGS.glass_effect = (g_effect == "true")
        elseif c_mode == "glass" then
            SETTINGS.glass_effect = true
            SETTINGS.color_mode = "dark"
        end

        local b_rad = content:match('"blur_radius"%s*:%s*(%d+)')
        if b_rad then
            local new_rad = tonumber(b_rad) or 30
            if new_rad ~= SETTINGS.blur_radius then
                SETTINGS.blur_radius = new_rad
                if blur_surface then
                    pcall(cairo_surface_destroy, blur_surface)
                    blur_surface = nil
                    blur_surface_failed = false
                end
            end
        end

        local b_opac = content:match('"blur_opacity"%s*:%s*([%d%.]+)')
        if b_opac then
            SETTINGS.blur_opacity = tonumber(b_opac) or 0.60
        end

        if not SETTINGS.glass_effect and blur_surface then
            pcall(cairo_surface_destroy, blur_surface)
            blur_surface = nil
            blur_surface_failed = false
        end

        local w_border = content:match('"widget_border"%s*:%s*(%a+)')
        if w_border ~= nil then SETTINGS.widget_border = (w_border == "true") end

        local sc = content:match('"scale"%s*:%s*([%d%.]+)')
        if sc then SETTINGS.scale = tonumber(sc) or 1.0 end

        local tf = content:match('"time_format"%s*:%s*"([^"]+)"')
        if tf then SETTINGS.time_format = tf end

        local ms = content:match('"measurement_system"%s*:%s*"([^"]+)"')
        if ms then SETTINGS.measurement_system = ms end

        local loc = content:match('"location"%s*:%s*"([^"]+)"')
        if loc then SETTINGS.location = loc end

        -- Parse all slots
        for _, s in ipairs({"A1", "A2", "B1", "B2", "C1", "C2", "D1", "D2"}) do
            local val = content:match('"' .. s .. '"%s*:%s*"([^"]+)"')
            if val then SETTINGS.slots[s] = val end
        end

        apply_theme(SETTINGS.color_mode, SETTINGS.widget_border, SETTINGS.glass_effect)
    end
end

-- -----------------------------------------------------------------------
-- Zero-Subprocess Telemetry Cache Reader
-- -----------------------------------------------------------------------
local TELEMETRY = {
    weather = {
        city = "Mumbai",
        temp = "29°C",
        desc = "Fair",
        feels = "33°C",
        hum = "65%",
        icon = "󰖙"
    },
    media = {
        status = "󰓛 Idle",
        is_playing = false,
        title = "No Media Playing",
        artist = "Weget Audio Engine",
        progress = 0.0,
        time = "--:--"
    },
    network = {
        ssid = "WiFi"
    },
    quote = {
        text = "Peace begins when you accept things as they are.",
        author = "Austin Freeman",
        tag = "Daily Wisdom"
    }
}

local function update_telemetry()
    local paths = {
        "/tmp/weget_telemetry.json",
        (os.getenv("HOME") or "") .. "/.cache/weget/telemetry.json"
    }
    for _, path in ipairs(paths) do
        local f = io.open(path, "r")
        if f then
            local str = f:read("*a")
            f:close()
            if str and str ~= "" then
                -- Weather
                local w_city = str:match('"city"%s*:%s*"([^"]+)"')
                if w_city then TELEMETRY.weather.city = w_city end
                local w_temp = str:match('"temp"%s*:%s*"([^"]+)"')
                if w_temp then TELEMETRY.weather.temp = w_temp end
                local w_desc = str:match('"desc"%s*:%s*"([^"]+)"')
                if w_desc then TELEMETRY.weather.desc = w_desc end
                local w_feels = str:match('"feels"%s*:%s*"([^"]+)"')
                if w_feels then TELEMETRY.weather.feels = w_feels end
                local w_hum = str:match('"hum"%s*:%s*"([^"]+)"')
                if w_hum then TELEMETRY.weather.hum = w_hum end
                local w_icon = str:match('"icon"%s*:%s*"([^"]+)"')
                if w_icon then TELEMETRY.weather.icon = w_icon end

                -- Media
                local m_status = str:match('"status"%s*:%s*"([^"]+)"')
                if m_status then TELEMETRY.media.status = m_status end
                local m_play = str:match('"is_playing"%s*:%s*(%a+)')
                if m_play ~= nil then TELEMETRY.media.is_playing = (m_play == "true") end
                local m_title = str:match('"title"%s*:%s*"([^"]+)"')
                if m_title then TELEMETRY.media.title = m_title end
                local m_artist = str:match('"artist"%s*:%s*"([^"]+)"')
                if m_artist then TELEMETRY.media.artist = m_artist end
                local m_prog = str:match('"progress"%s*:%s*([%d%.]+)')
                if m_prog then TELEMETRY.media.progress = tonumber(m_prog) or 0.0 end
                local m_time = str:match('"time"%s*:%s*"([^"]+)"')
                if m_time then TELEMETRY.media.time = m_time end

                -- Network
                local n_ssid = str:match('"ssid"%s*:%s*"([^"]+)"')
                if n_ssid then TELEMETRY.network.ssid = n_ssid end

                -- Quote
                local q_text = str:match('"text"%s*:%s*"([^"]+)"')
                if q_text then TELEMETRY.quote.text = q_text end
                local q_author = str:match('"author"%s*:%s*"([^"]+)"')
                if q_author then TELEMETRY.quote.author = q_author end
                local q_tag = str:match('"tag"%s*:%s*"([^"]+)"')
                if q_tag then TELEMETRY.quote.tag = q_tag end

                break
            end
        end
    end
end


-- -----------------------------------------------------------------------
-- Cairo Drawing Primitives
-- -----------------------------------------------------------------------
local function rounded_rect(cr, x, y, w, h, r)
    if r > h / 2 then r = h / 2 end
    if r > w / 2 then r = w / 2 end
    cairo_new_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r,     y + r,     r, math.pi, 3 * math.pi / 2)
    cairo_close_path(cr)
end

local function get_blur_surface()
    if blur_surface then return blur_surface end
    if blur_surface_failed then
        blur_retry_count = blur_retry_count + 1
        if blur_retry_count < 4 then return nil end
        blur_retry_count = 0
        blur_surface_failed = false
    end

    local f = io.open(blur_file, "r")
    if not f then
        blur_surface_failed = true
        os.execute("python3 helpers/blur.py >/dev/null 2>&1 &")
        return nil
    end
    f:close()

    local ok, s = pcall(cairo_image_surface_create_from_png, blur_file)
    if ok and s and cairo_surface_status(s) == 0 then
        blur_surface = s
        blur_surface_failed = false
    else
        blur_surface_failed = true
    end
    return blur_surface
end

local function draw_card(cr, x, y, w, h)
    local r = CARD_RADIUS
    local cx = x + 0.5
    local cy = y + 0.5
    local cw = w - 1
    local ch = h - 1

    if SETTINGS.glass_effect or SETTINGS.color_mode == "glass" then
        -- Pass 1: Soft Ambient Elevation Shadow (GNOME Shell window shadow)
        rounded_rect(cr, cx, cy + 3, cw, ch, r)
        cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.18)
        cairo_fill(cr)

        -- Pass 2: Genuine Frosted Wallpaper Blur (clipped to squircle)
        local b_surf = get_blur_surface()
        if b_surf then
            rounded_rect(cr, cx, cy, cw, ch, r)
            cairo_save(cr)
            cairo_clip(cr)
            cairo_set_source_surface(cr, b_surf, 0, 0)
            cairo_paint(cr)
            cairo_restore(cr)
        end

        -- Pass 3: Uniform Translucent Acrylic Surface Fill
        rounded_rect(cr, cx, cy, cw, ch, r)
        cairo_set_source_rgba(cr, BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, BG_COLOR.a)
        cairo_fill(cr)

        -- Pass 4: Uniform 1px Hairline Border (if enabled)
        if BORDER_COLOR.a > 0.001 then
            rounded_rect(cr, cx, cy, cw, ch, r)
            cairo_set_source_rgba(cr, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, BORDER_COLOR.a)
            cairo_set_line_width(cr, 1.0)
            cairo_stroke(cr)
        end
    else
        rounded_rect(cr, cx, cy, cw, ch, r)
        cairo_set_source_rgba(cr, BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, BG_COLOR.a)
        cairo_fill_preserve(cr)

        if BORDER_COLOR.a > 0.001 then
            cairo_set_source_rgba(cr, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, BORDER_COLOR.a)
            cairo_set_line_width(cr, 1.0)
            cairo_stroke(cr)
        else
            cairo_new_path(cr)
        end
    end
end

local function draw_sub_card(cr, x, y, w, h, r)
    local rad = r or 14
    local cx = x + 0.5
    local cy = y + 0.5
    local cw = w - 1
    local ch = h - 1
    rounded_rect(cr, cx, cy, cw, ch, rad)
    cairo_set_source_rgba(cr, SUB_CARD_BG.r, SUB_CARD_BG.g, SUB_CARD_BG.b, SUB_CARD_BG.a)
    cairo_fill_preserve(cr)

    if SETTINGS.glass_effect or SETTINGS.color_mode == "glass" then
        -- Subtle elevated matte border
        if SETTINGS.color_mode == "light" then
            cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.04)
        else
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.04)
        end
        cairo_set_line_width(cr, 0.75)
        cairo_stroke(cr)
    else
        cairo_new_path(cr)
    end
end

local function draw_text(cr, text, x, y, size, weight, color, align)
    cairo_select_font_face(cr, 'Noto Sans', CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    
    local draw_x = x
    if align == 'center' or align == 'right' then
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, text, ext)
        if align == 'center' then draw_x = x - ext.width / 2
        elseif align == 'right' then draw_x = x - ext.width end
    end

    if SETTINGS.color_mode == "glass" and (color.r > 0.8 and color.g > 0.8 and color.b > 0.8) then
        -- Micro text shadow for optical legibility over varied wallpapers
        cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.40 * (color.a or 1.0))
        cairo_move_to(cr, draw_x, y + 1)
        cairo_show_text(cr, text)
    end

    cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a or 1.0)
    cairo_move_to(cr, draw_x, y)
    cairo_show_text(cr, text)
end

local function draw_icon(cr, icon_char, x, y, size, color, align)
    cairo_select_font_face(cr, 'JetBrainsMono Nerd Font', CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    
    local draw_x = x
    if align == 'center' or align == 'right' then
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, icon_char, ext)
        if align == 'center' then draw_x = x - ext.width / 2
        elseif align == 'right' then draw_x = x - ext.width end
    end

    if SETTINGS.color_mode == "glass" and (color.r > 0.8 and color.g > 0.8 and color.b > 0.8) then
        cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35 * (color.a or 1.0))
        cairo_move_to(cr, draw_x, y + 1)
        cairo_show_text(cr, icon_char)
    end

    cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a or 1.0)
    cairo_move_to(cr, draw_x, y)
    cairo_show_text(cr, icon_char)
end

local function draw_arc_ring(cr, cx, cy, radius, width, frac, c)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, width)

    -- Inset dark base disc for depth
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, radius + width / 2, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, 0, 0, 0, 0.22)
    cairo_fill(cr)

    cairo_new_path(cr)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, 0.16)
    cairo_arc(cr, cx, cy, radius, 0, 2 * math.pi)
    cairo_stroke(cr)

    if frac > 0.005 then
        cairo_new_path(cr)
        local start_a = -math.pi / 2
        local end_a = start_a + frac * (2 * math.pi)
        cairo_set_source_rgba(cr, c.r, c.g, c.b, 0.98)
        cairo_arc(cr, cx, cy, radius, start_a, end_a)
        cairo_stroke(cr)
    end
end

local function draw_pill(cr, x, y, w, h, r, color)
    rounded_rect(cr, x + 0.5, y + 0.5, w - 1, h - 1, r)
    if SETTINGS.color_mode == "glass" then
        local alpha = color.a or 1.0
        if alpha < 0.25 then
            -- Floating light-frosted glass capsule (matching reference ▶ Play button & control capsules)
            local pill_sheen = cairo_pattern_create_linear(x, y, x, y + h)
            cairo_pattern_add_color_stop_rgba(pill_sheen, 0.0, 1.0, 1.0, 1.0, 0.45)
            cairo_pattern_add_color_stop_rgba(pill_sheen, 1.0, 1.0, 1.0, 1.0, 0.24)
            cairo_set_source(cr, pill_sheen)
            cairo_fill_preserve(cr)
            cairo_pattern_destroy(pill_sheen)

            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.60)
            cairo_set_line_width(cr, 0.85)
            cairo_stroke(cr)
        else
            -- Accent / vibrant pill (e.g. Scrubber progress, active play button)
            cairo_set_source_rgba(cr, color.r, color.g, color.b, math.min(0.92, alpha))
            cairo_fill_preserve(cr)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.40)
            cairo_set_line_width(cr, 0.85)
            cairo_stroke(cr)
        end
    else
        cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a or 1.0)
        cairo_fill(cr)
    end
end

local function read_pct(expr)
    return (tonumber(conky_parse(expr)) or 0) / 100
end

-- -----------------------------------------------------------------------
-- Pure Cairo Geometric Vector Icons
-- -----------------------------------------------------------------------
local function draw_vec_chip(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    cairo_set_line_width(cr, 1.5)
    rounded_rect(cr, cx - r*0.6, cy - r*0.6, r*1.2, r*1.2, 2)
    cairo_stroke(cr)
    -- Center core
    cairo_arc(cr, cx, cy, r*0.25, 0, 2 * math.pi)
    cairo_fill(cr)
    -- Pins
    for _, offset in ipairs({-r*0.35, r*0.35}) do
        -- Top & bottom
        cairo_move_to(cr, cx + offset, cy - r*0.6)
        cairo_line_to(cr, cx + offset, cy - r*0.85)
        cairo_move_to(cr, cx + offset, cy + r*0.6)
        cairo_line_to(cr, cx + offset, cy + r*0.85)
        -- Left & right
        cairo_move_to(cr, cx - r*0.6, cy + offset)
        cairo_line_to(cr, cx - r*0.85, cy + offset)
        cairo_move_to(cr, cx + r*0.6, cy + offset)
        cairo_line_to(cr, cx + r*0.85, cy + offset)
    end
    cairo_stroke(cr)
end

local function draw_vec_ram(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    cairo_set_line_width(cr, 1.4)
    rounded_rect(cr, cx - r*0.75, cy - r*0.4, r*1.5, r*0.8, 2)
    cairo_stroke(cr)
    -- Notch
    cairo_move_to(cr, cx, cy + r*0.4)
    cairo_line_to(cr, cx, cy + r*0.15)
    cairo_stroke(cr)
    -- Blocks
    for _, ox in ipairs({-r*0.45, r*0.25}) do
        rounded_rect(cr, cx + ox, cy - r*0.25, r*0.22, r*0.35, 1)
        cairo_fill(cr)
    end
end

local function draw_vec_battery(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    cairo_set_line_width(cr, 1.4)
    rounded_rect(cr, cx - r*0.65, cy - r*0.35, r*1.2, r*0.7, 2.5)
    cairo_stroke(cr)
    -- Terminal nub
    cairo_arc(cr, cx + r*0.65, cy, 1.8, -math.pi/2, math.pi/2)
    cairo_fill(cr)
    -- Fill bar
    rounded_rect(cr, cx - r*0.5, cy - r*0.2, r*0.75, r*0.4, 1.5)
    cairo_fill(cr)
end

local function draw_vec_temp(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    -- Bulb at bottom
    cairo_arc(cr, cx, cy + r*0.35, r*0.32, 0, 2 * math.pi)
    cairo_fill(cr)
    -- Stem
    rounded_rect(cr, cx - r*0.14, cy - r*0.7, r*0.28, r*0.8, r*0.14)
    cairo_fill(cr)
end

local function draw_vec_disk(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    cairo_set_line_width(cr, 1.4)
    rounded_rect(cr, cx - r*0.65, cy - r*0.5, r*1.3, r*1.0, 3)
    cairo_stroke(cr)
    -- Platter circle
    cairo_arc(cr, cx - r*0.15, cy - r*0.05, r*0.3, 0, 2 * math.pi)
    cairo_stroke(cr)
    -- LED dot
    cairo_arc(cr, cx + r*0.4, cy + r*0.25, 1.5, 0, 2 * math.pi)
    cairo_fill(cr)
end

local function draw_vec_home(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    cairo_new_path(cr)
    -- Roof
    cairo_move_to(cr, cx, cy - r*0.65)
    cairo_line_to(cr, cx + r*0.65, cy - r*0.1)
    cairo_line_to(cr, cx - r*0.65, cy - r*0.1)
    cairo_close_path(cr)
    cairo_fill(cr)
    -- Body
    rounded_rect(cr, cx - r*0.45, cy - r*0.1, r*0.9, r*0.65, 1)
    cairo_fill(cr)
end

local function draw_vec_usb(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    cairo_set_line_width(cr, 1.4)
    -- Body
    rounded_rect(cr, cx - r*0.45, cy - r*0.2, r*0.9, r*0.7, 2)
    cairo_fill(cr)
    -- Connector
    rounded_rect(cr, cx - r*0.3, cy - r*0.65, r*0.6, r*0.45, 1)
    cairo_stroke(cr)
end

local function draw_vec_slashed(cr, cx, cy, r, c)
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a or 1.0)
    cairo_set_line_width(cr, 1.5)
    cairo_arc(cr, cx, cy, r*0.55, 0, 2 * math.pi)
    cairo_stroke(cr)
    cairo_move_to(cr, cx - r*0.4, cy + r*0.4)
    cairo_line_to(cr, cx + r*0.4, cy - r*0.4)
    cairo_stroke(cr)
end

-- =======================================================================
-- MODULE FAMILY 1: NETWORK MONITOR
-- =======================================================================

-- 1.1 Network Pulse (1x1 Minimal)
local function draw_network_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local ssid = TELEMETRY.network.ssid or conky_parse("${wireless_essid}")
    if ssid == "" or ssid == nil or ssid == "off/any" then ssid = "WiFi" end

    local up_kb = tonumber(conky_parse("${upspeedf wlo1}")) or tonumber(conky_parse("${upspeedf}")) or 22.0
    local down_kb = tonumber(conky_parse("${downspeedf wlo1}")) or tonumber(conky_parse("${downspeedf}")) or 42.0

    table.remove(net_up_history, 1)
    table.insert(net_up_history, up_kb)
    table.remove(net_down_history, 1)
    table.insert(net_down_history, down_kb)

    local up_str = string.format("%d KB/s", math.floor(up_kb + 0.5))
    local down_str = string.format("%d KB/s", math.floor(down_kb + 0.5))

    -- Header
    draw_text(cr, "Wi-Fi : " .. ssid, card_x + 18, card_y + 24, 10, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    -- Inner container for mirrored graph
    local inner_x = card_x + 14
    local inner_y = card_y + 36
    local inner_w = card_w - 28
    local inner_h = card_h - 48
    draw_sub_card(cr, inner_x, inner_y, inner_w, inner_h, 12)

    -- Speeds inside container
    draw_text(cr, up_str, inner_x + 10, inner_y + 18, 9, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, down_str, inner_x + 10, inner_y + inner_h - 10, 9, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    -- Baseline
    local base_y = inner_y + inner_h / 2
    cairo_new_path(cr)
    cairo_move_to(cr, inner_x + 8, base_y)
    cairo_line_to(cr, inner_x + inner_w - 8, base_y)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.15)
    cairo_set_line_width(cr, 1.0)
    cairo_stroke(cr)

    -- Waveform
    local num_pts = 24
    local step = (inner_w - 16) / (num_pts - 1)
    local max_speed = 60.0

    -- Up waveform (Coral Red)
    cairo_new_path(cr)
    cairo_move_to(cr, inner_x + 8, base_y)
    for i = 1, num_pts do
        local val = net_up_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 5.0
        local h = math.min(inner_h * 0.42, (val / max_speed) * (inner_h * 0.42))
        cairo_line_to(cr, inner_x + 8 + (i - 1) * step, base_y - h)
    end
    cairo_line_to(cr, inner_x + inner_w - 8, base_y)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, CORAL_RED.r, CORAL_RED.g, CORAL_RED.b, 0.25)
    cairo_fill(cr)

    cairo_new_path(cr)
    for i = 1, num_pts do
        local val = net_up_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 5.0
        local h = math.min(inner_h * 0.42, (val / max_speed) * (inner_h * 0.42))
        local px = inner_x + 8 + (i - 1) * step
        local py = base_y - h
        if i == 1 then cairo_move_to(cr, px, py) else cairo_line_to(cr, px, py) end
    end
    cairo_set_source_rgba(cr, CORAL_RED.r, CORAL_RED.g, CORAL_RED.b, 0.95)
    cairo_set_line_width(cr, 1.4)
    cairo_stroke(cr)

    -- Down waveform (Purple)
    cairo_new_path(cr)
    cairo_move_to(cr, inner_x + 8, base_y)
    for i = 1, num_pts do
        local val = net_down_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 10.0
        local h = math.min(inner_h * 0.42, (val / max_speed) * (inner_h * 0.42))
        cairo_line_to(cr, inner_x + 8 + (i - 1) * step, base_y + h)
    end
    cairo_line_to(cr, inner_x + inner_w - 8, base_y)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, PURPLE_MEDIA.r, PURPLE_MEDIA.g, PURPLE_MEDIA.b, 0.25)
    cairo_fill(cr)

    cairo_new_path(cr)
    for i = 1, num_pts do
        local val = net_down_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 10.0
        local h = math.min(inner_h * 0.42, (val / max_speed) * (inner_h * 0.42))
        local px = inner_x + 8 + (i - 1) * step
        local py = base_y + h
        if i == 1 then cairo_move_to(cr, px, py) else cairo_line_to(cr, px, py) end
    end
    cairo_set_source_rgba(cr, PURPLE_MEDIA.r, PURPLE_MEDIA.g, PURPLE_MEDIA.b, 0.95)
    cairo_set_line_width(cr, 1.4)
    cairo_stroke(cr)
end

-- 1.2 Dual Bandwidth Track (1x1 Detailed)
local function draw_network_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local ssid = TELEMETRY.network.ssid or conky_parse("${wireless_essid}")
    if ssid == "" or ssid == nil or ssid == "off/any" then ssid = "WiFi" end

    local up_str = conky_parse("${upspeed}")
    if up_str == "" or up_str == nil or up_str == "0B" then up_str = "0 KB/s" end
    local tot_up = conky_parse("${totalup}")
    if tot_up == "" or tot_up == nil then tot_up = "0 MiB" end

    local down_str = conky_parse("${downspeed}")
    if down_str == "" or down_str == nil or down_str == "0B" then down_str = "0 KB/s" end
    local tot_down = conky_parse("${totaldown}")
    if tot_down == "" or tot_down == nil then tot_down = "0 MiB" end

    draw_text(cr, "Wi-Fi : " .. ssid, card_x + 16, card_y + 20, 10, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    -- Top sub-card (Upload - Red)
    local sub_w = card_w - 28
    local sub_h = 32
    local top_y = card_y + 28
    draw_sub_card(cr, card_x + 14, top_y, sub_w, sub_h, 8)

    -- Red line graph with area fill
    cairo_new_path(cr)
    cairo_move_to(cr, card_x + 18, top_y + sub_h - 4)
    cairo_line_to(cr, card_x + 40, top_y + sub_h - 8)
    cairo_line_to(cr, card_x + 65, top_y + 6)
    cairo_line_to(cr, card_x + 85, top_y + 18)
    cairo_line_to(cr, card_x + 110, top_y + 10)
    cairo_line_to(cr, card_x + card_w - 18, top_y + sub_h - 4)
    cairo_line_to(cr, card_x + card_w - 18, top_y + sub_h)
    cairo_line_to(cr, card_x + 18, top_y + sub_h)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, CORAL_RED.r, CORAL_RED.g, CORAL_RED.b, 0.25)
    cairo_fill(cr)

    cairo_new_path(cr)
    cairo_move_to(cr, card_x + 18, top_y + sub_h - 4)
    cairo_line_to(cr, card_x + 40, top_y + sub_h - 8)
    cairo_line_to(cr, card_x + 65, top_y + 6)
    cairo_line_to(cr, card_x + 85, top_y + 18)
    cairo_line_to(cr, card_x + 110, top_y + 10)
    cairo_line_to(cr, card_x + card_w - 18, top_y + sub_h - 4)
    cairo_set_source_rgba(cr, CORAL_RED.r, CORAL_RED.g, CORAL_RED.b, 0.95)
    cairo_set_line_width(cr, 1.4)
    cairo_stroke(cr)

    local stat1_y = top_y + sub_h + 12
    draw_text(cr, up_str, card_x + 16, stat1_y, 8.5, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, tot_up, card_x + card_w - 16, stat1_y, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')

    -- Bottom sub-card (Download - Green)
    local bot_y = stat1_y + 6
    draw_sub_card(cr, card_x + 14, bot_y, sub_w, sub_h, 8)

    cairo_new_path(cr)
    cairo_move_to(cr, card_x + 18, bot_y + sub_h - 4)
    cairo_line_to(cr, card_x + 50, bot_y + sub_h - 10)
    cairo_line_to(cr, card_x + 70, bot_y + 12)
    cairo_line_to(cr, card_x + 100, bot_y + 20)
    cairo_line_to(cr, card_x + 118, bot_y + 6)
    cairo_line_to(cr, card_x + card_w - 18, bot_y + sub_h - 4)
    cairo_line_to(cr, card_x + card_w - 18, bot_y + sub_h)
    cairo_line_to(cr, card_x + 18, bot_y + sub_h)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, GREEN_HOME.r, GREEN_HOME.g, GREEN_HOME.b, 0.25)
    cairo_fill(cr)

    cairo_new_path(cr)
    cairo_move_to(cr, card_x + 18, bot_y + sub_h - 4)
    cairo_line_to(cr, card_x + 50, bot_y + sub_h - 10)
    cairo_line_to(cr, card_x + 70, bot_y + 12)
    cairo_line_to(cr, card_x + 100, bot_y + 20)
    cairo_line_to(cr, card_x + 118, bot_y + 6)
    cairo_line_to(cr, card_x + card_w - 18, bot_y + sub_h - 4)
    cairo_set_source_rgba(cr, GREEN_HOME.r, GREEN_HOME.g, GREEN_HOME.b, 0.95)
    cairo_set_line_width(cr, 1.4)
    cairo_stroke(cr)

    local stat2_y = bot_y + sub_h + 12
    draw_text(cr, down_str, card_x + 16, stat2_y, 8.5, CAIRO_FONT_WEIGHT_BOLD, GREEN_HOME, 'left')
    draw_text(cr, tot_down, card_x + card_w - 16, stat2_y, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')
end

-- 1.3 Network Seismograph (2x1 Wide)
local function draw_network_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local ssid = TELEMETRY.network.ssid or conky_parse("${wireless_essid}")
    if ssid == "" or ssid == nil or ssid == "off/any" then ssid = "WiFi" end

    local up_str = conky_parse("${upspeed}")
    if up_str == "" or up_str == nil or up_str == "0B" then up_str = "0 KB/s" end
    local tot_up = conky_parse("${totalup}")
    if tot_up == "" or tot_up == nil then tot_up = "0 MiB" end

    local down_str = conky_parse("${downspeed}")
    if down_str == "" or down_str == nil or down_str == "0B" then down_str = "0 KB/s" end
    local tot_down = conky_parse("${totaldown}")
    if tot_down == "" or tot_down == nil then tot_down = "0 MiB" end

    -- Title
    draw_text(cr, "Wi-Fi : " .. ssid, card_x + 20, card_y + 24, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    -- Left 62%: Waveform card
    local wave_x = card_x + 18
    local wave_y = card_y + 34
    local wave_w = 205
    local wave_h = card_h - 48
    draw_sub_card(cr, wave_x, wave_y, wave_w, wave_h, 12)

    local base_y = wave_y + wave_h / 2
    cairo_new_path(cr)
    cairo_move_to(cr, wave_x + 8, base_y)
    cairo_line_to(cr, wave_x + wave_w - 8, base_y)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.15)
    cairo_set_line_width(cr, 1.0)
    cairo_stroke(cr)

    -- Waveform line peaks
    local num_pts = 26
    local step = (wave_w - 16) / (num_pts - 1)
    
    -- Up peaks (Red)
    cairo_new_path(cr)
    cairo_move_to(cr, wave_x + 8, base_y)
    for i = 1, num_pts do
        local val = net_up_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 0.0
        local h = math.min(wave_h * 0.44, (val / 50.0) * (wave_h * 0.44))
        cairo_line_to(cr, wave_x + 8 + (i - 1) * step, base_y - h)
    end
    cairo_line_to(cr, wave_x + wave_w - 8, base_y)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, CORAL_RED.r, CORAL_RED.g, CORAL_RED.b, 0.22)
    cairo_fill(cr)

    cairo_new_path(cr)
    for i = 1, num_pts do
        local val = net_up_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 0.0
        local h = math.min(wave_h * 0.44, (val / 50.0) * (wave_h * 0.44))
        local px = wave_x + 8 + (i - 1) * step
        local py = base_y - h
        if i == 1 then cairo_move_to(cr, px, py) else cairo_line_to(cr, px, py) end
    end
    cairo_set_source_rgba(cr, CORAL_RED.r, CORAL_RED.g, CORAL_RED.b, 0.95)
    cairo_set_line_width(cr, 1.4)
    cairo_stroke(cr)

    -- Down peaks (Blue)
    cairo_new_path(cr)
    cairo_move_to(cr, wave_x + 8, base_y)
    for i = 1, num_pts do
        local val = net_down_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 0.0
        local h = math.min(wave_h * 0.44, (val / 50.0) * (wave_h * 0.44))
        cairo_line_to(cr, wave_x + 8 + (i - 1) * step, base_y + h)
    end
    cairo_line_to(cr, wave_x + wave_w - 8, base_y)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, BLUE_ROOT.r, BLUE_ROOT.g, BLUE_ROOT.b, 0.22)
    cairo_fill(cr)

    cairo_new_path(cr)
    for i = 1, num_pts do
        local val = net_down_history[math.floor((i / num_pts) * NET_BUFFER_LEN) + 1] or 0.0
        local h = math.min(wave_h * 0.44, (val / 50.0) * (wave_h * 0.44))
        local px = wave_x + 8 + (i - 1) * step
        local py = base_y + h
        if i == 1 then cairo_move_to(cr, px, py) else cairo_line_to(cr, px, py) end
    end
    cairo_set_source_rgba(cr, BLUE_ROOT.r, BLUE_ROOT.g, BLUE_ROOT.b, 0.95)
    cairo_set_line_width(cr, 1.4)
    cairo_stroke(cr)

    -- Right 38%: Telemetry stack
    local stat_x = card_x + 238
    draw_text(cr, "Upload Speed", stat_x, card_y + 36, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
    draw_text(cr, up_str, stat_x, card_y + 48, 10, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')

    draw_text(cr, "Total Upload", stat_x, card_y + 62, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
    draw_text(cr, tot_up, stat_x, card_y + 74, 10, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')

    draw_text(cr, "Download Speed", stat_x, card_y + 88, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
    draw_text(cr, down_str, stat_x, card_y + 100, 10, CAIRO_FONT_WEIGHT_BOLD, BLUE_ROOT, 'left')

    draw_text(cr, "Total Download", stat_x, card_y + 114, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
    draw_text(cr, tot_down, stat_x, card_y + 126, 10, CAIRO_FONT_WEIGHT_BOLD, BLUE_ROOT, 'left')
end

-- =======================================================================
-- MODULE FAMILY 2: CALENDAR & AGENDA
-- =======================================================================

-- Helper to draw 7-day monthly matrix
local function render_month_grid(cr, grid_x, grid_y, col_w, row_h, cur_day)
    local headers = { "M", "T", "W", "T", "F", "S", "S" }
    for col = 1, 7 do
        draw_text(cr, headers[col], grid_x + (col - 1) * col_w + col_w / 2, grid_y, 8.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    end

    local now = os.date("*t")
    local first_day_time = os.time{ year = now.year, month = now.month, day = 1 }
    local first_wday = tonumber(os.date("%w", first_day_time))
    if first_wday == 0 then first_wday = 7 end

    local next_m_time = os.time{ year = (now.month == 12 and now.year + 1 or now.year), month = (now.month == 12 and 1 or now.month + 1), day = 1 }
    local days_in_month = math.floor(os.difftime(next_m_time, first_day_time) / 86400 + 0.5)

    local row = 1
    local col = first_wday

    for d = 1, days_in_month do
        local cx = grid_x + (col - 1) * col_w + col_w / 2
        local cy = grid_y + row * row_h

        if d == cur_day then
            cairo_new_path(cr)
            cairo_arc(cr, cx, cy - 3.5, 8.5, 0, 2 * math.pi)
            cairo_set_source_rgba(cr, CORAL_RED.r, CORAL_RED.g, CORAL_RED.b, 1.0)
            cairo_fill(cr)
            draw_text(cr, tostring(d), cx, cy, 8.5, CAIRO_FONT_WEIGHT_BOLD, { r = 1, g = 1, b = 1 }, 'center')
        else
            draw_text(cr, tostring(d), cx, cy, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_PRIMARY, 'center')
        end

        col = col + 1
        if col > 7 then
            col = 1
            row = row + 1
        end
    end
end

-- 2.1 Monthly Matrix (1x1 Minimal)
local function draw_calendar_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local month_str = string.upper(os.date("%B"))
    local cur_day = tonumber(os.date("%d"))

    draw_text(cr, month_str, card_x + 18, card_y + 24, 11, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')

    local grid_x = card_x + 14
    local grid_y = card_y + 40
    local col_w = (card_w - 28) / 7
    local row_h = 17

    render_month_grid(cr, grid_x, grid_y, col_w, row_h, cur_day)
end

-- 2.2 Day Horizon (1x1 Detailed)
local function draw_calendar_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local month_str = string.upper(os.date("%B"))
    local wday_str  = os.date("%A")
    local day_num   = tonumber(os.date("%d"))

    draw_text(cr, month_str, card_x + 20, card_y + 26, 9.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
    draw_text(cr, wday_str,  card_x + 20, card_y + 44, 13, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, string.format("%02d", day_num), card_x + 18, card_y + 96, 46, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    -- Event pill
    draw_pill(cr, card_x + 20, card_y + 114, 3.5, 24, 1.75, CORAL_RED)
    draw_text(cr, "System Active", card_x + 30, card_y + 125, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, "Today", card_x + 30, card_y + 137, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
end

-- 2.3 Executive Calendar (2x1 Wide)
local function draw_calendar_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local month_str = string.upper(os.date("%B"))
    local wday_str  = os.date("%A")
    local day_num   = tonumber(os.date("%d"))

    -- Left: Month, Weekday, Big Date, Event
    draw_text(cr, month_str, card_x + 22, card_y + 28, 9.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
    draw_text(cr, wday_str,  card_x + 22, card_y + 46, 13, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, string.format("%02d", day_num), card_x + 20, card_y + 98, 46, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    draw_pill(cr, card_x + 22, card_y + 118, 3.5, 24, 1.75, CORAL_RED)
    draw_text(cr, "System Active", card_x + 32, card_y + 129, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, "Today", card_x + 32, card_y + 141, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')

    -- Right: 7-day grid
    local grid_x = card_x + 148
    local grid_y = card_y + 28
    local col_w = (card_w - grid_x - 14) / 7
    local row_h = 19
    render_month_grid(cr, grid_x, grid_y, col_w, row_h, day_num)
end

-- =======================================================================
-- MODULE FAMILY 3: ANALOG CLOCK
-- =======================================================================

-- Helper to draw an analog clock face
local function render_analog_clock(cr, cx, cy, r, sec_color, is_light, show_numbers)
    local now = os.date("*t")
    local s = now.sec
    local m = now.min + s / 60
    local h = (now.hour % 12) + m / 60

    -- Dial circle
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, is_light and 0.08 or 0.04)
    cairo_fill_preserve(cr)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.12)
    cairo_set_line_width(cr, 1.0)
    cairo_stroke(cr)

    -- Numbers or tick marks
    if show_numbers then
        for i = 1, 12 do
            local angle = (i * 30 - 90) * (math.pi / 180)
            local tx = cx + math.cos(angle) * (r - 10)
            local ty = cy + math.sin(angle) * (r - 10) + 3.5
            draw_text(cr, tostring(i), tx, ty, 7.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
        end
    else
        for i = 1, 12 do
            local angle = (i * 30 - 90) * (math.pi / 180)
            local r_in = (i % 3 == 0) and (r - 7) or (r - 4)
            cairo_move_to(cr, cx + math.cos(angle) * r_in, cy + math.sin(angle) * r_in)
            cairo_line_to(cr, cx + math.cos(angle) * (r - 1), cy + math.sin(angle) * (r - 1))
            cairo_set_line_width(cr, (i % 3 == 0) and 1.8 or 1.0)
            cairo_set_source_rgba(cr, TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, 0.6)
            cairo_stroke(cr)
        end
    end

    -- Hour hand
    local h_angle = (h * 30 - 90) * (math.pi / 180)
    cairo_new_path(cr)
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + math.cos(h_angle) * (r * 0.52), cy + math.sin(h_angle) * (r * 0.52))
    cairo_set_source_rgba(cr, TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, 0.95)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, 2.5)
    cairo_stroke(cr)

    -- Minute hand
    local m_angle = (m * 6 - 90) * (math.pi / 180)
    cairo_new_path(cr)
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + math.cos(m_angle) * (r * 0.76), cy + math.sin(m_angle) * (r * 0.76))
    cairo_set_source_rgba(cr, TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, 0.95)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, 1.8)
    cairo_stroke(cr)

    -- Second hand
    local s_angle = (s * 6 - 90) * (math.pi / 180)
    cairo_new_path(cr)
    cairo_move_to(cr, cx - math.cos(s_angle) * 8, cy - math.sin(s_angle) * 8)
    cairo_line_to(cr, cx + math.cos(s_angle) * (r * 0.85), cy + math.sin(s_angle) * (r * 0.85))
    cairo_set_source_rgba(cr, sec_color.r, sec_color.g, sec_color.b, 0.95)
    cairo_set_line_width(cr, 1.0)
    cairo_stroke(cr)

    -- Pivot dot
    cairo_arc(cr, cx, cy, 2.5, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, sec_color.r, sec_color.g, sec_color.b, 1.0)
    cairo_fill(cr)
end

-- 3.1 Classic Chrono (1x1 Minimal)
local function draw_analogue_clock_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)
    local cx = card_x + card_w / 2
    local cy = card_y + card_h / 2
    render_analog_clock(cr, cx, cy, 54, AMBER_CPU, SETTINGS.color_mode == "light", true)
end

-- 3.2 Precision Squircle (1x1 Detailed)
local function draw_analogue_clock_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local cx = card_x + card_w / 2
    local cy = card_y + card_h / 2

    -- Cardinal numbers: 12, 3, 6, 9
    draw_text(cr, "12", cx, card_y + 24, 13, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    draw_text(cr, "3", card_x + card_w - 20, cy + 5, 13, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    draw_text(cr, "6", cx, card_y + card_h - 14, 13, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    draw_text(cr, "9", card_x + 20, cy + 5, 13, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')

    -- Radiating border tick marks
    cairo_set_line_width(cr, 1.5)
    for i = 1, 12 do
        if i % 3 ~= 0 then
            local angle = (i * 30 - 90) * (math.pi / 180)
            local r_out = 62
            local r_in = 52
            cairo_move_to(cr, cx + math.cos(angle) * r_in, cy + math.sin(angle) * r_in)
            cairo_line_to(cr, cx + math.cos(angle) * r_out, cy + math.sin(angle) * r_out)
            cairo_set_source_rgba(cr, TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, 0.7)
            cairo_stroke(cr)
        end
    end

    -- Hands
    local now = os.date("*t")
    local s = now.sec
    local m = now.min + s / 60
    local h = (now.hour % 12) + m / 60

    -- Hour hand
    local h_angle = (h * 30 - 90) * (math.pi / 180)
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + math.cos(h_angle) * 36, cy + math.sin(h_angle) * 36)
    cairo_set_source_rgba(cr, TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, 1.0)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, 3.2)
    cairo_stroke(cr)

    -- Minute hand
    local m_angle = (m * 6 - 90) * (math.pi / 180)
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + math.cos(m_angle) * 52, cy + math.sin(m_angle) * 52)
    cairo_set_source_rgba(cr, TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, 1.0)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, 2.2)
    cairo_stroke(cr)

    -- Orange Sweep Second Hand
    local s_angle = (s * 6 - 90) * (math.pi / 180)
    cairo_move_to(cr, cx - math.cos(s_angle) * 10, cy - math.sin(s_angle) * 10)
    cairo_line_to(cr, cx + math.cos(s_angle) * 58, cy + math.sin(s_angle) * 58)
    cairo_set_source_rgba(cr, AMBER_CPU.r, AMBER_CPU.g, AMBER_CPU.b, 1.0)
    cairo_set_line_width(cr, 1.2)
    cairo_stroke(cr)

    cairo_arc(cr, cx, cy, 3.0, 0, 2 * math.pi)
    cairo_fill(cr)
end

-- 3.3 World Chronometer (2x1 Wide)
local function draw_analogue_clock_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local cities = {
        { name = "Local", offset = "Current", sec_color = AMBER_CPU, is_alt = false },
        { name = "Tokyo", offset = "+2 HRS",  sec_color = BLUE_ROOT, is_alt = false },
        { name = "London", offset = "-6 HRS", sec_color = GREEN_HOME, is_alt = true },
        { name = "Los Angeles", offset = "+10 HRS", sec_color = PURPLE_MEDIA, is_alt = true }
    }

    local col_w = card_w / 4
    local cy = card_y + 44
    local r = 24

    for i, city in ipairs(cities) do
        local cx = card_x + (i - 0.5) * col_w
        render_analog_clock(cr, cx, cy, r, city.sec_color, city.is_alt, false)

        draw_text(cr, city.name, cx, card_y + 86, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
        draw_text(cr, city.offset, cx, card_y + 98, 8, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'center')
    end
end

-- =======================================================================
-- MODULE FAMILY 4: DIGITAL CLOCK
-- =======================================================================

-- 4.1 Digital Glance (1x1 Minimal)
local function draw_digital_clock_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local is_12h = (SETTINGS.time_format == "12h")
    local time_fmt = is_12h and "%I:%M" or "%H:%M"
    local time_str = os.date(time_fmt)

    local cx = card_x + card_w / 2
    local cy = card_y + card_h / 2

    -- Pure, iconic minimalism: Just the bold time, optically centered with generous breathing room
    draw_text(cr, time_str, cx, cy + 18, 52, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
end

-- 4.2 Chrono Detailed (1x1 Detailed)
local function draw_digital_clock_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local is_12h = (SETTINGS.time_format == "12h")
    local time_fmt = is_12h and "%I:%M" or "%H:%M"
    local time_str = os.date(time_fmt)
    local sec_str  = os.date(":%S")
    local wday_str = os.date("%A")
    local full_date = os.date("%d %B %Y")

    -- Weekday in accent color
    draw_text(cr, string.upper(wday_str), card_x + 20, card_y + 36, 10, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')

    -- Time with Seconds inline (clean, no boxy pills)
    draw_text(cr, time_str, card_x + 20, card_y + 82, 38, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, sec_str, card_x + 124, card_y + 82, 16, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')

    -- Clean full date below
    draw_text(cr, full_date, card_x + 20, card_y + 118, 12, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')
end

-- 4.3 Horizon Panoramic Clock (2x1 Wide)
local function draw_digital_clock_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local is_12h = (SETTINGS.time_format == "12h")
    local time_fmt = is_12h and "%I:%M" or "%H:%M"
    local time_str = os.date(time_fmt)
    local sec_str  = os.date(":%S")
    local ampm_str = is_12h and (" " .. os.date("%p")) or ""
    local wday_str = os.date("%A")
    local full_date = os.date("%A, %d %B %Y")

    local mid_x = card_x + 175
    local cy = card_y + card_h / 2

    -- Left half: Prominent panoramic time + seconds
    draw_text(cr, time_str, card_x + 24, cy + 14, 46, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, sec_str .. ampm_str, card_x + 152, cy + 14, 15, CAIRO_FONT_WEIGHT_BOLD, AMBER_CPU, 'left')

    -- Subtle vertical divider
    cairo_set_source_rgba(cr, 1, 1, 1, 0.08)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, mid_x + 30, card_y + 24)
    cairo_line_to(cr, mid_x + 30, card_y + card_h - 24)
    cairo_stroke(cr)

    -- Right half: Clean Date & Schedule anchor
    draw_text(cr, string.upper(wday_str), mid_x + 46, cy - 6, 11, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, os.date("%d %B %Y"), mid_x + 46, cy + 16, 13, CAIRO_FONT_WEIGHT_NORMAL, TEXT_PRIMARY, 'left')
end

-- =======================================================================
-- MODULE FAMILY 5: DISK STORAGE
-- =======================================================================

-- 5.1 Storage Dual Bar (1x1 Minimal)
local function draw_storage_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local root_pct = conky_parse("${fs_used_perc /}") .. "%"
    local root_used = conky_parse("${fs_used /}")
    local root_size = conky_parse("${fs_size /}")
    local root_frac = read_pct("${fs_used_perc /}")

    local home_pct = conky_parse("${fs_used_perc /home}") .. "%"
    local home_used = conky_parse("${fs_used /home}")
    local home_size = conky_parse("${fs_size /home}")
    local home_frac = read_pct("${fs_used_perc /home}")

    draw_text(cr, "STORAGE", card_x + 18, card_y + 22, 9, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'left')
    draw_icon(cr, "󰋊", card_x + card_w - 18, card_y + 23, 14, TEXT_MUTED, 'right')

    local bar_w = card_w - 36

    -- Root bar
    draw_text(cr, "Root (" .. root_pct .. ")", card_x + 18, card_y + 44, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, root_used .. " / " .. root_size, card_x + card_w - 18, card_y + 44, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')
    draw_pill(cr, card_x + 18, card_y + 52, bar_w, 8, 4, { r = 1, g = 1, b = 1, a = 0.08 })
    draw_pill(cr, card_x + 18, card_y + 52, math.max(8, bar_w * root_frac), 8, 4, BLUE_ROOT)

    -- Home bar
    draw_text(cr, "Home (" .. home_pct .. ")", card_x + 18, card_y + 82, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, home_used .. " / " .. home_size, card_x + card_w - 18, card_y + 82, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')
    draw_pill(cr, card_x + 18, card_y + 90, bar_w, 8, 4, { r = 1, g = 1, b = 1, a = 0.08 })
    draw_pill(cr, card_x + 18, card_y + 90, math.max(8, bar_w * home_frac), 8, 4, GREEN_HOME)

    -- Free pill at bottom
    local free_str = conky_parse("${fs_free /}") .. " available"
    draw_pill(cr, card_x + 18, card_y + 116, bar_w, 20, 6, { r = 1, g = 1, b = 1, a = 0.05 })
    draw_text(cr, free_str, card_x + card_w / 2, card_y + 129, 8.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'center')
end

-- 5.2 Concentric Disk Rings (1x1 Detailed)
local function draw_storage_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local root_frac = read_pct("${fs_used_perc /}")
    local home_frac = read_pct("${fs_used_perc /home}")
    local free_str  = conky_parse("${fs_free /}")

    local cx = card_x + card_w / 2
    local cy = card_y + 48

    -- Inset base circle
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, 38, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, 0, 0, 0, 0.25)
    cairo_fill(cr)

    -- Concentric rings: outer (blue), middle (green), inner (orange/amber)
    draw_arc_ring(cr, cx, cy, 32, 4.5, root_frac, BLUE_ROOT)
    draw_arc_ring(cr, cx, cy, 23, 4.0, home_frac, GREEN_HOME)
    draw_arc_ring(cr, cx, cy, 14, 3.5, 0.08, AMBER_CPU)

    -- Disk icon in center
    draw_icon(cr, "󰋊", cx, cy + 5, 12, TEXT_MUTED, 'center')

    -- Legend table
    local r_used = conky_parse("${fs_used /}")
    local r_size = conky_parse("${fs_size /}")
    local h_used = conky_parse("${fs_used /home}")
    local h_size = conky_parse("${fs_size /home}")

    local row1_y = card_y + 98
    local row2_y = card_y + 114
    local row3_y = card_y + 130

    -- Row 1: Root
    cairo_new_path(cr)
    cairo_arc(cr, card_x + 22, row1_y - 3.5, 3.5, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, BLUE_ROOT.r, BLUE_ROOT.g, BLUE_ROOT.b, 1.0)
    cairo_fill(cr)
    draw_text(cr, "Root", card_x + 32, row1_y, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, r_used .. " / " .. r_size, card_x + card_w - 20, row1_y, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')

    -- Row 2: Home
    cairo_new_path(cr)
    cairo_arc(cr, card_x + 22, row2_y - 3.5, 3.5, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, GREEN_HOME.r, GREEN_HOME.g, GREEN_HOME.b, 1.0)
    cairo_fill(cr)
    draw_text(cr, "Home", card_x + 32, row2_y, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, h_used .. " / " .. h_size, card_x + card_w - 20, row2_y, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')

    -- Row 3: Free
    cairo_new_path(cr)
    cairo_arc(cr, card_x + 22, row3_y - 3.5, 3.5, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, AMBER_CPU.r, AMBER_CPU.g, AMBER_CPU.b, 1.0)
    cairo_fill(cr)
    draw_text(cr, "Free", card_x + 32, row3_y, 9.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, free_str .. " available", card_x + card_w - 20, row3_y, 8.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')
end

-- 5.3 Quad Drive Array (2x1 Wide)
local function draw_storage_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local drives = {
        { name = "Root", pct = conky_parse("${fs_used_perc /}") .. "%", size = conky_parse("${fs_size /}"), frac = read_pct("${fs_used_perc /}"), color = BLUE_ROOT, type = "disk" },
        { name = "Home", pct = conky_parse("${fs_used_perc /home}") .. "%", size = conky_parse("${fs_size /home}"), frac = read_pct("${fs_used_perc /home}"), color = GREEN_HOME, type = "home" },
        { name = "RAM",  pct = conky_parse("${memperc}") .. "%", size = conky_parse("${memmax}"), frac = read_pct("${memperc}"), color = PURPLE_MEDIA, type = "ram" },
        { name = "Free", pct = conky_parse("${fs_free_perc /}") .. "%", size = conky_parse("${fs_free /}"), frac = read_pct("${fs_free_perc /}"), color = AMBER_CPU, type = "free" }
    }

    local col_w = card_w / 4
    local cy = card_y + 44
    local r = 24

    for i, d in ipairs(drives) do
        local cx = card_x + (i - 0.5) * col_w
        draw_arc_ring(cr, cx, cy, r, 5.0, d.frac, d.color)

        -- Vector Icon inside
        if d.type == "disk" then draw_vec_disk(cr, cx, cy, 14, d.color)
        elseif d.type == "home" then draw_vec_home(cr, cx, cy, 14, d.color)
        elseif d.type == "ram" then draw_vec_ram(cr, cx, cy, 14, d.color)
        else draw_icon(cr, "󰋊", cx, cy + 5, 14, d.color, 'center') end

        draw_text(cr, d.pct, cx, card_y + 88, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
        draw_text(cr, d.name .. " · " .. d.size, cx, card_y + 102, 8, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'center')
    end
end

-- =======================================================================
-- MODULE FAMILY 6: SYSTEM SENSORS
-- =======================================================================

-- 6.1 Activity Quad Rings (1x1 Minimal)
local function draw_rings_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local cpu_frac = read_pct("${cpu cpu0}")
    local ram_frac = read_pct("${memperc}")
    local bat_val = tonumber(conky_parse("${battery_percent BAT1}")) or 100
    local bat_frac = bat_val / 100
    local temp_c = tonumber(conky_parse(HWMON_TEMP_VAR)) or 52
    local temp_frac = math.min(1.0, temp_c / 100.0)

    local r = 18.0
    local th = 4.0
    local cx_l = card_x + 44
    local cx_r = card_x + card_w - 44
    local cy_t = card_y + 42
    local cy_b = card_y + card_h - 42

    local function draw_sensor_disc(cx, cy, frac, color, icon_fn)
        cairo_new_path(cr)
        cairo_arc(cr, cx, cy, 24, 0, 2 * math.pi)
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.05)
        cairo_fill(cr)

        draw_arc_ring(cr, cx, cy, r, th, math.max(0.04, frac), color)
        icon_fn(cr, cx, cy, 12, color)
    end

    -- CPU (Coral)
    draw_sensor_disc(cx_l, cy_t, cpu_frac, CORAL_RED, draw_vec_chip)

    -- RAM (Green)
    draw_sensor_disc(cx_r, cy_t, ram_frac, GREEN_HOME, draw_vec_ram)

    -- Battery (Blue)
    draw_sensor_disc(cx_l, cy_b, bat_frac, BLUE_ROOT, draw_vec_battery)

    -- Temp (Amber)
    draw_sensor_disc(cx_r, cy_b, temp_frac, AMBER_CPU, draw_vec_temp)
end

-- 6.2 Hardware Sensor Hub (1x1 Detailed)
local function draw_rings_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local cpu_val = conky_parse("${cpu cpu0}")
    local cpu_frac = read_pct("${cpu cpu0}")
    local ram_val = conky_parse("${memperc}")
    local ram_frac = read_pct("${memperc}")
    local bat_val = conky_parse("${battery_percent BAT1}")
    if bat_val == "" or bat_val == nil then bat_val = "100" end
    local bat_frac = (tonumber(bat_val) or 100) / 100
    local temp_val = conky_parse(HWMON_TEMP_VAR)
    if temp_val == "" or temp_val == nil then temp_val = "52" end
    local temp_frac = math.min(1.0, (tonumber(temp_val) or 52) / 100.0)

    local r = 21.0
    local th = 4.5
    local cx_l = card_x + 44
    local cx_r = card_x + card_w - 44
    local cy_t = card_y + 44
    local cy_b = card_y + card_h - 44

    -- Top Left: CPU
    draw_arc_ring(cr, cx_l, cy_t, r, th, cpu_frac, CORAL_RED)
    draw_text(cr, cpu_val, cx_l, cy_t + 1, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    draw_text(cr, "CPU", cx_l, cy_t + 13, 7.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'center')

    -- Top Right: RAM
    draw_arc_ring(cr, cx_r, cy_t, r, th, ram_frac, GREEN_HOME)
    draw_text(cr, ram_val, cx_r, cy_t + 1, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    draw_text(cr, "RAM", cx_r, cy_t + 13, 7.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'center')

    -- Bottom Left: BAT
    draw_arc_ring(cr, cx_l, cy_b, r, th, bat_frac, BLUE_ROOT)
    draw_text(cr, bat_val, cx_l, cy_b + 1, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    draw_text(cr, "BAT", cx_l, cy_b + 13, 7.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'center')

    -- Bottom Right: TEMP
    draw_arc_ring(cr, cx_r, cy_b, r, th, temp_frac, AMBER_CPU)
    draw_text(cr, temp_val .. "°", cx_r, cy_b + 1, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    draw_text(cr, "TEMP", cx_r, cy_b + 13, 7.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'center')
end

-- 6.3 System Horizon (2x1 Wide)
local function draw_rings_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local cpu_str = conky_parse("${cpu cpu0}") .. "%"
    local ram_str = conky_parse("${memperc}") .. "%"
    local bat_str = (conky_parse("${battery_percent BAT1}") or "100") .. "%"
    local temp_str = (conky_parse(HWMON_TEMP_VAR) or "52") .. "°C"

    local cpu_frac = read_pct("${cpu cpu0}")
    local ram_frac = read_pct("${memperc}")
    local bat_frac = (tonumber(conky_parse("${battery_percent BAT1}")) or 100) / 100
    local temp_frac = math.min(1.0, (tonumber(conky_parse(HWMON_TEMP_VAR)) or 52) / 100.0)

    local sensors = {
        { pct = cpu_str, frac = cpu_frac, color = CORAL_RED, type = "chip" },
        { pct = ram_str, frac = ram_frac, color = GREEN_HOME, type = "ram" },
        { pct = bat_str, frac = bat_frac, color = BLUE_ROOT,  type = "battery" },
        { pct = temp_str, frac = temp_frac, color = AMBER_CPU, type = "temp" }
    }

    local col_w = card_w / 4
    local cy = card_y + 44
    local r = 24

    for i, s in ipairs(sensors) do
        local cx = card_x + (i - 0.5) * col_w
        draw_arc_ring(cr, cx, cy, r, 5.0, s.frac, s.color)

        if s.type == "chip" then draw_vec_chip(cr, cx, cy, 14, s.color)
        elseif s.type == "ram" then draw_vec_ram(cr, cx, cy, 14, s.color)
        elseif s.type == "battery" then draw_vec_battery(cr, cx, cy, 14, s.color)
        else draw_vec_temp(cr, cx, cy, 14, s.color) end

        draw_text(cr, s.pct, cx, card_y + 92, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
    end
end

-- =======================================================================
-- MODULE FAMILY 7: WEATHER FORECAST
-- =======================================================================

-- 7.1 Weather Squircle (1x1 Minimal)
local function draw_weather_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local city = TELEMETRY.weather.city or "Mumbai"
    local temp = TELEMETRY.weather.temp or "29°C"
    local desc = TELEMETRY.weather.desc or "Fair"
    local icon = TELEMETRY.weather.icon or "󰖙"

    local icon_color = AMBER_CPU
    local d_low = (desc or ""):lower()
    if d_low:find("rain") or d_low:find("drizzle") or d_low:find("shower") then
        icon_color = BLUE_ROOT
    elseif d_low:find("thunder") then
        icon_color = CORAL_RED
    elseif d_low:find("cloud") or d_low:find("overcast") or d_low:find("haze") or d_low:find("smoke") or d_low:find("fog") then
        icon_color = TEXT_MUTED
    elseif d_low:find("snow") then
        icon_color = { r = 0.85, g = 0.92, b = 1.0, a = 1.0 }
    end

    draw_text(cr, city, card_x + 18, card_y + 26, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'left')
    draw_icon(cr, icon, card_x + card_w - 18, card_y + 32, 24, icon_color, 'right')

    draw_text(cr, temp, card_x + 18, card_y + 72, 32, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, desc, card_x + 18, card_y + 98, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, "WEATHER", card_x + 18, card_y + 130, 8, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'left')
end

-- 7.2 Meteorology Station (1x1 Detailed)
local function draw_weather_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local city  = TELEMETRY.weather.city or "Mumbai"
    local temp  = TELEMETRY.weather.temp or "29°C"
    local desc  = TELEMETRY.weather.desc or "Fair"
    local feels = TELEMETRY.weather.feels or "31°C"
    local hum   = TELEMETRY.weather.hum or "65%"

    draw_text(cr, city, card_x + 18, card_y + 24, 10, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'left')
    draw_text(cr, temp, card_x + 18, card_y + 56, 26, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, desc, card_x + 18, card_y + 74, 10, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    draw_pill(cr, card_x + 18, card_y + 86, card_w - 36, 22, 6, { r = 1, g = 1, b = 1, a = 0.06 })
    draw_text(cr, "Feels " .. feels .. " · Hum " .. hum, card_x + card_w / 2, card_y + 100, 8.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')

    draw_pill(cr, card_x + 18, card_y + 114, card_w - 36, 22, 6, { r = 1, g = 1, b = 1, a = 0.06 })
    draw_text(cr, "Wind 14 km/h · H: 32° L: 24°", card_x + card_w / 2, card_y + 128, 8.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'center')
end

-- 7.3 Forecast Panorama (2x1 Wide)
local function draw_weather_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local city  = TELEMETRY.weather.city or "Mumbai"
    local temp  = TELEMETRY.weather.temp or "29°C"
    local desc  = TELEMETRY.weather.desc or "Fair"
    local feels = TELEMETRY.weather.feels or "31°C"

    -- Left: Current
    draw_text(cr, city, card_x + 22, card_y + 26, 10, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'left')
    draw_text(cr, temp, card_x + 20, card_y + 60, 30, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, desc .. " · Feels " .. feels, card_x + 22, card_y + 80, 9.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_PRIMARY, 'left')

    -- Right: 4-day Forecast
    local days = { "Mon", "Tue", "Wed", "Thu" }
    local temps = { "30°/24°", "29°/23°", "31°/25°", "28°/22°" }
    local icons = { "󰖙", "󰖕", "󰖙", "󰖖" }

    local f_start_x = card_x + 160
    local f_w = (card_w - 176) / 4

    for i = 1, 4 do
        local fx = f_start_x + (i - 0.5) * f_w
        draw_text(cr, days[i], fx, card_y + 36, 9, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
        draw_icon(cr, icons[i], fx, card_y + 58, 16, AMBER_CPU, 'center')
        draw_text(cr, temps[i], fx, card_y + 80, 8, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'center')
    end
end

-- =======================================================================
-- MODULE FAMILY 8: DAILY INSPIRATION (RENAMED FROM QUOTE)
-- =======================================================================

-- 8.1 Inspiration Spark (1x1 Minimal)
local function draw_quote_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local q_author = TELEMETRY.quote.author or "Austin Freeman"

    draw_text(cr, "“", card_x + 18, card_y + 36, 32, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, "Simplicity is the", card_x + 18, card_y + 60, 10.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, "soul of efficiency.", card_x + 18, card_y + 76, 10.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')

    draw_text(cr, "— " .. q_author, card_x + 18, card_y + 114, 9, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
end

-- 8.2 Philosophical Insight (1x1 Detailed)
local function draw_quote_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local q_tag = TELEMETRY.quote.tag or "WISDOM"
    local q_author = TELEMETRY.quote.author or "Marcus Aurelius"

    draw_pill(cr, card_x + 18, card_y + 16, 68, 18, 9, { r = 1, g = 1, b = 1, a = 0.08 })
    draw_text(cr, string.upper(q_tag), card_x + 52, card_y + 28, 7.5, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'center')

    draw_text(cr, "Peace begins when", card_x + 18, card_y + 62, 10.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_PRIMARY, 'left')
    draw_text(cr, "you accept things", card_x + 18, card_y + 78, 10.5, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'left')
    draw_text(cr, "as they are.", card_x + 18, card_y + 94, 10.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_PRIMARY, 'left')

    draw_text(cr, "— " .. q_author, card_x + 18, card_y + 128, 9, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'left')
end

-- 8.3 Wisdom Banner (2x1 Wide)
local function draw_quote_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local q_author = TELEMETRY.quote.author or "Austin Freeman"

    -- Signature coral red vertical accent bar
    draw_pill(cr, card_x + 22, card_y + 24, 3.5, card_h - 48, 1.75, CORAL_RED)

    draw_text(cr, "“", card_x + 36, card_y + 40, 32, CAIRO_FONT_WEIGHT_BOLD, AMBER_CPU, 'left')
    draw_text(cr, "Peace begins when you accept things as they are.", card_x + 58, card_y + 36, 11, CAIRO_FONT_WEIGHT_NORMAL, TEXT_PRIMARY, 'left')
    draw_text(cr, "Stability quietly fuels sustainable growth.", card_x + 58, card_y + 54, 11, CAIRO_FONT_WEIGHT_BOLD, AMBER_CPU, 'left')

    draw_text(cr, "DAILY INSPIRATION", card_x + 36, card_y + 86, 8, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'left')
    draw_text(cr, "— " .. q_author, card_x + card_w - 24, card_y + 86, 8.5, CAIRO_FONT_WEIGHT_BOLD, CORAL_RED, 'right')
end

-- =======================================================================
-- MODULE FAMILY 9: NOW PLAYING (MEDIA PLAYER)
-- =======================================================================

-- 9.1 Album Spotlight (1x1 Minimal)
local function draw_media_1x1_minimal(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local is_playing = TELEMETRY.media.is_playing
    local title = TELEMETRY.media.title or "No Track"
    local artist = TELEMETRY.media.artist or "Weget Audio"

    -- Album art / Disc squircle (Top-Left)
    local ax = card_x + 18
    local ay = card_y + 18
    local asize = 48
    draw_sub_card(cr, ax, ay, asize, asize, 12)
    draw_icon(cr, "󰝚", ax + asize / 2, ay + asize / 2 + 5, 22, PURPLE_MEDIA, 'center')

    -- Apple Music Logo (Top-Right)
    draw_icon(cr, "󰝚", card_x + card_w - 24, card_y + 32, 16, TEXT_PRIMARY, 'center')

    -- Title & Artist (Middle)
    draw_text(cr, title, card_x + 18, card_y + 86, 12, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, artist, card_x + 18, card_y + 102, 9.5, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')

    -- Floating Apple ▶ Play / ⏸ Pause Pill Button (Bottom)
    local btn_x = card_x + 18
    local btn_y = card_y + 112
    local btn_w = 82
    local btn_h = 28
    CLICK_ZONES["play"] = { x = btn_x, y = btn_y, w = btn_w, h = btn_h }
    draw_pill(cr, btn_x, btn_y, btn_w, btn_h, 14, { r = 1, g = 1, b = 1, a = 0.20 })
    draw_icon(cr, is_playing and "󰏤" or "󰐊", btn_x + 18, btn_y + 18, 12, TEXT_PRIMARY, 'center')
    draw_text(cr, is_playing and "Pause" or "Play", btn_x + 46, btn_y + 18, 10.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')
end

-- 9.2 Track Controller (1x1 Detailed)
local function draw_media_1x1_detailed(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local is_playing = TELEMETRY.media.is_playing
    local title = TELEMETRY.media.title or "No Track"
    local artist = TELEMETRY.media.artist or "Weget Audio Engine"
    local p_frac = TELEMETRY.media.progress or 0.0

    draw_text(cr, title, card_x + 18, card_y + 26, 11, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, artist, card_x + 18, card_y + 40, 9, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')

    -- Scrubber bar
    local bar_w = card_w - 36
    draw_pill(cr, card_x + 18, card_y + 54, bar_w, 4, 2, { r = 1, g = 1, b = 1, a = 0.12 })
    draw_pill(cr, card_x + 18, card_y + 54, math.max(6, bar_w * p_frac), 4, 2, PURPLE_MEDIA)

    -- Playback controls
    local ctrl_y = card_y + 76
    CLICK_ZONES["prev"] = { x = card_x + 18, y = ctrl_y, w = 36, h = 32 }
    CLICK_ZONES["play"] = { x = card_x + card_w / 2 - 18, y = ctrl_y, w = 36, h = 32 }
    CLICK_ZONES["next"] = { x = card_x + card_w - 54, y = ctrl_y, w = 36, h = 32 }

    -- Prev
    draw_pill(cr, card_x + 18, ctrl_y, 36, 32, 10, { r = 1, g = 1, b = 1, a = 0.08 })
    draw_icon(cr, "󰒮", card_x + 36, ctrl_y + 20, 13, TEXT_PRIMARY, 'center')

    -- Play/Pause
    draw_pill(cr, card_x + card_w / 2 - 18, ctrl_y, 36, 32, 10, PURPLE_MEDIA)
    draw_icon(cr, is_playing and "󰏤" or "󰐊", card_x + card_w / 2, ctrl_y + 20, 14, { r = 1, g = 1, b = 1 }, 'center')

    -- Next
    draw_pill(cr, card_x + card_w - 54, ctrl_y, 36, 32, 10, { r = 1, g = 1, b = 1, a = 0.08 })
    draw_icon(cr, "󰒭", card_x + card_w - 36, ctrl_y + 20, 13, TEXT_PRIMARY, 'center')

    draw_text(cr, "NOW PLAYING", card_x + card_w / 2, card_y + 134, 8, CAIRO_FONT_WEIGHT_BOLD, TEXT_MUTED, 'center')
end

-- 9.3 Studio Master Deck (2x1 Wide)
local function draw_media_2x1_wide(cr, card_x, card_y, card_w, card_h)
    draw_card(cr, card_x, card_y, card_w, card_h)

    local is_playing = TELEMETRY.media.is_playing
    local title = TELEMETRY.media.title or "No Media Playing"
    local artist = TELEMETRY.media.artist or "Weget Audio Engine"
    local p_time = TELEMETRY.media.time or "00:00 / 00:00"
    if p_time == "--:--" then p_time = "00:00 / 00:00" end
    local p_frac = TELEMETRY.media.progress or 0.0

    -- Album art / Disc square (Left)
    local ax = card_x + 18
    local ay = card_y + 18
    local asize = 52
    draw_sub_card(cr, ax, ay, asize, asize, 12)
    draw_icon(cr, "󰝚", ax + asize / 2, ay + asize / 2 + 5, 24, PURPLE_MEDIA, 'center')

    -- Top-Right Music glyph
    draw_icon(cr, "󰝚", card_x + card_w - 24, card_y + 30, 16, TEXT_MUTED, 'center')

    -- Title & Artist (Beside album art)
    local text_x = card_x + 82
    draw_text(cr, title, text_x, card_y + 32, 12.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'left')
    draw_text(cr, artist, text_x, card_y + 48, 10, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'left')

    -- Scrubber bar
    local bar_x = text_x
    local bar_w = card_w - 110
    local bar_y = card_y + 64
    draw_pill(cr, bar_x, bar_y, bar_w, 4, 2.0, { r = 1, g = 1, b = 1, a = 0.12 })
    if p_frac > 0.005 then
        draw_pill(cr, bar_x, bar_y, math.max(6, bar_w * p_frac), 4, 2.0, PURPLE_MEDIA)
    end

    -- Bottom controls: Apple ▶ Play capsule + prev/next
    local btn_y = card_y + 76
    local play_w = 80
    local btn_h = 28

    CLICK_ZONES["play"] = { x = text_x, y = btn_y, w = play_w, h = btn_h }
    draw_pill(cr, text_x, btn_y, play_w, btn_h, 14, { r = 1, g = 1, b = 1, a = 0.20 })
    draw_icon(cr, is_playing and "󰏤" or "󰐊", text_x + 18, btn_y + 18, 12, TEXT_PRIMARY, 'center')
    draw_text(cr, is_playing and "Pause" or "Play", text_x + 46, btn_y + 18, 10.5, CAIRO_FONT_WEIGHT_BOLD, TEXT_PRIMARY, 'center')

    -- Prev & Next
    local prev_x = text_x + play_w + 10
    CLICK_ZONES["prev"] = { x = prev_x, y = btn_y, w = 32, h = btn_h }
    draw_pill(cr, prev_x, btn_y, 32, btn_h, 14, { r = 1, g = 1, b = 1, a = 0.10 })
    draw_icon(cr, "󰒮", prev_x + 16, btn_y + 19, 12, TEXT_PRIMARY, 'center')

    local next_x = prev_x + 40
    CLICK_ZONES["next"] = { x = next_x, y = btn_y, w = 32, h = btn_h }
    draw_pill(cr, next_x, btn_y, 32, btn_h, 14, { r = 1, g = 1, b = 1, a = 0.10 })
    draw_icon(cr, "󰒭", next_x + 16, btn_y + 19, 12, TEXT_PRIMARY, 'center')

    -- Time readout
    draw_text(cr, p_time, card_x + card_w - 20, card_y + 94, 9, CAIRO_FONT_WEIGHT_NORMAL, TEXT_MUTED, 'right')
end

-- =======================================================================
-- MAPPING TABLE & DISPATCHER
-- =======================================================================
local MODULE_REGISTRY = {
    -- 1. Network Monitor
    NETW_1x1_MIN = { fn = draw_network_1x1_minimal,  h = 152, is1x1 = true },
    NETW_1x1_DET = { fn = draw_network_1x1_detailed, h = 152, is1x1 = true },
    NETW_2x1_WID = { fn = draw_network_2x1_wide,     h = 138, is1x1 = false },

    -- 2. Calendar & Agenda
    CALN_1x1_MIN = { fn = draw_calendar_1x1_minimal,  h = 152, is1x1 = true },
    CALN_1x1_DET = { fn = draw_calendar_1x1_detailed, h = 152, is1x1 = true },
    CALN_2x1_WID = { fn = draw_calendar_2x1_wide,     h = 168, is1x1 = false },

    -- 3. Analog Clock
    CLKA_1x1_MIN = { fn = draw_analogue_clock_1x1_minimal,  h = 152, is1x1 = true },
    CLKA_1x1_DET = { fn = draw_analogue_clock_1x1_detailed, h = 152, is1x1 = true },
    CLKA_2x1_WID = { fn = draw_analogue_clock_2x1_wide,     h = 120, is1x1 = false },

    -- 4. Digital Clock
    CLKD_1x1_MIN = { fn = draw_digital_clock_1x1_minimal,  h = 152, is1x1 = true },
    CLKD_1x1_DET = { fn = draw_digital_clock_1x1_detailed, h = 152, is1x1 = true },
    CLKD_2x1_WID = { fn = draw_digital_clock_2x1_wide,     h = 118, is1x1 = false },

    -- 5. Disk Storage
    STOR_1x1_MIN = { fn = draw_storage_1x1_minimal,  h = 152, is1x1 = true },
    STOR_1x1_DET = { fn = draw_storage_1x1_detailed, h = 152, is1x1 = true },
    STOR_2x1_WID = { fn = draw_storage_2x1_wide,     h = 122, is1x1 = false },

    -- 6. System Sensors
    RING_1x1_MIN = { fn = draw_rings_1x1_minimal,  h = 152, is1x1 = true },
    RING_1x1_DET = { fn = draw_rings_1x1_detailed, h = 152, is1x1 = true },
    RING_2x1_WID = { fn = draw_rings_2x1_wide,     h = 118, is1x1 = false },

    -- 7. Weather Forecast
    WEAT_1x1_MIN = { fn = draw_weather_1x1_minimal,  h = 152, is1x1 = true },
    WEAT_1x1_DET = { fn = draw_weather_1x1_detailed, h = 152, is1x1 = true },
    WEAT_2x1_WID = { fn = draw_weather_2x1_wide,     h = 118, is1x1 = false },

    -- 8. Daily Inspiration
    QUOT_1x1_MIN = { fn = draw_quote_1x1_minimal,  h = 152, is1x1 = true },
    QUOT_1x1_DET = { fn = draw_quote_1x1_detailed, h = 152, is1x1 = true },
    QUOT_2x1_WID = { fn = draw_quote_2x1_wide,     h = 104, is1x1 = false },

    -- 9. Now Playing
    MEDI_1x1_MIN = { fn = draw_media_1x1_minimal,  h = 152, is1x1 = true },
    MEDI_1x1_DET = { fn = draw_media_1x1_detailed, h = 152, is1x1 = true },
    MEDI_2x1_WID = { fn = draw_media_2x1_wide,     h = 118, is1x1 = false },

    -- Backwards compatibility aliases
    TIME_2x1_A01 = { fn = draw_calendar_2x1_wide,     h = 168, is1x1 = false },
    TIME         = { fn = draw_calendar_2x1_wide,     h = 168, is1x1 = false },
    WEAT_1x1_W01 = { fn = draw_weather_1x1_minimal,  h = 152, is1x1 = true },
    WEATHER      = { fn = draw_weather_1x1_minimal,  h = 152, is1x1 = true },
    SYST_1x1_S01 = { fn = draw_rings_1x1_minimal,    h = 152, is1x1 = true },
    SYSTEM       = { fn = draw_rings_1x1_minimal,    h = 152, is1x1 = true },
    SYST_2x1_S03 = { fn = draw_rings_2x1_wide,       h = 118, is1x1 = false },
    NETW_2x1_N01 = { fn = draw_network_2x1_wide,     h = 138, is1x1 = false },
    NETWORK      = { fn = draw_network_2x1_wide,     h = 138, is1x1 = false },
    MEDI_2x1_M01 = { fn = draw_media_2x1_wide,       h = 118, is1x1 = false },
    MEDIA        = { fn = draw_media_2x1_wide,       h = 118, is1x1 = false },
    QUOT_2x1_Q01 = { fn = draw_quote_2x1_wide,       h = 104, is1x1 = false },
    QUOTE        = { fn = draw_quote_2x1_wide,       h = 104, is1x1 = false },
}

local function is_1x1(mod_id)
    if not mod_id or mod_id == "EMPTY" or mod_id == "" then return false end
    local entry = MODULE_REGISTRY[mod_id]
    if entry then return entry.is1x1 end
    return mod_id:find("_1x1_") ~= nil
end

local function dispatch_module(cr, mod_id, x, y, w, h)
    if mod_id == nil or mod_id == "EMPTY" or mod_id == "" then
        return 0
    end
    local entry = MODULE_REGISTRY[mod_id]
    if entry then
        local target_h = (h > 0) and h or entry.h
        entry.fn(cr, x, y, w, target_h)
        return target_h + 14
    end
    return 0
end

-- -----------------------------------------------------------------------
-- Dynamic Row Dispatcher
-- -----------------------------------------------------------------------
local function render_row_pair(cr, m1, m2, cur_y)
    local act1 = (m1 and m1 ~= "EMPTY" and m1 ~= "")
    local act2 = (m2 and m2 ~= "EMPTY" and m2 ~= "")

    if not act1 and not act2 then
        return 0
    end

    if act1 and act2 and is_1x1(m1) and is_1x1(m2) then
        -- Side-by-side Squircles
        local sq_w = 168
        local sq_h = 152
        dispatch_module(cr, m1, 0, cur_y, sq_w, sq_h)
        dispatch_module(cr, m2, 182, cur_y, sq_w, sq_h)
        return sq_h + 14
    elseif act1 and not act2 then
        local w = is_1x1(m1) and 168 or LOGICAL_W
        local h = is_1x1(m1) and 152 or 0
        local x = is_1x1(m1) and math.floor((LOGICAL_W - 168) / 2) or 0
        return dispatch_module(cr, m1, x, cur_y, w, h)
    elseif act2 and not act1 then
        local w = is_1x1(m2) and 168 or LOGICAL_W
        local h = is_1x1(m2) and 152 or 0
        local x = is_1x1(m2) and math.floor((LOGICAL_W - 168) / 2) or 0
        return dispatch_module(cr, m2, x, cur_y, w, h)
    else
        -- Both active but at least one is 2x1 wide: render vertically
        local h1 = dispatch_module(cr, m1, 0, cur_y, LOGICAL_W, 0)
        local h2 = dispatch_module(cr, m2, 0, cur_y + h1, LOGICAL_W, 0)
        return h1 + h2
    end
end

-- -----------------------------------------------------------------------
-- Mouse Click Event Handler
-- -----------------------------------------------------------------------
function conky_mouse_event(event)
    if not event then return end
    local x = event.x or 0
    local y = event.y or 0
    local scale = SETTINGS.scale or 1.0

    local lx = x / scale
    local ly = y / scale

    local helper_cmd = (function()
        local home = os.getenv("HOME") or ""
        local candidates = {
            home .. "/.config/conky/macwidget/helpers/media.py",
            home .. "/.local/share/weget/helpers/media.py",
            "/usr/share/weget/helpers/media.py",
            "helpers/media.py"
        }
        for _, c in ipairs(candidates) do
            local f = io.open(c, "r")
            if f then f:close(); return "python3 " .. c end
        end
        return "playerctl"
    end)()

    for action, box in pairs(CLICK_ZONES) do
        if lx >= box.x and lx <= (box.x + box.w) and ly >= box.y and ly <= (box.y + box.h) then
            if action == "prev" then
                os.execute(helper_cmd .. " prev &")
            elseif action == "play" then
                os.execute(helper_cmd .. " play-pause &")
            elseif action == "next" then
                os.execute(helper_cmd .. " next &")
            end
            break
        end
    end
end

-- -----------------------------------------------------------------------
-- Main Conky Render Hook
-- -----------------------------------------------------------------------
function conky_draw_widgets()
    if conky_window == nil then return end
    if (tonumber(conky_parse('${updates}')) or 0) < 1 then return end

    check_hot_reload()
    update_telemetry()

    local user_scale = SETTINGS.scale or 1.0
    local base_scale = math.floor(conky_window.width / LOGICAL_W + 0.5)
    if base_scale < 1 then base_scale = 1 end
    local effective_scale = base_scale * user_scale

    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable, conky_window.visual,
        conky_window.width, conky_window.height)
    cairo_surface_set_device_scale(cs, effective_scale, effective_scale)

    local cr = cairo_create(cs)
    local cur_y = 0

    local slots = SETTINGS.slots or {}

    -- Row A (A1 & A2)
    cur_y = cur_y + render_row_pair(cr, slots.A1, slots.A2, cur_y)

    -- Row B (B1 & B2)
    cur_y = cur_y + render_row_pair(cr, slots.B1, slots.B2, cur_y)

    -- Row C (C1 & C2)
    cur_y = cur_y + render_row_pair(cr, slots.C1, slots.C2, cur_y)

    -- Row D (D1 & D2)
    cur_y = cur_y + render_row_pair(cr, slots.D1, slots.D2, cur_y)

    cairo_surface_flush(cs)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
