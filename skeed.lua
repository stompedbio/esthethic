-- skeed
-- Tabs: HVH Config, HVH Extras, HVH More, HVH ESP, HVH Plus, Chat, Helper
-- Network use: only the Chat tab, and only to the Server URL you type in.
-- No loadstring, no obfuscation. Everything is reset when the script unloads.

local ICON = "rbxassetid://10734975692"

-- THEMES
local C = Color3.fromRGB
local THEMES = {
    Default = { accent = C(0,255,160),  accent2 = C(240,60,70),   good = C(120,255,120), bad = C(255,100,100), warn = C(255,200,60), text = C(255,255,255), sub = C(200,200,200), panel = C(20,22,30), header = C(70,130,240),  target = C(255,40,40) },
    Ocean   = { accent = C(80,220,255), accent2 = C(60,140,255),  good = C(110,255,210), bad = C(255,110,130), warn = C(255,210,120), text = C(235,248,255), sub = C(160,190,210), panel = C(12,24,38), header = C(30,120,200),  target = C(80,220,255) },
    Sunset  = { accent = C(255,150,70), accent2 = C(255,80,110),  good = C(255,220,120), bad = C(255,90,90),   warn = C(255,190,80), text = C(255,244,235), sub = C(210,180,170), panel = C(32,18,24), header = C(220,90,70),   target = C(255,110,70) },
    Purple  = { accent = C(190,120,255),accent2 = C(255,110,220), good = C(160,255,200), bad = C(255,100,140), warn = C(255,210,120), text = C(245,238,255), sub = C(185,170,210), panel = C(24,18,36), header = C(120,70,220),  target = C(210,120,255) },
    Rose    = { accent = C(255,120,170),accent2 = C(255,170,200), good = C(170,255,190), bad = C(255,90,110),  warn = C(255,205,130), text = C(255,240,245), sub = C(210,175,190), panel = C(34,18,26), header = C(220,70,130),  target = C(255,100,150) },
    Mono    = { accent = C(235,235,235),accent2 = C(160,160,160), good = C(220,220,220), bad = C(150,150,150), warn = C(200,200,200), text = C(255,255,255), sub = C(150,150,150), panel = C(16,16,18), header = C(70,70,76),    target = C(235,235,235) },
}
-- Rainbow animates its accents; Custom is rebuilt from a colorpicker
THEMES.Rainbow, THEMES.Custom = {}, {}
for k, v in pairs(THEMES.Default) do THEMES.Rainbow[k] = v; THEMES.Custom[k] = v end

local theme, themeHooks, currentTheme = {}, {}, "Default"
local function runThemeHooks()
    for _, fn in ipairs(themeHooks) do pcall(fn) end
end
local function applyTheme(name)
    local src = THEMES[name]
    if not src then return end
    currentTheme = name
    for k, v in pairs(src) do theme[k] = v end
    runThemeHooks()
end
applyTheme("Default")

-- Safety helpers: an error in any callback pops up as a notification
-- and is written to the Lua console (once per unique error)
local reportedErrors, toastCount = {}, 0
local function reportError(where, err)
    local msg = tostring(err)
    local key = where .. msg
    if reportedErrors[key] then return end
    reportedErrors[key] = true
    pcall(function() client.error(string.format("[%s] %s", where, msg)) end)
    if toastCount < 4 then
        toastCount += 1
        pcall(function() notify("Script error in " .. where, string.sub(msg, 1, 140), 8, false) end)
    end
end

local function guard(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then reportError(where, err) end
    end
end

-- shot events arrive either as one table or as positional arguments
local function normShot(name, a, b, c)
    if type(a) == "table" then return a end
    local e = { target = a, hitbox = b }
    if name == "aim_miss" then
        if type(c) == "string" then e.reason = c
        elseif type(b) == "string" then e.reason = b end
    else
        e.damage = c
    end
    return e
end

local tickCount = 0
local function onTick(fn)
    tickCount += 1
    return events.on_tick(guard("tick #" .. tickCount, fn))
end

local function onEvent(name, fn)
    if name == "aim_fire" or name == "aim_hit" or name == "aim_miss" then
        return client.set_event_callback(name, guard(name, function(a, b, c)
            fn(normShot(name, a, b, c))
        end))
    end
    return client.set_event_callback(name, guard(name, fn))
end

-- per-enemy key: UserId for players, and slot numbers are mapped to a UserId
-- once the ragebot has shown us which slot belongs to which player
local slotMap = {}
local function keyOf(x)
    if type(x) == "number" then return slotMap[x] or x end
    local ok, id = pcall(function() return x.UserId end)
    if ok and id then return id end
    return x
end

local function learnSlot()
    local t = curTarget()
    if type(t) ~= "table" or t.slot == nil or t.player == nil then return end
    local ok2, id = pcall(function() return t.player.UserId end)
    if ok2 and id then slotMap[t.slot] = id end
end


-- PERFORMANCE HELPERS
-- perf.rate is the HUD refresh interval (seconds), set from HVH Plus > Performance
local perf = { rate = 0.1 }

-- rage.get_target() is asked for by several callbacks per frame: ask once per ~30 ms
local _tgt, _tgtAt = nil, -1
local function curTarget()
    local now = globals.realtime()
    if now - _tgtAt > 0.03 then
        local ok, t = pcall(rage.get_target)
        _tgt = ok and t or nil
        _tgtAt = now
    end
    return _tgt
end

-- text that is rebuilt at most every perf.rate seconds instead of every frame
local fmtCache = {}
local function cached(id, fn)
    local now = globals.realtime()
    local c = fmtCache[id]
    if not c or now - c.t > perf.rate then
        c = { t = now, v = fn() }
        fmtCache[id] = c
    end
    return c.v
end

-- plist.set that skips writes whose value has not changed (refreshed once a second)
local psetCache, psetAt = {}, 0
local function pset(enemy, key, val)
    local now = globals.realtime()
    if now - psetAt > 1 then psetCache, psetAt = {}, now end
    local id = keyOf(enemy)
    local c = psetCache[id]
    if not c then c = {}; psetCache[id] = c end
    if c[key] ~= val then
        c[key] = val
        plist.set(enemy, key, val)
    end
end
local function psetClear() psetCache = {} end

-- MENU
local tab = menu.new_tab("HVH Config", ICON)

local aa_sec   = tab:new_section("Anti-Aim", "Left")
local res_sec  = tab:new_section("Resolver", "Right")
local rage_sec = tab:new_section("Ragebot", "Left")
local vis_sec  = tab:new_section("Visuals", "Right")
local misc_sec = tab:new_section("Misc", "Left")

-- Anti-aim
local aa_enable   = aa_sec:new_toggle("Enable Anti-Aim", true)
local aa_pitch    = aa_sec:new_combobox("Pitch", { "Down", "Up", "Zero", "Disabled" }, "Down")
local aa_yaw      = aa_sec:new_slider("Yaw Offset", -180, 180, 180, 0, "°")
local aa_mod      = aa_sec:new_combobox("Yaw Modifier", { "Disabled", "Sway", "Spin", "Random", "Center", "3-Way", "5-Way" }, "Sway")
local aa_sway_amt = aa_sec:new_slider("Sway Amount", 0, 90, 35, 0, "°")
local aa_desync   = aa_sec:new_slider("Desync Limit", 0, 86, 58, 0, "°")
local aa_invert   = aa_sec:new_keybind("Invert Side", "Toggle", "F")
local aa_lag      = aa_sec:new_slider("Fake Lag", 0, 14, 8, 0, "t")
local aa_lag_var  = aa_sec:new_slider("Lag Variability", 0, 100, 20, 0, "%")

-- Resolver
local res_enable  = res_sec:new_toggle("Lua Resolver", true)
local res_mode    = res_sec:new_combobox("Mode", { "Brute-force", "Adaptive", "Freestanding" }, "Brute-force")
local res_baim    = res_sec:new_slider("BAim After Misses", 0, 5, 2, 0, " misses")
local res_miss    = res_sec:new_slider("Miss Limit", 1, 5, 2, 0, " shots")

-- Ragebot
local rb_enable   = rage_sec:new_toggle("Override Ragebot", true)
local rb_dmg      = rage_sec:new_slider("Min Damage", 1, 100, 40, 0, " hp")
local rb_hc       = rage_sec:new_slider("Hitchance", 1, 100, 65, 0, "%")
local rb_target   = rage_sec:new_combobox("Target Selection", { "Highest damage", "Near crosshair", "Best hitchance", "Cycle" }, "Highest damage")
local rb_baim_key = rage_sec:new_keybind("Force Body Aim", "Hold", "Z")
local rb_safe_key = rage_sec:new_keybind("Force Safe Point", "Hold", "X")

-- Visuals
local v_chams     = vis_sec:new_toggle("Enemy Chams", true)
local v_chams_mat = vis_sec:new_combobox("Material", chams.get_materials(), "Neon")
local v_vis_col   = vis_sec:new_colorpicker("Visible Color", Color3.fromRGB(80, 220, 255))
local v_hid_col   = vis_sec:new_colorpicker("Occluded Color", Color3.fromRGB(255, 60, 60))
local v_hud       = vis_sec:new_toggle("Debug HUD", true)
local v_target3d  = vis_sec:new_toggle("3D Target Box", true)

-- Misc
local m_hitsound  = misc_sec:new_combobox("Hitsound", sounds.get_hitsound_names(), "skeet")
local m_killsound = misc_sec:new_combobox("Killsound", sounds.get_hitsound_names(), "fatality")
local m_clantag   = misc_sec:new_toggle("Clantag", false)
local m_tag_text  = misc_sec:new_textbox("Clantag Text", "skeed", "skeed")
local m_tag_anim  = misc_sec:new_combobox("Clantag Anim", { "Static", "Marquee", "Typewriter" }, "Marquee")
local m_killsay   = misc_sec:new_toggle("Kill Say", false)
local m_hs_id     = misc_sec:new_textbox("Custom Hitsound ID", "Roblox asset ID (optional)", "")
local m_hs_vol    = misc_sec:new_slider("Hitsound Volume", 0, 300, 100, 0, "%")
local m_hs_pitch  = misc_sec:new_slider("Hitsound Pitch", 50, 200, 100, 0, "%")

-- ANTI-AIM
local aaWas, aaSig, swayFn, swayAmt = false, nil, nil, nil
onTick(function(tick)
    if not aa_enable:get() then
        if aaWas then aa.reset(); aaWas = false; aaSig = nil end
        return
    end
    aaWas = true

    -- unchanged settings are only re-sent every 12 ticks
    local sig = table.concat({
        tostring(aa_pitch:get()), tostring(aa_yaw:get()), tostring(aa_mod:get()), tostring(aa_sway_amt:get()),
        tostring(aa_desync:get()), tostring(aa_invert:get()), tostring(aa_lag:get()), tostring(aa_lag_var:get()),
    }, "|")
    if sig == aaSig and globals.tickcount() % 12 ~= 0 then return end
    aaSig = sig

    aa.override_pitch(aa_pitch:get())
    aa.override_yaw(aa_yaw:get(), "camera")

    local mod = aa_mod:get()
    if mod == "Sway" then
        local amt = aa_sway_amt:get()
        if swayAmt ~= amt then
            swayAmt = amt
            swayFn = function(t, baseYaw) return math.sin(t * 0.2) * amt end
        end
        aa.override_yaw_modifier(swayFn)
    elseif mod == "Disabled" then
        aa.override_yaw_modifier("Disabled")
    else
        aa.override_yaw_modifier(mod)
    end

    local lim = aa_desync:get()
    aa.override_body_yaw(true)
    aa.override_inverter(aa_invert:get())
    aa.override_desync_limits(lim, lim)

    aa.override_fake_lag(true)
    aa.override_fake_lag_limit(aa_lag:get())
    aa.override_fake_lag_variability(aa_lag_var:get())
end)

-- RESOLVER (built-in baseline + Lua brute-force on top)
local BRUTE_ANGLES = { 58, -58, 0, 86, -86 }
local targetState = {}

local function getState(who)
    local key = keyOf(who)
    if not targetState[key] then
        targetState[key] = { misses = 0, stage = 1 }
    end
    return targetState[key]
end

local function applyResolverSettings()
    local on = res_enable:get()
    rage.set_resolver_enabled(on)
    if on then
        rage.set_resolver_mode(res_mode:get())
        rage.set_resolver_miss_limit(res_miss:get())
        rage.set_resolver_baim_after_misses(res_baim:get())
    end
end

res_enable:set_callback(applyResolverSettings)
res_mode:set_callback(applyResolverSettings)
res_baim:set_callback(applyResolverSettings)
res_miss:set_callback(applyResolverSettings)
applyResolverSettings()

onEvent("aim_hit", function(e)
    getState(e.target).misses = 0
end)

onEvent("aim_miss", function(e)
    if e.reason == "resolver" then
        local s = getState(e.target)
        s.misses += 1
        s.stage = (s.stage % #BRUTE_ANGLES) + 1
    end
end)

onTick(function(tick)
    learnSlot()

    -- Lua brute-force only runs in Brute-force mode
    if not res_enable:get() or res_mode:get() ~= "Brute-force" then
        return
    end

    for _, enemy in ipairs(entity.get_enemies()) do
        if entity.is_alive(enemy) then
            local s = getState(enemy)
            pset(enemy, "Force body yaw", true)
            pset(enemy, "Override yaw offset", BRUTE_ANGLES[s.stage] or 0)

            local limit = res_baim:get()
            if limit > 0 and s.misses >= limit then
                pset(enemy, "Override prefer body aim", "Force")
            else
                pset(enemy, "Override prefer body aim", "-")
            end
        end
    end
end)

-- RAGEBOT OVERRIDES (re-applied when a setting changes, and every 16 ticks as a refresh)
local rbWas, rbSig = false, nil
onTick(function(tick)
    if not rb_enable:get() then
        if rbWas then rage.reset(); rbWas = false; rbSig = nil end
        return
    end
    rbWas = true

    local dmg, hc = rb_dmg:get(), rb_hc:get()
    local sig = dmg .. "|" .. hc .. "|" .. tostring(rb_target:get()) .. "|" ..
        tostring(rb_baim_key:get()) .. "|" .. tostring(rb_safe_key:get())
    if sig == rbSig and globals.tickcount() % 16 ~= 0 then return end
    rbSig = sig

    rage.override_min_damage(dmg)
    rage.override_hitchance(hc)
    rage.override_target_selection(rb_target:get())
    rage.override_force_baim(rb_baim_key:get())
    rage.override_force_safe_point(rb_safe_key:get())
    rage.override_hitboxes({ "head", "chest", "pelvis", "legs" })
    rage.override_hitbox_priority({ "pelvis", "chest", "head" })
    rage.set_hitbox_config("head", { min_damage = dmg, hitchance = hc, multipoint = true })
end)

-- VISUALS
local function applyChams()
    if v_chams:get() then
        chams.set_enabled(true)
        chams.override_visible(v_vis_col:get(), v_chams_mat:get(), 0.1)
        chams.override_occluded(v_hid_col:get(), v_chams_mat:get(), 0.3)
    else
        chams.clear_overrides()
        chams.set_enabled(false)
    end
end

v_chams:set_callback(applyChams)
v_chams_mat:set_callback(applyChams)
v_vis_col:set_callback(applyChams)
v_hid_col:set_callback(applyChams)
applyChams()

onEvent("paint", function()
    render.clear() -- recycle last frame's drawings so nothing stacks
    local target = curTarget()

    if v_target3d:get() and target and (target.aim_point or target.point) then
        render3d.box(CFrame.new(target.aim_point or target.point), Vector3.new(1.2, 1.2, 1.2), theme.target, 0.4, true)
    end

    if v_hud:get() then
        -- fixed-position text lines, bottom-left, drawn upward
        local _, sh = render.screen_size()
        local y = sh - 200
        local function line(text, c)
            render.text(20, y, text, c, 14, true)
            y = y - 18
        end

        if aa_enable:get() then
            local side = aa.get_inverter() and "RIGHT" or "LEFT"
            local choke = aa.is_fake_lag_choking() and "YES" or "NO"
            line(cached("hud_aa", function() return string.format("AA: %d° [%s] | CHOKE: %s", aa_desync:get(), side, choke) end), theme.accent2)
        end

        if res_enable:get() then
            if target and target.slot ~= nil then
                local s = getState(target.slot)
                line(cached("hud_res", function() return string.format("RESOLVER: %d° | MISS: %d", BRUTE_ANGLES[s.stage] or 0, s.misses) end), theme.accent)
            else
                line("RESOLVER: ACTIVE", theme.sub)
            end
        end

        if rage.is_double_tap_charged() then
            line("DT: READY", theme.good)
        else
            line(cached("hud_dt", function() return string.format("DT: %d/14", rage.get_double_tap_charge()) end), theme.bad)
        end
    end
end)

-- MISC
local function applySounds()
    local custom = (string.gsub(tostring(m_hs_id:get() or ""), "%s", ""))
    local hit = (custom ~= "") and custom or m_hitsound:get()
    sounds.override_hitsound(hit, m_hs_vol:get() / 100, m_hs_pitch:get() / 100)
    sounds.override_killsound(m_killsound:get(), 1.0, 1.0)
end
m_hitsound:set_callback(applySounds)
m_killsound:set_callback(applySounds)
m_hs_id:set_callback(applySounds)
m_hs_vol:set_callback(applySounds)
m_hs_pitch:set_callback(applySounds)
applySounds()

local function applyClantag()
    if not m_clantag:get() then
        clantag.reset()
        return
    end
    clantag.set(m_tag_text:get(), string.lower(m_tag_anim:get()), 0.3)
end
m_clantag:set_callback(applyClantag)
m_tag_text:set_callback(applyClantag)
m_tag_anim:set_callback(applyClantag)

local KILL_SAY = { "1", "sit down", "nice try", "skeed on top" }
onEvent("aim_hit", function(e)
    if m_killsay:get() and e.health_remaining and e.health_remaining <= 0 then
        chat.say(KILL_SAY[math.random(1, #KILL_SAY)])
    end
end)

notify("HVH Config", "Loaded successfully", 3, true)

-- EXTRAS: second menu tab
local xtab      = menu.new_tab("HVH Extras", ICON)
local x_aa      = xtab:new_section("Advanced AA", "Left")
local x_rage    = xtab:new_section("Weapon Config", "Right")
local x_vis     = xtab:new_section("Extra Visuals", "Left")
local x_misc    = xtab:new_section("Utilities", "Right")

-- Manual AA
local man_left  = x_aa:new_keybind("Manual Left", "Toggle", "Left")
local man_right = x_aa:new_keybind("Manual Right", "Toggle", "Right")
local man_back  = x_aa:new_keybind("Manual Back", "Toggle", "Down")

-- Movement-state body yaw (real/fake angles)
local st_enable = x_aa:new_toggle("Body Yaw By Movement", true)
local st_stand  = x_aa:new_slider("Standing Desync Limit", 0, 86, 86, 0, "°")
local st_run    = x_aa:new_slider("Running Desync Limit", 0, 86, 58, 0, "°")
local st_crouch = x_aa:new_slider("Crouching Desync Limit", 0, 86, 75, 0, "°")
local st_air    = x_aa:new_slider("In-Air Desync Limit", 0, 86, 45, 0, "°")
local st_stand_real = x_aa:new_slider("Standing Real Body Yaw", -86, 86, 0, 0, "°")
local st_stand_fake = x_aa:new_slider("Standing Fake Body Yaw", -86, 86, 58, 0, "°")
local st_run_real   = x_aa:new_slider("Moving Real Body Yaw", -86, 86, 0, 0, "°")
local st_run_fake   = x_aa:new_slider("Moving Fake Body Yaw", -86, 86, 58, 0, "°")
local st_crouch_real = x_aa:new_slider("Crouch Real Body Yaw", -86, 86, 0, 0, "°")
local st_crouch_fake = x_aa:new_slider("Crouch Fake Body Yaw", -86, 86, 58, 0, "°")
local st_air_real   = x_aa:new_slider("Air Real Body Yaw", -86, 86, 0, 0, "°")
local st_air_fake   = x_aa:new_slider("Air Fake Body Yaw", -86, 86, 45, 0, "°")

-- Defensive AA
local def_enable   = x_aa:new_toggle("Defensive AA", false)
local def_interval = x_aa:new_slider("Defensive Interval", 8, 64, 24, 0, " ticks")

-- extended angles, fake pitch, fake model
local x_fake    = x_aa:new_toggle("Show Fake Model", false)
local x_ext_on  = x_aa:new_toggle("Extended Angles", false)
local x_ext_amt = x_aa:new_slider("Extended Angles Amount", -100, 100, 50, 0, "%")
local x_fpitch  = x_aa:new_combobox("Fake Pitch", { "Disabled", "Down", "Up", "Zero" }, "Disabled")

-- Weapon-based damage
local wp_enable = x_rage:new_toggle("Per-Weapon Min Damage", true)
local wp_sniper = x_rage:new_slider("Sniper Min Damage", 1, 100, 80, 0, " hp")
local wp_pistol = x_rage:new_slider("Pistol Min Damage", 1, 100, 35, 0, " hp")
local wp_other  = x_rage:new_slider("Other Min Damage", 1, 100, 45, 0, " hp")

-- Extra visuals
local xv_watermark = x_vis:new_toggle("Watermark", true)
local xv_stats     = x_vis:new_toggle("Hit/Miss Stats", true)
local xv_predict   = x_vis:new_toggle("Enemy Path Prediction", false)
local xv_pred_tick = x_vis:new_slider("Prediction Ticks", 4, 32, 16, 0, " ticks")
local xv_wire      = x_vis:new_toggle("Enemy Wire Boxes", false)
local xv_wire_col  = x_vis:new_colorpicker("Wire Box Color", Color3.fromRGB(255, 80, 80))
local xv_ring      = x_vis:new_toggle("Target Ring", false)
local xv_wm_text   = x_vis:new_textbox("Watermark Text", "skeed.$win", "skeed.$win")
local xv_hat       = x_vis:new_toggle("China Hat", false)
local xv_hat_col   = x_vis:new_colorpicker("China Hat Color", Color3.fromRGB(190, 120, 255))
local xv_hat_r     = x_vis:new_slider("China Hat Radius", 0.5, 4, 1.6, 1, " studs")
local xv_hat_h     = x_vis:new_slider("China Hat Height", 0.3, 3, 0.9, 1, " studs")
local xv_hat_spin  = x_vis:new_slider("China Hat Spin Speed", 0, 5, 1, 1, "")
local xv_hat_flip  = x_vis:new_toggle("Flip China Hat (if upside down)", false)
local xv_hat_off   = x_vis:new_slider("China Hat Height Offset", -10, 10, 6, 1, " studs")

-- where the hat sits: head center and half the head height, plus where it came from
local function hatAnchor()
    local center, half, source = nil, 1, nil

    pcall(function()
        local char = game:GetService("Players").LocalPlayer.Character
        if not char then return end
        local head = char:FindFirstChild("Head")
        if head then
            center, half, source = head.Position, head.Size.Y / 2, "character head"
        else
            local cf, size = char:GetBoundingBox()
            center, half, source = cf.Position + Vector3.new(0, size.Y / 2 - 1, 0), 1, "character bounds"
        end
    end)

    if not center then
        local me = entity.get_local_player()
        local pos = me and entity.get_player_position(me)
        if pos then center, half, source = pos + Vector3.new(0, 1.5, 0), 1, "entity position" end
    end
    return center, half, source
end

x_vis:new_button("Print China Hat Info", function()
    local function fmt(v)
        if not v then return "none" end
        return string.format("%.1f, %.1f, %.1f", v.X, v.Y, v.Z)
    end
    local center, half, source = hatAnchor()
    local root, cam, ent = nil, nil, nil
    pcall(function() root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position end)
    pcall(function() cam = workspace.CurrentCamera.CFrame.Position end)
    pcall(function() ent = entity.get_player_position(entity.get_local_player()) end)
    local msg = string.format("hat anchor (%s): %s | root: %s | entity pos: %s | camera: %s",
        tostring(source), fmt(center), fmt(root), fmt(ent), fmt(cam))
    client.log("[china hat] " .. msg)
    notify("China Hat info", msg, 12, false)
end)

-- Utilities
local u_log = x_misc:new_toggle("Log Shots To Console", true)
x_misc:new_button("Reset Resolver State", function()
    for k in pairs(targetState) do targetState[k] = nil end
    rage.reset_resolver_state()
    notify("Resolver", "Resolver state reset", 2, false)
end)
x_misc:new_button("Test Hitsound", function()
    sounds.play_hitsound()
end)
x_misc:new_button("Test Killsound", function()
    sounds.play_killsound()
end)
x_misc:new_button("Reset Stats", function()
    -- handled below via the stats table
    if _G.__hvh_reset_stats then _G.__hvh_reset_stats() end
end)

-- EXTRAS: AA logic (registered after the main AA tick, so it wins)
onTick(function(tick)
    if not aa_enable:get() then return end

    -- manual direction
    if man_left:get() then
        aa.set_manual("Left")
    elseif man_right:get() then
        aa.set_manual("Right")
    elseif man_back:get() then
        aa.set_manual("Back")
    else
        aa.set_manual(nil)
    end

    -- Apply independently adjustable real/fake body yaw for each movement state.
    if st_enable:get() then
        local state = movement.get_state()
        local lim, realYaw, fakeYaw
        if state == "InAir" then
            lim, realYaw, fakeYaw = st_air:get(), st_air_real:get(), st_air_fake:get()
        elseif state == "Crouching" then
            lim, realYaw, fakeYaw = st_crouch:get(), st_crouch_real:get(), st_crouch_fake:get()
        elseif state == "Running" then
            lim, realYaw, fakeYaw = st_run:get(), st_run_real:get(), st_run_fake:get()
        else
            lim, realYaw, fakeYaw = st_stand:get(), st_stand_real:get(), st_stand_fake:get()
        end
        if aa_invert:get() then
            realYaw, fakeYaw = -realYaw, -fakeYaw
        end
        aa.override_desync_limits(lim, lim)
        aa.override_desync(realYaw, fakeYaw)
    end
end)

local defensiveUntil = 0
onTick(function(tick)
    if not aa_enable:get() or not def_enable:get() then return end

    local tc = globals.tickcount()
    if rage.is_double_tap_charged() and tc % def_interval:get() == 0 then
        rage.shift_ticks()
        defensiveUntil = tc + 2
    end

    if tc < defensiveUntil then
        aa.override_pitch((tc % 2 == 0) and 89 or -89)
        aa.override_yaw_offset(math.random(-180, 180))
    end
end)

-- EXTRAS: extended angles, fake pitch, fake model
onTick(function(tick)
    if not aa_enable:get() then return end

    if x_fake:get() then aa.override_show_fake(true) end

    if x_ext_on:get() then
        aa.override_extended_angles(x_ext_amt:get())
    else
        aa.override_extended_angles(nil)
    end

    local fp = x_fpitch:get()
    if fp == "Disabled" then
        aa.override_fake_pitch(nil)
    else
        aa.override_fake_pitch(fp)
    end
end)

-- EXTRAS: weapon-based min damage
onTick(function(tick)
    if not rb_enable:get() or not wp_enable:get() then return end

    local wep = weapon.get_active()
    if not wep then return end

    local t = string.lower(tostring(wep.type or ""))
    local dmg
    if string.find(t, "sniper") then
        dmg = wp_sniper:get()
    elseif string.find(t, "pistol") then
        dmg = wp_pistol:get()
    else
        dmg = wp_other:get()
    end
    rage.override_min_damage(dmg)
end)

-- EXTRAS: stats + shot logging
local stats = { fired = 0, hits = 0, misses = 0, kills = 0, reasons = { resolver = 0, spread = 0, occlusion = 0, death = 0 } }

_G.__hvh_reset_stats = function()
    stats.fired, stats.hits, stats.misses, stats.kills = 0, 0, 0, 0
    for k in pairs(stats.reasons) do stats.reasons[k] = 0 end
end

onEvent("aim_fire", function(e)
    stats.fired += 1
    if u_log:get() then
        client.log(string.format("[fire] hitbox=%s dmg=%s hc=%s", tostring(e.hitbox), tostring(e.damage), tostring(e.hitchance)))
    end
end)

onEvent("aim_hit", function(e)
    stats.hits += 1
    if e.health_remaining and e.health_remaining <= 0 then stats.kills += 1 end
    if u_log:get() then
        client.log(string.format("[hit] hitbox=%s dmg=%s hp_left=%s bt=%s", tostring(e.hitbox), tostring(e.damage), tostring(e.health_remaining), tostring(e.backtrack_ticks)))
    end
end)

onEvent("aim_miss", function(e)
    stats.misses += 1
    if stats.reasons[e.reason] ~= nil then
        stats.reasons[e.reason] += 1
    end
    if u_log:get() then
        client.log(string.format("[miss] hitbox=%s reason=%s", tostring(e.hitbox), tostring(e.reason)))
    end
end)

-- EXTRAS: second paint pass (runs after the main one has cleared)
onEvent("paint", function()
    local sw, sh = render.screen_size()

    -- watermark, top right
    if xv_watermark:get() then
        local fps = math.floor(1 / math.max(globals.frametime(), 0.001))
        local ping = math.floor(client.latency() * 1000)
        local label = tostring(xv_wm_text:get() or "")
        if label == "" then label = "skeed.$win" end
        local txt = cached("wm", function() return label .. string.format(" | %d fps | %d ms", fps, ping) end)
        local size = cached("wm_size", function() return render.measure_text(txt, 14) end)
        render.text(sw - size.X - 20, 12, txt, theme.accent, 14, true)
    end

    -- hit / miss stats, top left
    if xv_stats:get() then
        local total = stats.hits + stats.misses
        local pct = total > 0 and math.floor(stats.hits / total * 100) or 0
        render.text(20, 40, cached("st1", function() return string.format("Hits %d | Misses %d | %d%% | Kills %d", stats.hits, stats.misses, pct, stats.kills) end), theme.accent, 14, true)
        render.text(20, 58, cached("st2", function() return string.format("Miss: resolver %d, spread %d, occ %d, death %d",
            stats.reasons.resolver, stats.reasons.spread, stats.reasons.occlusion, stats.reasons.death) end),
            theme.sub, 13, true)
    end

    -- predicted enemy paths
    if xv_predict:get() then
        local ticks = xv_pred_tick:get()
        for _, enemy in ipairs(entity.get_enemies()) do
            if entity.is_alive(enemy) then
                local now = entity.get_player_position(enemy)
                local future = movement.predict_position(enemy, ticks)
                if now and future then
                    render3d.line(now, future, theme.good, 2)
                    render3d.sphere(future, 0.5, theme.good, 0.2)
                end
            end
        end
    end

    -- wire boxes around enemies
    if xv_wire:get() then
        local col = xv_wire_col:get()
        for _, enemy in ipairs(entity.get_enemies()) do
            if entity.is_alive(enemy) then
                local pos = entity.get_player_position(enemy)
                if pos then
                    render3d.wire_box(CFrame.new(pos), Vector3.new(3, 5.5, 3), col, 0.2, true)
                end
            end
        end
    end

    -- china hat: a spinning cone above your own head
    if xv_hat:get() then
        local center, half = hatAnchor()

        if center then
            local radius, height = xv_hat_r:get(), xv_hat_h:get()
            local col = xv_hat_col:get()
            local dir = xv_hat_flip:get() and -1 or 1
            local base = center + Vector3.new(0, dir * (half + 0.15) + xv_hat_off:get(), 0)
            local apex = base + Vector3.new(0, dir * height, 0)
            local spokes = perf.spokes or 12
            local step = (2 * math.pi) / spokes
            local spin = globals.realtime() * xv_hat_spin:get()

            for k = 0, spokes - 1 do
                local a1 = spin + k * step
                local a2 = a1 + step
                local p1 = base + Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)
                local p2 = base + Vector3.new(math.cos(a2) * radius, 0, math.sin(a2) * radius)
                render3d.line(apex, p1, col, 1, 0.1)
                render3d.line(p1, p2, col, 1, 0.1)
            end
        end
    end

    -- ring under the current ragebot target
    if xv_ring:get() then
        local target = curTarget()
        if target and target.player then
            local pos = entity.get_player_position(target.player)
            if pos then
                render3d.ring(pos - Vector3.new(0, 2.8, 0), 3, 0.4, theme.target, 0.2, true)
            end
        end
    end

    -- manual direction indicator
    local manual = aa.get_manual()
    if manual then
        render.text(sw / 2 - 40, sh / 2 + 60, "MANUAL: " .. manual, theme.warn, 14, true, true)
    end
end)

-- MORE: third menu tab
local ttab     = menu.new_tab("HVH More", ICON)
local t_aa     = ttab:new_section("Smart AA", "Left")
local t_res    = ttab:new_section("Smart Resolver", "Right")
local t_hud    = ttab:new_section("HUD", "Left")
local t_cfg    = ttab:new_section("Presets", "Right")

-- Smart AA: fake lag by movement state
local fl_state  = t_aa:new_toggle("State-Based Fake Lag", true)
local fl_stand  = t_aa:new_slider("Standing Lag", 0, 14, 4, 0, "t")
local fl_run    = t_aa:new_slider("Running Lag", 0, 14, 10, 0, "t")
local fl_air    = t_aa:new_slider("In-Air Lag", 0, 14, 14, 0, "t")

-- Smart Resolver
local sr_anim   = t_res:new_toggle("Animstate Assist (Adaptive mode)", true)
local sr_air_sp = t_res:new_toggle("Safe Point On Airborne Enemies", true)
local yp_enable = t_res:new_toggle("Yaw Prediction (Adaptive mode)", true)
local yp_time   = t_res:new_slider("Prediction Time", 0, 300, 90, 0, "ms")
local yp_jitter = t_res:new_toggle("Predict Jitter Flips", true)

-- HUD
local h_cross   = t_hud:new_toggle("Crosshair Indicators", true)
local h_keys    = t_hud:new_toggle("Keybind List", true)
local h_hitlog  = t_hud:new_toggle("On-Screen Hitlog", true)
local h_weapon  = t_hud:new_toggle("Weapon Info", true)
local h_speed   = t_hud:new_toggle("Speed And State (needs Crosshair Indicators)", true)
local h_spread  = t_hud:new_toggle("Spread And Inaccuracy (needs Crosshair Indicators)", false)

-- MORE: smart AA (fake lag by state)
onTick(function(tick)
    if not aa_enable:get() or not fl_state:get() then return end

    local state = movement.get_state()
    local lag
    if state == "InAir" then
        lag = fl_air:get()
    elseif state == "Running" then
        lag = fl_run:get()
    else
        lag = fl_stand:get()
    end
    aa.override_fake_lag(true)
    aa.override_fake_lag_limit(lag)
end)

-- MORE: smart resolver
-- Yaw prediction: keeps a short history of each enemy's yaw / desync.
--  * spinning enemies: yaw velocity is smoothed and extrapolated forward
--  * jitter enemies: if the desync side flipped on the last samples we
--    expect it to flip again and aim at the side it is about to be on
local yawHist = {}
local function wrapDeg(d)
    d = (d + 180) % 360 - 180
    return d
end

local function predictOffset(enemy, anim, base)
    local now = globals.realtime()
    local key = keyOf(enemy)
    local h = yawHist[key]
    if not h then
        h = { yaw = anim.eye_angles_y or 0, t = now, vel = 0, side = 0, flips = 0, lastBase = base }
        yawHist[key] = h
        return base
    end
    local dt = now - h.t
    if dt < 0.008 then return h.out or base end

    local yaw = anim.eye_angles_y or h.yaw
    local rawVel = wrapDeg(yaw - h.yaw) / dt
    rawVel = math.max(-2000, math.min(2000, rawVel))
    h.vel = h.vel * 0.7 + rawVel * 0.3            -- smoothed deg/s
    h.yaw, h.t = yaw, now

    -- desync side tracking (for jitter)
    local side = base > 2 and 1 or (base < -2 and -1 or 0)
    if side ~= 0 and h.side ~= 0 then
        if side ~= h.side then h.flips = math.min(h.flips + 1, 6)
        else h.flips = math.max(h.flips - 1, 0) end
    end
    if side ~= 0 then h.side = side end

    local out = base
    local lead = yp_time:get() / 1000
    -- spin: add the yaw the enemy will have turned by the time we shoot
    if math.abs(h.vel) > 40 then
        out = out + math.max(-60, math.min(60, h.vel * lead))
    end
    -- jitter: flips keep happening -> assume the opposite side next tick
    if yp_jitter:get() and h.flips >= 3 and side ~= 0 then
        out = -base
    end
    out = math.max(-86, math.min(86, out))
    h.out = out
    return out
end

onTick(function(tick)
    if not res_enable:get() then return end
    local useAnim = sr_anim:get() and res_mode:get() == "Adaptive"
    local usePred = yp_enable:get() and res_mode:get() == "Adaptive"

    for _, enemy in ipairs(entity.get_enemies()) do
        if entity.is_alive(enemy) then
            -- use the enemy's evaluated animstate desync as the yaw offset
            if useAnim or usePred then
                local anim = entity.get_anim_state(enemy)
                if anim and anim.desync then
                    local off = math.max(-86, math.min(86, anim.desync))
                    if usePred then
                        local ok, r = pcall(predictOffset, enemy, anim, off)
                        if ok and r then off = r end
                    end
                    pset(enemy, "Force body yaw", true)
                    pset(enemy, "Override yaw offset", off)
                end
            end

            -- airborne enemies: require safe points
            if sr_air_sp:get() then
                local info = entity.get_info(enemy)
                if info and info.is_in_air then
                    pset(enemy, "Override safe point", "Force")
                else
                    pset(enemy, "Override safe point", "-")
                end
            end
        end
    end
end)

-- MORE: on-screen hitlog
local hitlog = {}
local HITLOG_TIME = 4

local function nameOf(target)
    local ok, info = pcall(entity.get_info, target)
    if ok and type(info) == "table" and info.name then return tostring(info.name) end
    local ok2, n = pcall(entity.get_player_name, target)
    if ok2 and n then return tostring(n) end
    return "player"
end

local function pushLog(text, col)
    table.insert(hitlog, 1, { text = text, col = col, t = globals.realtime() })
    if #hitlog > 8 then table.remove(hitlog) end
end

onEvent("aim_hit", function(e)
    pushLog(string.format("Hit %s in %s for %s (%s hp left)",
        nameOf(e.target), tostring(e.hitbox), tostring(e.damage), tostring(e.health_remaining)),
        theme.good)
end)

onEvent("aim_miss", function(e)
    pushLog(string.format("Missed %s in %s due to %s",
        nameOf(e.target), tostring(e.hitbox), tostring(e.reason)),
        theme.bad)
end)

-- MORE: HUD drawing (third paint pass)
onEvent("paint", function()
    local sw, sh = render.screen_size()
    local cx, cy = sw / 2, sh / 2

    -- hitlog, top center
    if h_hitlog:get() then
        local now = globals.realtime()
        local y = 80
        for i = #hitlog, 1, -1 do
            if now - hitlog[i].t > HITLOG_TIME then table.remove(hitlog, i) end
        end
        for _, entry in ipairs(hitlog) do
            render.text(cx, y, entry.text, entry.col, 13, true, true)
            y += 16
        end
    end

    -- crosshair indicators
    if h_cross:get() then
        local y = cy + 30
        local function ind(text, col)
            render.text(cx, y, text, col, 13, true, true)
            y += 14
        end

        if rage.is_double_tap_charged() then
            ind("DT", theme.good)
        else
            ind(cached("ind_dt", function() return string.format("DT %d/14", rage.get_double_tap_charge()) end), theme.bad)
        end
        ind(cached("ind_dmg", function() return "DMG " .. tostring(rage.get_min_damage()) end), theme.text)
        if h_speed:get() then
            ind(cached("ind_spd", function() return string.format("%s %d", tostring(movement.get_state()), math.floor(movement.get_speed() or 0)) end), theme.sub)
        end
        if h_spread:get() then
            ind(cached("ind_spr", function() return string.format("SPREAD %.2f  INACC %.2f", weapon.get_spread() or 0, weapon.get_inaccuracy() or 0) end), theme.warn)
        end
        if rage.is_force_baim() then ind("BAIM", theme.warn) end
        if rage.is_force_safe_point() then ind("SAFE", theme.header) end
        if aa.get_manual() then ind("MAN " .. aa.get_manual():upper(), theme.warn) end
    end

    -- keybind list, left-middle
    if h_keys:get() then
        local y = cy - 40
        render.text(20, y, "Keybinds", theme.text, 14, true)
        y += 18
        local binds = {
            { "Invert Side", aa_invert:get() },
            { "Force Body Aim", rb_baim_key:get() },
            { "Force Safe Point", rb_safe_key:get() },
            { "Manual Left", man_left:get() },
            { "Manual Right", man_right:get() },
            { "Manual Back", man_back:get() },
        }
        for _, b in ipairs(binds) do
            if b[2] then
                render.text(20, y, b[1] .. " [on]", theme.accent, 13, true)
                y += 16
            end
        end
    end

    -- weapon info, bottom-right
    if h_weapon:get() then
        local wep = weapon.get_active()
        if wep then
            local txt = string.format("%s  %s/%s%s", tostring(wep.name),
                tostring(wep.ammo), tostring(wep.reserve),
                wep.is_reloading and "  [RELOADING]" or "")
            local size = render.measure_text(txt, 14)
            render.text(sw - size.X - 20, sh - 40, txt, theme.text, 14, true)
        end
    end
end)

-- MORE: presets (saved with the database, survive reloads)
local function snapshot()
    return {
        yaw = aa_yaw:get(),
        desync = aa_desync:get(),
        lag = aa_lag:get(),
        dmg = rb_dmg:get(),
        hc = rb_hc:get(),
        baim = res_baim:get(),
    }
end

local function applySnapshot(p)
    if type(p) ~= "table" then return false end
    if p.yaw then aa_yaw:set(p.yaw) end
    if p.desync then aa_desync:set(p.desync) end
    if p.lag then aa_lag:set(p.lag) end
    if p.dmg then rb_dmg:set(p.dmg) end
    if p.hc then rb_hc:set(p.hc) end
    if p.baim then res_baim:set(p.baim) end
    return true
end

local presets = {
    Legit  = { yaw = 180, desync = 40, lag = 4,  dmg = 20, hc = 50, baim = 0 },
    Rage   = { yaw = 180, desync = 58, lag = 8,  dmg = 40, hc = 65, baim = 2 },
    Max    = { yaw = 180, desync = 86, lag = 14, dmg = 60, hc = 80, baim = 2 },
}

t_cfg:new_button("Load Preset: Legit", function()
    applySnapshot(presets.Legit)
    notify("Preset", "Loaded Legit", 2, false)
end)
t_cfg:new_button("Load Preset: Rage", function()
    applySnapshot(presets.Rage)
    notify("Preset", "Loaded Rage", 2, false)
end)
t_cfg:new_button("Load Preset: Max", function()
    applySnapshot(presets.Max)
    notify("Preset", "Loaded Max", 2, false)
end)
for _, style in ipairs({ "Static", "Sway", "Spin", "Random", "5-Way" }) do
    t_cfg:new_button("AA Style: " .. style, function()
        aa_mod:set(style == "Static" and "Disabled" or style)
        notify("Preset", "AA style: " .. style, 2, false)
    end)
end
t_cfg:new_button("Save Custom Slot", function()
    database.write("hvh_custom_slot", snapshot())
    database.flush()
    notify("Preset", "Saved custom slot", 2, false)
end)
t_cfg:new_button("Load Custom Slot", function()
    if applySnapshot(database.read("hvh_custom_slot")) then
        notify("Preset", "Loaded custom slot", 2, false)
    else
        notify("Preset", "No custom slot saved yet", 2, false)
    end
end)

-- SPREAD HELPER (state-based hitchance; this cannot remove weapon spread)
local sp_sec      = ttab:new_section("Spread Helper", "Left")
local sp_enable   = sp_sec:new_toggle("Enable Spread Helper", false)
local sp_speed    = sp_sec:new_toggle("Hold Fire While Moving Fast", false)
local sp_maxspd   = sp_sec:new_slider("Max Fire Speed", 0, 40, 20, 0, " studs/s")
local sp_scope    = sp_sec:new_toggle("Require Scope (Snipers)", false)
local sp_noscope  = sp_sec:new_slider("No-scope Chance", 0, 100, 65, 0, "%")
local sp_crouch   = sp_sec:new_slider("Crouch Assist Chance", 0, 100, 80, 0, "%")
local sp_moving   = sp_sec:new_slider("Moving Assist Chance", 0, 100, 75, 0, "%")
local sp_adapt    = sp_sec:new_toggle("Adaptive Hitchance", true)
local sp_step     = sp_sec:new_slider("Hitchance Per Spread Miss", 1, 10, 4, 0, "%")

local spreadMisses = 0

onEvent("aim_miss", function(e)
    if e.reason == "spread" then
        spreadMisses = math.min(spreadMisses + 1, 8)
    end
end)

onEvent("aim_hit", function(e)
    spreadMisses = math.max(spreadMisses - 1, 0)
end)

onTick(function(tick)
    if not rb_enable:get() or not sp_enable:get() then return end

    local allow = true
    local speed = movement.get_speed()
    local wep = weapon.get_active()
    local weaponType = wep and string.lower(tostring(wep.type or "")) or ""
    local isSniper = string.find(weaponType, "sniper", 1, true) ~= nil
    local scoped = not isSniper or weapon.is_scoped()

    -- Start with the main Ragebot hitchance, then apply the active state values.
    local hc = rb_hc:get()

    if isSniper and not scoped then
        hc = math.max(hc, sp_noscope:get())
        if sp_scope:get() then allow = false end
    end

    if movement.is_ducking() then
        hc = math.max(hc, sp_crouch:get())
    end

    if speed > 1 then
        hc = math.max(hc, sp_moving:get())
    end

    -- Keep the optional fast-movement fire gate.
    if sp_speed:get() and speed > sp_maxspd:get() then
        allow = false
    end

    -- Recent spread misses raise the selected state hitchance further.
    if sp_adapt:get() then
        hc = math.min(hc + spreadMisses * sp_step:get(), 100)
    end
    rage.override_hitchance(hc)
    rage.override_enabled(allow)
end)

-- CURSORS: spinning custom cursor and a sniper cursor
local cur_sec   = ttab:new_section("Cursor", "Right")
local cu_enable = cur_sec:new_toggle("Custom Cursor", false)
local cu_style  = cur_sec:new_combobox("Cursor Style", { "Crosshair", "Diamond", "Triangle", "Star" }, "Crosshair")
local cu_size   = cur_sec:new_slider("Cursor Size", 6, 40, 14, 0, " px")
local cu_speed  = cur_sec:new_slider("Rotation Speed", 0, 360, 120, 0, " deg/s")
local cu_col    = cur_sec:new_colorpicker("Cursor Color", Color3.fromRGB(255, 255, 255))
local cu_hide   = cur_sec:new_toggle("Hide Default Cursor", true)
local cu_offx   = cur_sec:new_slider("Cursor X Offset", -60, 60, 0, 0, " px")
local cu_offy   = cur_sec:new_slider("Cursor Y Offset", -60, 60, 0, 0, " px")
local sc_enable = cur_sec:new_toggle("Sniper Cursor", false)
local sc_gap    = cur_sec:new_slider("Sniper Cursor Gap", 0, 40, 8, 0, " px")
local sc_thick  = cur_sec:new_slider("Sniper Cursor Thickness", 1, 4, 1, 0, " px")
local sc_dot    = cur_sec:new_toggle("Sniper Cursor Center Dot", true)
local sc_col    = cur_sec:new_colorpicker("Sniper Cursor Color", Color3.fromRGB(255, 60, 70))
local sc_hide   = cur_sec:new_toggle("Hide Game Cursor While Scoped", true)

do
    local uis = nil
    pcall(function() uis = game:GetService("UserInputService") end)
    local iconHidden = false

    -- the real mouse icon is only hidden while one of our cursors is drawn
    local function setIconHidden(hidden)
        if hidden == iconHidden or not uis then return end
        iconHidden = hidden
        pcall(function() uis.MouseIconEnabled = not hidden end)
    end

    local function sniperScoped()
        local wep = weapon.get_active()
        if not wep then return false end
        local kind = string.lower(tostring(wep.type or ""))
        return string.find(kind, "sniper", 1, true) ~= nil and weapon.is_scoped()
    end

    -- regular polygon, or a star when step is 2: connect vertex k to vertex k + step
    local function polygon(cx, cy, r, startAngle, n, step, col)
        local xs, ys = {}, {}
        for k = 0, n - 1 do
            local ang = startAngle + k * (2 * math.pi / n)
            xs[k] = cx + math.cos(ang) * r
            ys[k] = cy + math.sin(ang) * r
        end
        for k = 0, n - 1 do
            local j = (k + step) % n
            render.line(xs[k], ys[k], xs[j], ys[j], col, 2, 100)
        end
    end

    local function drawCursor(cx, cy)
        local r = cu_size:get()
        local col = cu_col:get()
        local a = math.rad((globals.realtime() * cu_speed:get()) % 360)
        local style = cu_style:get()

        if style == "Crosshair" then
            for k = 0, 3 do
                local ang = a + k * (math.pi / 2)
                render.line(cx + math.cos(ang) * r * 0.35, cy + math.sin(ang) * r * 0.35,
                    cx + math.cos(ang) * r, cy + math.sin(ang) * r, col, 2, 100)
            end
        elseif style == "Diamond" then
            polygon(cx, cy, r, a + math.pi / 4, 4, 1, col)
        elseif style == "Triangle" then
            polygon(cx, cy, r, a - math.pi / 2, 3, 1, col)
        else
            polygon(cx, cy, r, a - math.pi / 2, 5, 2, col)
        end
        render.circle_filled(cx, cy, 2, col, 100)
    end

    local function drawSniper(sw, sh)
        local cx, cy = sw / 2, sh / 2
        local gap, th, col = sc_gap:get(), sc_thick:get(), sc_col:get()
        render.line(0, cy, cx - gap, cy, col, th, 100)
        render.line(cx + gap, cy, sw, cy, col, th, 100)
        render.line(cx, 0, cx, cy - gap, col, th, 100)
        render.line(cx, cy + gap, cx, sh, col, th, 100)
        if sc_dot:get() then render.circle_filled(cx, cy, 2, col, 100) end
    end

    -- mouse position: tries the pointer, then the mouse, then the engine's own value
    local function pointer()
        local function fromCall(fn)
            local ok, a, b = pcall(fn)
            if not ok then return nil end
            if type(a) == "number" and type(b) == "number" then return a, b end
            local isVec = pcall(function() return a.X + a.Y end)
            if isVec then return a.X, a.Y end
            return nil
        end

        local x, y = fromCall(input.get_pointer_position)
        if x then return x, y, "input.get_pointer_position" end

        x, y = fromCall(input.get_mouse_position)
        if x then return x, y, "input.get_mouse_position" end

        if uis then
            x, y = fromCall(function() return uis:GetMouseLocation() end)
            if x then return x, y, "UserInputService" end
        end
        return nil
    end

    local cursorDrawn = false

    -- registered after the main paint callback, so render.clear() there does not wipe it
    onEvent("paint", function()
        local sw, sh = render.screen_size()
        local sniperOn = sc_enable:get() and sniperScoped()
        cursorDrawn = false

        if sniperOn then
            drawSniper(sw, sh)
        elseif cu_enable:get() then
            local mx, my = pointer()
            if not mx then
                mx, my = sw / 2, sh / 2 -- no pointer found: draw in the middle
            end
            local ok, err = pcall(drawCursor, mx + cu_offx:get(), my + cu_offy:get())
            if ok then
                cursorDrawn = true
            else
                reportError("custom cursor", err)
            end
        end

        -- only hide the real cursor once ours is actually being drawn
        setIconHidden((cursorDrawn and cu_hide:get()) or (sniperOn and sc_hide:get()))
    end)

    cur_sec:new_button("Print Cursor Info", function()
        local sw, sh = render.screen_size()
        local x, y, source = pointer()
        local msg
        if x then
            msg = string.format("pointer %d,%d via %s | screen %dx%d | drawn: %s",
                math.floor(x), math.floor(y), source, math.floor(sw), math.floor(sh), tostring(cursorDrawn))
        else
            msg = "no pointer position found, drawing in the middle of the screen"
        end
        client.log("[cursor] " .. msg)
        notify("Cursor info", msg, 8, false)
    end)

    onEvent("shutdown", function()
        setIconHidden(false)
    end)
end

-- ESP TAB: enemy ESP, hitmarker, crosshair, fov circle, ammo warning
local etab      = menu.new_tab("HVH ESP", ICON)
local e_esp     = etab:new_section("Enemy ESP", "Left")
local e_aim     = etab:new_section("Aim Helpers", "Right")

local esp_enable = e_esp:new_toggle("Enemy ESP", false)
local esp_name   = e_esp:new_toggle("Names", true)
local esp_dist   = e_esp:new_toggle("Distance", true)
local esp_health = e_esp:new_toggle("Health Bar", true)
local esp_weapon = e_esp:new_toggle("Weapon", true)
local esp_res    = e_esp:new_toggle("Resolver Info", false)
local esp_snap   = e_esp:new_toggle("Snaplines", false)
local esp_col    = e_esp:new_colorpicker("ESP Color", Color3.fromRGB(255, 255, 255))

local hm_enable  = e_aim:new_toggle("Hitmarker", false)
local hm_col     = e_aim:new_colorpicker("Hitmarker Color", Color3.fromRGB(255, 255, 255))
local cx_enable  = e_aim:new_toggle("Custom Crosshair", false)
local cx_size    = e_aim:new_slider("Crosshair Length", 2, 30, 8, 0, " px")
local cx_gap     = e_aim:new_slider("Crosshair Gap", 0, 20, 4, 0, " px")
local cx_thick   = e_aim:new_slider("Crosshair Thickness", 1, 4, 1, 0, " px")
local cx_dot     = e_aim:new_toggle("Crosshair Center Dot", true)
local cx_col     = e_aim:new_colorpicker("Crosshair Color", Color3.fromRGB(0, 255, 160))
local fov_enable = e_aim:new_toggle("FOV Circle", false)
local fov_r      = e_aim:new_slider("FOV Circle Radius", 20, 600, 200, 0, " px")
local fov_col    = e_aim:new_colorpicker("FOV Circle Color", Color3.fromRGB(255, 255, 255))
local am_enable  = e_aim:new_toggle("Low Ammo Warning", false)
local am_pct     = e_aim:new_slider("Warn Below", 5, 60, 25, 0, "%")

local lastHit = -10

onEvent("aim_hit", function(e)
    lastHit = globals.realtime()
end)

do
    local function enemyName(enemy)
        local name = nameOf(enemy)
        if name == "player" then
            local ok, n = pcall(function() return enemy.Name end)
            if ok and n then name = tostring(n) end
        end
        return name
    end

    local function drawEsp(sw, sh)
        local me = entity.get_local_player()
        local myPos = me and entity.get_player_position(me)
        local col = esp_col:get()

        for _, enemy in ipairs(entity.get_enemies()) do
            if entity.is_alive(enemy) then
                local pos = entity.get_player_position(enemy)
                if pos then
                    local head = entity.get_player_hitbox_position(enemy, "head") or (pos + Vector3.new(0, 2, 0))
                    local x, y, onScreen = render.world_to_screen(head + Vector3.new(0, 1.2, 0))

                    if onScreen then
                        if esp_snap:get() then
                            render.line(sw / 2, sh, x, y, col, 1)
                        end

                        local ty = y - 34

                        if esp_name:get() or esp_dist:get() then
                            local label = esp_name:get() and enemyName(enemy) or ""
                            if esp_dist:get() and myPos then
                                label = label .. " [" .. math.floor((pos - myPos).Magnitude) .. "]"
                            end
                            render.text(x, ty, label, col, 13, true, true)
                            ty += 14
                        end

                        if esp_health:get() then
                            local hp = math.max(0, math.min(100, entity.get_player_health(enemy) or 0)) / 100
                            render.rect_filled(x - 25, ty, 50, 5, Color3.fromRGB(20, 20, 20))
                            render.rect_filled(x - 24, ty + 1, 48 * hp, 3, Color3.fromRGB(255 * (1 - hp), 255 * hp, 60))
                            ty += 8
                        end

                        if esp_weapon:get() then
                            render.text(x, ty, tostring(entity.get_player_weapon_name(enemy) or ""), Color3.fromRGB(200, 200, 200), 12, true, true)
                            ty += 13
                        end

                        if esp_res:get() then
                            local s = getState(enemy)
                            render.text(x, ty, string.format("R %d  miss %d", BRUTE_ANGLES[s.stage] or 0, s.misses), Color3.fromRGB(0, 255, 160), 12, true, true)
                        end
                    end
                end
            end
        end
    end

    -- registered after the main paint callback, so render.clear() there does not wipe it
    onEvent("paint", function()
        local sw, sh = render.screen_size()
        local cx, cy = sw / 2, sh / 2

        if esp_enable:get() then drawEsp(sw, sh) end

        if fov_enable:get() then
            render.circle(cx, cy, fov_r:get(), fov_col:get(), 1)
        end

        if cx_enable:get() then
            local gap, len, th, col = cx_gap:get(), cx_size:get(), cx_thick:get(), cx_col:get()
            render.line(cx - gap - len, cy, cx - gap, cy, col, th)
            render.line(cx + gap, cy, cx + gap + len, cy, col, th)
            render.line(cx, cy - gap - len, cx, cy - gap, col, th)
            render.line(cx, cy + gap, cx, cy + gap + len, col, th)
            if cx_dot:get() then render.circle_filled(cx, cy, 1.5, col) end
        end

        if hm_enable:get() and globals.realtime() - lastHit < 0.35 then
            local col = hm_col:get()
            local a, b = 4, 10
            render.line(cx - b, cy - b, cx - a, cy - a, col, 2)
            render.line(cx + b, cy - b, cx + a, cy - a, col, 2)
            render.line(cx - b, cy + b, cx - a, cy + a, col, 2)
            render.line(cx + b, cy + b, cx + a, cy + a, col, 2)
        end

        if am_enable:get() then
            local ammo, maxAmmo = weapon.get_ammo(), weapon.get_max_ammo()
            if weapon.is_reloading() then
                render.text(cx, sh * 0.62, "RELOADING", Color3.fromRGB(255, 210, 90), 16, true, true)
            elseif ammo and maxAmmo and maxAmmo > 0 and ammo / maxAmmo <= am_pct:get() / 100 then
                render.text(cx, sh * 0.62, string.format("LOW AMMO  %d/%d", ammo, maxAmmo), Color3.fromRGB(255, 80, 80), 16, true, true)
            end
        end
    end)
end

-- HVH PLUS: situational ragebot rules + extra HUD
local ptab      = menu.new_tab("HVH Plus", ICON)
local p_rage    = ptab:new_section("Smart Ragebot", "Left")
local p_hud     = ptab:new_section("Extra HUD", "Right")

local pl_lethal   = p_rage:new_toggle("Lethal Min Damage", false)
local pl_lethal_h = p_rage:new_slider("Only When Target HP Below", 10, 100, 60, 0, " hp")
local pl_baim     = p_rage:new_toggle("Force Baim On Low HP", false)
local pl_baim_hp  = p_rage:new_slider("Baim Below", 5, 100, 50, 0, " hp")
local pl_air      = p_rage:new_toggle("Lower Hitchance On Airborne Target", false)
local pl_air_hc   = p_rage:new_slider("Airborne Hitchance", 1, 100, 40, 0, "%")
local pl_move     = p_rage:new_toggle("Lower Hitchance On Fast Target", false)
local pl_move_spd = p_rage:new_slider("Fast Above", 5, 60, 25, 0, " st/s")
local pl_move_hc  = p_rage:new_slider("Fast Target Hitchance", 1, 100, 50, 0, "%")

local ph_dt       = p_hud:new_toggle("Double Tap Charge Bar", false)
local ph_speed    = p_hud:new_toggle("Speed Indicator", false)
local ph_enemies  = p_hud:new_toggle("Enemy Counter", false)
local ph_near     = p_hud:new_toggle("Nearest Enemy Distance", false)
local ph_target   = p_hud:new_toggle("Current Target Info", false)
local ph_timer    = p_hud:new_toggle("Session Timer", false)
local ph_streak   = p_hud:new_toggle("Hit Streak", false)
local ph_vitals   = p_hud:new_toggle("Own HP / Armor Bar", false)

local p_perf      = ptab:new_section("Performance", "Right")
local pf_rate     = p_perf:new_slider("HUD Refresh Interval", 20, 500, 100, 0, " ms")
local pf_hat      = p_perf:new_slider("China Hat Detail", 6, 24, 10, 0, " spokes")

pf_rate:set_callback(function() perf.rate = pf_rate:get() / 1000 end)
pf_hat:set_callback(function() perf.spokes = pf_hat:get() end)
perf.rate, perf.spokes = pf_rate:get() / 1000, pf_hat:get()

do
    -- remembers what the ragebot had before we touched it, so it can be put back
    local saved = { dmg = nil, hc = nil, baim = nil }
    local sessionStart = globals.realtime()
    local streak, bestStreak = 0, 0

    local function restore(key, getFn, setFn)
        if saved[key] ~= nil then
            pcall(setFn, saved[key])
            saved[key] = nil
        end
    end

    local function remember(key, getFn)
        if saved[key] == nil then
            local ok, v = pcall(getFn)
            if ok then saved[key] = v end
        end
    end

    local function currentTarget()
        local t = curTarget()
        if type(t) == "table" and t.player then return t.player end
        return nil
    end

    local function release()
        restore("dmg", nil, rage.override_min_damage)
        restore("hc", nil, rage.override_hitchance)
        restore("baim", nil, rage.override_force_baim)
    end

    onTick(function()
        local any = pl_lethal:get() or pl_baim:get() or pl_air:get() or pl_move:get()
        if not any then release() return end

        local tgt = currentTarget()
        if not tgt or not entity.is_alive(tgt) then release() return end
        local hp = entity.get_player_health(tgt)

        -- lethal: shoot for exactly the damage that kills
        if pl_lethal:get() and hp <= pl_lethal_h:get() then
            remember("dmg", rage.get_min_damage)
            rage.override_min_damage(math.max(1, math.floor(hp)))
        else
            restore("dmg", nil, rage.override_min_damage)
        end

        -- low hp: body shots only
        if pl_baim:get() and hp <= pl_baim_hp:get() then
            remember("baim", rage.is_force_baim)
            rage.override_force_baim(true)
        else
            restore("baim", nil, rage.override_force_baim)
        end

        -- hitchance relaxations (the lower of the active ones wins)
        local want
        if pl_air:get() then
            local info = entity.get_info(tgt)
            if info and info.is_in_air then want = pl_air_hc:get() end
        end
        if pl_move:get() and entity.get_player_speed(tgt) >= pl_move_spd:get() then
            local hc = pl_move_hc:get()
            want = want and math.min(want, hc) or hc
        end
        if want then
            remember("hc", rage.get_hitchance)
            rage.override_hitchance(want)
        else
            restore("hc", nil, rage.override_hitchance)
        end
    end)

    onEvent("shutdown", release)

    onEvent("aim_hit", function()
        streak = streak + 1
        if streak > bestStreak then bestStreak = streak end
    end)
    onEvent("aim_miss", function() streak = 0 end)

    onEvent("paint", function()
        if not (ph_dt:get() or ph_speed:get() or ph_enemies:get() or ph_near:get() or ph_target:get()
            or ph_timer:get() or ph_streak:get() or ph_vitals:get()) then return end
        local sw, sh = render.screen_size()
        local x, y = 20, math.floor(sh * 0.5)
        local me = entity.get_local_player()

        if ph_dt:get() then
            local ok, ch = pcall(rage.get_double_tap_charge)
            ch = ok and ch or 0
            local frac = math.max(0, math.min(1, ch / 14))
            render.text(x, y, "DT", theme.text, 13, true)
            render.rect_filled(x + 24, y + 3, 100, 8, theme.panel, 3, 1)
            if frac > 0 then
                render.rect_filled(x + 24, y + 3, math.floor(100 * frac), 8, frac >= 1 and theme.good or theme.warn, 3, 2)
            end
            y = y + 18
        end

        if ph_speed:get() and me then
            local ok, sp = pcall(entity.get_player_speed, me)
            render.text(x, y, string.format("Speed %d", ok and sp or 0), theme.text, 13, true)
            y = y + 16
        end

        local enemies = entity.get_enemies()
        if ph_enemies:get() then
            local alive = 0
            for _, e in ipairs(enemies) do
                if entity.is_alive(e) then alive = alive + 1 end
            end
            render.text(x, y, string.format("Enemies alive %d", alive), theme.text, 13, true)
            y = y + 16
        end

        if ph_near:get() and me then
            local myPos = entity.get_player_position(me)
            local best, bestName
            for _, e in ipairs(enemies) do
                if entity.is_alive(e) then
                    local d = (entity.get_player_position(e) - myPos).Magnitude
                    if not best or d < best then best, bestName = d, nameOf(e) end
                end
            end
            if best then
                render.text(x, y, string.format("Nearest %s  %d studs", tostring(bestName), best), theme.text, 13, true)
                y = y + 16
            end
        end

        if ph_timer:get() then
            local secs = math.floor(globals.realtime() - sessionStart)
            local txt = cached("p_timer", function()
                return string.format("Session %02d:%02d:%02d", secs // 3600, (secs // 60) % 60, secs % 60)
            end)
            render.text(x, y, txt, theme.sub, 13, true)
            y = y + 16
        end

        if ph_streak:get() then
            render.text(x, y, cached("p_streak", function()
                return string.format("Streak %d  (best %d)", streak, bestStreak)
            end), streak > 0 and theme.good or theme.sub, 13, true)
            y = y + 16
        end

        if ph_vitals:get() and me then
            local hp = math.max(0, math.min(100, entity.get_player_health(me) or 0))
            local ar = math.max(0, math.min(100, entity.get_player_armor(me) or 0))
            render.rect_filled(x, y + 2, 100, 6, theme.panel, 3, 1)
            render.rect_filled(x, y + 2, math.floor(hp), 6, hp > 35 and theme.good or theme.bad, 3, 2)
            render.rect_filled(x, y + 10, 100, 4, theme.panel, 2, 1)
            render.rect_filled(x, y + 10, math.floor(ar), 4, theme.accent, 2, 2)
            y = y + 20
        end

        if ph_target:get() then
            local t = currentTarget()
            if t and entity.is_alive(t) then
                render.text(x, y, string.format("Target %s  %d hp", tostring(nameOf(t)), entity.get_player_health(t)), theme.accent, 13, true)
            end
        end
    end)
end

-- HVH PLUS 2: weapon profiles, keybind overrides, close-range rules, respawn reset, warnings
local p_wp   = ptab:new_section("Weapon Profiles", "Left")
local wp_enable = p_wp:new_toggle("Weapon Profiles", false)
local wp_s_dmg  = p_wp:new_slider("Sniper Min Damage", 1, 100, 90, 0, "")
local wp_s_hc   = p_wp:new_slider("Sniper Hitchance", 1, 100, 70, 0, "%")
local wp_p_dmg  = p_wp:new_slider("Pistol Min Damage", 1, 100, 40, 0, "")
local wp_p_hc   = p_wp:new_slider("Pistol Hitchance", 1, 100, 60, 0, "%")
local wp_m_dmg  = p_wp:new_slider("SMG Min Damage", 1, 100, 30, 0, "")
local wp_m_hc   = p_wp:new_slider("SMG Hitchance", 1, 100, 55, 0, "%")
local wp_o_dmg  = p_wp:new_slider("Rifle / Other Min Damage", 1, 100, 45, 0, "")
local wp_o_hc   = p_wp:new_slider("Rifle / Other Hitchance", 1, 100, 65, 0, "%")

local p_ko   = ptab:new_section("Keybind Overrides", "Right")
local ko_dmg_on  = p_ko:new_keybind("Damage Override", "Hold", "G")
local ko_dmg_val = p_ko:new_slider("Override Min Damage", 1, 100, 10, 0, "")
local ko_hc_on   = p_ko:new_keybind("Hitchance Override", "Hold", "H")
local ko_hc_val  = p_ko:new_slider("Override Hitchance", 1, 100, 30, 0, "%")
local ko_head_on = p_ko:new_keybind("Head Only", "Hold", "J")
local pl_close   = p_ko:new_toggle("Lower Hitchance At Close Range", false)
local pl_close_d = p_ko:new_slider("Close Range Under", 3, 60, 20, 0, " studs")
local pl_close_h = p_ko:new_slider("Close Range Hitchance", 1, 100, 35, 0, "%")
local pl_respawn = p_ko:new_toggle("Reset Resolver On Enemy Respawn", true)
local pl_lowhp   = p_ko:new_toggle("Low HP Warning", false)
local pl_lowhp_v = p_ko:new_slider("Warn Below", 5, 60, 30, 0, " hp")

do
    local function weaponClass(name)
        name = string.lower(tostring(name or ""))
        if name:find("awp") or name:find("sniper") or name:find("scout") or name:find("ssg") or name:find("g3sg") then
            return "Sniper"
        elseif name:find("deagle") or name:find("revolver") or name:find("pistol") or name:find("glock")
            or name:find("usp") or name:find("p250") or name:find("five") then
            return "Pistol"
        elseif name:find("smg") or name:find("mp5") or name:find("mp7") or name:find("mp9") or name:find("p90")
            or name:find("ump") or name:find("mac10") or name:find("bizon") then
            return "SMG"
        end
        return "Other"
    end

    local function profile(cls)
        if cls == "Sniper" then return wp_s_dmg:get(), wp_s_hc:get()
        elseif cls == "Pistol" then return wp_p_dmg:get(), wp_p_hc:get()
        elseif cls == "SMG" then return wp_m_dmg:get(), wp_m_hc:get() end
        return wp_o_dmg:get(), wp_o_hc:get()
    end

    local wpLast, wpOn = nil, false
    local active = { dmg = false, hc = false, head = false, close = false }

    -- hand control back to the normal ragebot overrides on the next tick
    local function handBack()
        rbSig = nil
        wpLast = nil
    end

    onTick(function()
        local tc = globals.tickcount()

        -- weapon profile
        if wp_enable:get() then
            local me = entity.get_local_player()
            local ok, nm = pcall(entity.get_player_weapon_name, me)
            local cls = weaponClass(ok and nm or "")
            if cls ~= wpLast or tc % 16 == 0 then
                local d, h = profile(cls)
                rage.override_min_damage(d)
                rage.override_hitchance(h)
                wpLast, wpOn = cls, true
            end
        elseif wpOn then
            wpOn = false
            handBack()
        end

        -- keybind overrides (held = on, released = back to normal)
        local kd = ko_dmg_on:get()
        if kd then rage.override_min_damage(ko_dmg_val:get()) end
        if active.dmg and not kd then handBack() end
        active.dmg = kd

        local kh = ko_hc_on:get()
        if kh then rage.override_hitchance(ko_hc_val:get()) end
        if active.hc and not kh then handBack() end
        active.hc = kh

        local khead = ko_head_on:get()
        if khead then rage.override_hitboxes({ "head" }) end
        if active.head and not khead then handBack() end
        active.head = khead

        -- close range: easier hits at point blank
        local closeNow = false
        if pl_close:get() and not kh then
            local t = curTarget()
            local me = entity.get_local_player()
            if t and t.player and me and entity.is_alive(t.player) then
                local d = (entity.get_player_position(t.player) - entity.get_player_position(me)).Magnitude
                if d <= pl_close_d:get() then
                    rage.override_hitchance(pl_close_h:get())
                    closeNow = true
                end
            end
        end
        if active.close and not closeNow then handBack() end
        active.close = closeNow
    end)

    -- reset per-enemy resolver memory when an enemy comes back to life
    local wasAlive = {}
    onTick(function()
        if not pl_respawn:get() or globals.tickcount() % 8 ~= 0 then return end
        for _, e in ipairs(entity.get_enemies()) do
            local id = keyOf(e)
            local al = entity.is_alive(e)
            if al and wasAlive[id] == false then
                targetState[id] = nil
                yawHist[id] = nil
                psetClear()
            end
            wasAlive[id] = al
        end
    end)

    p_wp:new_button("Print Weapon Class", function()
        local me = entity.get_local_player()
        local ok, nm = pcall(entity.get_player_weapon_name, me)
        local cls = weaponClass(ok and nm or "")
        local d, h = profile(cls)
        client.log(string.format("[weapon] name=%s class=%s dmg=%d hc=%d", tostring(nm), cls, d, h))
        notify("Weapon", string.format("%s -> %s (dmg %d, hc %d)", tostring(nm), cls, d, h), 3, false)
    end)

    onEvent("paint", function()
        if not pl_lowhp:get() then return end
        local me = entity.get_local_player()
        if not me then return end
        local hp = entity.get_player_health(me) or 100
        if hp > 0 and hp <= pl_lowhp_v:get() then
            local sw, sh = render.screen_size()
            local pulse = 0.6 + 0.4 * math.sin(globals.realtime() * 6)
            render.text(sw / 2, sh * 0.72, "LOW HP  " .. math.floor(hp), theme.bad, 16 + math.floor(pulse * 2), true, true)
        end
    end)
end

-- PRESETS, SHOT LOG, RESOLVER PANEL (HVH Plus tab)
local p_pre   = ptab:new_section("Presets", "Right")
local pr_aa   = p_pre:new_combobox("Anti-Aim Preset", { "Custom", "Legit", "Jitter", "Spin", "Max Sway", "Low Delta" }, "Custom")
local pr_rage = p_pre:new_combobox("Ragebot Preset", { "Custom", "Safe", "Balanced", "Aggressive", "Hail Mary" }, "Custom")

local p_log   = ptab:new_section("Shot Log & Panels", "Left")
local pv_log   = p_log:new_toggle("On-Screen Shot Log", true)
local pv_log_n = p_log:new_slider("Log Lines", 3, 12, 6, 0, "")
local pv_log_t = p_log:new_slider("Log Time", 2, 15, 6, 0, " s")
local pv_res   = p_log:new_toggle("Resolver Panel", false)

do
    -- every preset only sets the normal menu elements, so they stay editable afterwards
    local AA_PRESETS = {
        Legit      = { pitch = "Zero", yaw = 180, mod = "Disabled", sway = 0,  desync = 30, lag = 2,  var = 0 },
        Jitter     = { pitch = "Down", yaw = 180, mod = "Center",   sway = 35, desync = 58, lag = 6,  var = 20 },
        Spin       = { pitch = "Down", yaw = 180, mod = "Spin",     sway = 0,  desync = 58, lag = 8,  var = 20 },
        ["Max Sway"] = { pitch = "Down", yaw = 180, mod = "Sway",   sway = 60, desync = 86, lag = 10, var = 30 },
        ["Low Delta"] = { pitch = "Down", yaw = 180, mod = "Disabled", sway = 0, desync = 25, lag = 4, var = 10 },
    }
    pr_aa:set_callback(function()
        local p = AA_PRESETS[pr_aa:get()]
        if not p then return end
        aa_pitch:set(p.pitch); aa_yaw:set(p.yaw); aa_mod:set(p.mod); aa_sway_amt:set(p.sway)
        aa_desync:set(p.desync); aa_lag:set(p.lag); aa_lag_var:set(p.var)
        notify("Preset", "Anti-aim preset: " .. pr_aa:get(), 2, false)
    end)

    local RAGE_PRESETS = {
        Safe       = { dmg = 60, hc = 80, baim = 2, miss = 2 },
        Balanced   = { dmg = 40, hc = 65, baim = 2, miss = 2 },
        Aggressive = { dmg = 20, hc = 45, baim = 3, miss = 3 },
        ["Hail Mary"] = { dmg = 1, hc = 20, baim = 5, miss = 5 },
    }
    pr_rage:set_callback(function()
        local p = RAGE_PRESETS[pr_rage:get()]
        if not p then return end
        rb_dmg:set(p.dmg); rb_hc:set(p.hc); res_baim:set(p.baim); res_miss:set(p.miss)
        notify("Preset", "Ragebot preset: " .. pr_rage:get(), 2, false)
    end)

    -- shot log
    local lines = {}
    local function push(text, col)
        lines[#lines + 1] = { text = text, col = col, t = globals.realtime() }
        while #lines > 12 do table.remove(lines, 1) end
    end

    onEvent("aim_hit", function(e)
        push(string.format("Hit %s  %s  -%s", tostring(nameOf(e.target)), tostring(e.hitbox or "?"), tostring(e.damage or "?")), theme.good)
    end)
    onEvent("aim_miss", function(e)
        push(string.format("Missed %s  %s  (%s)", tostring(nameOf(e.target)), tostring(e.hitbox or "?"), tostring(e.reason or "?")), theme.bad)
    end)

    onEvent("paint", function()
        local doLog, doRes = pv_log:get(), pv_res:get()
        if not (doLog or doRes) then return end
        local sw, sh = render.screen_size()

        if doLog and #lines > 0 then
            local now = globals.realtime()
            local life = pv_log_t:get()
            local maxN = pv_log_n:get()
            local x, y = sw - 280, 200
            local shown = 0
            for i = #lines, 1, -1 do
                local ln = lines[i]
                if now - ln.t <= life and shown < maxN then
                    render.text(x, y + shown * 15, ln.text, ln.col, 13, true)
                    shown = shown + 1
                end
            end
        end

        if doRes then
            local x, y = 20, math.floor(sh * 0.28)
            render.text(x, y, "RESOLVER", theme.accent, 13, true)
            local rows = cached("res_panel", function()
                local out = {}
                for _, e in ipairs(entity.get_enemies()) do
                    if entity.is_alive(e) then
                        local st = targetState[keyOf(e)]
                        local ang = st and BRUTE_ANGLES[st.stage] or 0
                        out[#out + 1] = string.format("%s  %d deg  miss %d", tostring(nameOf(e)), ang, st and st.misses or 0)
                    end
                end
                return out
            end)
            for i, txt in ipairs(rows) do
                if i > 8 then break end
                render.text(x, y + i * 15, txt, theme.text, 12, true)
            end
        end
    end)
end

-- DESYNC ENGINE (HVH Plus tab)
-- Drives the body yaw directly every tick, after all other anti-aim code,
-- using only the documented trio: override_body_yaw / override_inverter /
-- override_desync_limits. The side is picked by the mode below.
local p_ds       = ptab:new_section("Desync Engine", "Left")
local ds_enable  = p_ds:new_toggle("Desync Engine", true)
local ds_mode    = p_ds:new_combobox("Side Mode", { "Static", "Jitter", "Random", "Freestanding", "Flip On Hit" }, "Jitter")
local ds_left    = p_ds:new_slider("Left Limit", 0, 86, 58, 0, "°")
local ds_right   = p_ds:new_slider("Right Limit", 0, 86, 58, 0, "°")
local ds_rand    = p_ds:new_slider("Randomize Amount", 0, 30, 0, 0, "°")
local ds_ticks   = p_ds:new_slider("Flip Every", 1, 16, 4, 0, " ticks")
local ds_ghost   = p_ds:new_toggle("Show Fake Model", true)
local ds_ind     = p_ds:new_toggle("Desync Indicator", true)

do
    local ds = { rnd = false, nextFlip = 0, hitSide = false, lastHp = nil, inv = false, lim = 0 }

    -- the state-based desync (HVH Extras) calls override_desync every tick and would fight
    -- with this engine, so it is switched off when the engine is switched on
    ds_enable:set_callback(function()
        if ds_enable:get() and st_enable:get() then
            st_enable:set(false, true)
            notify("Desync", "State-based desync turned off (engine is active)", 3, false)
        end
    end)

    if ds_enable:get() and st_enable:get() then st_enable:set(false, true) end

    local function wrap(d) return (d + 180) % 360 - 180 end

    local function freestandSide()
        local me = entity.get_local_player()
        if not me then return nil end
        local myPos = entity.get_player_position(me)
        local best, bestPos
        for _, e in ipairs(entity.get_enemies()) do
            if entity.is_alive(e) then
                local p = entity.get_player_position(e)
                local d = (p - myPos).Magnitude
                if not best or d < best then best, bestPos = d, p end
            end
        end
        if not bestPos then return nil end
        local _, myYaw = entity.get_player_angles_deg(me)
        local dir = bestPos - myPos
        local toEnemy = math.deg(math.atan2(-dir.X, -dir.Z))
        local delta = wrap(toEnemy - myYaw)
        -- fake side faces the enemy: enemy on the left -> inverter false (fake left)
        return delta <= 0
    end

    onTick(function()
        if not (ds_enable:get() and aa_enable:get()) then return end
        local tc = globals.tickcount()
        local mode = ds_mode:get()
        local step = ds_ticks:get()
        local inv = false

        if mode == "Jitter" then
            inv = (math.floor(tc / step) % 2 == 1)
        elseif mode == "Random" then
            if tc >= ds.nextFlip then
                ds.rnd = math.random() < 0.5
                ds.nextFlip = tc + step * math.random(1, 3)
            end
            inv = ds.rnd
        elseif mode == "Freestanding" then
            local f = freestandSide()
            if f == nil then f = ds.inv end
            inv = f
        elseif mode == "Flip On Hit" then
            local me = entity.get_local_player()
            local hp = me and entity.get_player_health(me)
            if hp then
                if ds.lastHp and hp < ds.lastHp then ds.hitSide = not ds.hitSide end
                ds.lastHp = hp
            end
            inv = ds.hitSide
        end

        -- the Invert Side key still flips whatever the mode chose
        if aa_invert:get() then inv = not inv end
        ds.inv = inv

        local r = ds_rand:get()
        local l = ds_left:get()
        local rt = ds_right:get()
        if r > 0 then
            l = math.max(0, math.min(86, l + math.random(-r, r)))
            rt = math.max(0, math.min(86, rt + math.random(-r, r)))
        end
        ds.lim = inv and rt or l

        aa.override_body_yaw(true)
        aa.override_inverter(inv)
        aa.override_desync_limits(l, rt)
        if ds_ghost:get() then aa.override_show_fake(true) end
    end)

    local function readout()
        local ok1, fake = pcall(aa.get_fake_lby_deg)
        local ok2, real = pcall(aa.get_lby_deg)
        local ok3, twist = pcall(aa.get_twist_deg)
        return ok1 and fake or 0, ok2 and real or 0, ok3 and twist or 0
    end

    p_ds:new_button("Print Desync Debug", function()
        local fake, real, twist = readout()
        client.log(string.format("[desync] engine=%s mode=%s side=%s limit=%d fakeFeet=%.1f realFeet=%.1f twist=%.1f choke=%s",
            tostring(ds_enable:get()), ds_mode:get(), ds.inv and "right" or "left", ds.lim, fake, real, twist,
            tostring(aa.is_fake_lag_choking())))
        notify("Desync", string.format("twist %.0f° | fake %.0f° | real %.0f°", twist, fake, real), 3, false)
    end)

    onEvent("paint", function()
        if not (ds_ind:get() and ds_enable:get() and aa_enable:get()) then return end
        local sw, sh = render.screen_size()
        local snap = cached("ds_ind", function()
            local _, _, tw = readout()
            return { tw = tw, l1 = string.format("DESYNC %s  %d°", ds.inv and "RIGHT" or "LEFT", ds.lim),
                     l2 = string.format("twist %d°", math.floor(tw + 0.5)) }
        end)
        local twist = snap.tw
        local x, y = 20, math.floor(sh * 0.5) + 110
        render.text(x, y, snap.l1, theme.accent, 13, true)
        render.text(x, y + 16, snap.l2, theme.sub, 12, true)
        local frac = math.max(0, math.min(1, math.abs(twist) / 86))
        render.rect_filled(x, y + 32, 100, 6, theme.panel, 3, 1)
        if frac > 0 then render.rect_filled(x, y + 32, math.floor(100 * frac), 6, theme.accent, 3, 2) end
    end)
end

-- CONFIG SHARING: "Show Code" / "Load Code" (codes start with SKEED)
local share_sec = ttab:new_section("Config Sharing", "Right")

local CODE_PREFIX = "SKEED"
local CODE_VERSION = 17

-- every setting that gets exported (order matters, keep it stable!)
-- keybinds are not included: their key choice isn't readable from Lua
local CFG = {
    aa_enable, aa_pitch, aa_yaw, aa_mod, aa_sway_amt, aa_desync, aa_lag, aa_lag_var,
    res_enable, res_mode, res_baim, res_miss,
    rb_enable, rb_dmg, rb_hc, rb_target,
    v_chams, v_chams_mat, v_vis_col, v_hid_col, v_hud, v_target3d,
    m_hitsound, m_killsound, m_clantag, m_tag_text, m_tag_anim, m_killsay,
    st_enable, st_stand, st_run, st_crouch, st_air,
    def_enable, def_interval,
    wp_enable, wp_sniper, wp_pistol, wp_other,
    xv_watermark, xv_stats, xv_predict, xv_pred_tick, u_log,
    fl_state, fl_stand, fl_run, fl_air,
    sr_anim, sr_air_sp, yp_enable, yp_time, yp_jitter,
    pl_lethal, pl_lethal_h, pl_baim, pl_baim_hp, pl_air, pl_air_hc, pl_move, pl_move_spd, pl_move_hc,
    ph_dt, ph_speed, ph_enemies, ph_near, ph_target,
    ph_timer, ph_streak, ph_vitals, pf_rate, pf_hat,
    wp_enable, wp_s_dmg, wp_s_hc, wp_p_dmg, wp_p_hc, wp_m_dmg, wp_m_hc, wp_o_dmg, wp_o_hc,
    ko_dmg_val, ko_hc_val, pl_close, pl_close_d, pl_close_h, pl_respawn, pl_lowhp, pl_lowhp_v,
    pv_log, pv_log_n, pv_log_t, pv_res,
    ds_enable, ds_mode, ds_left, ds_right, ds_rand, ds_ticks, ds_ghost, ds_ind,
    h_cross, h_keys, h_hitlog, h_weapon,
    sp_enable, sp_speed, sp_maxspd, sp_scope, sp_adapt, sp_step,
    x_fake, x_ext_on, x_ext_amt, x_fpitch,
    m_hs_id, m_hs_vol, m_hs_pitch,
    -- new controls are appended at the end
    sp_noscope, sp_crouch, sp_moving,
    xv_wire, xv_wire_col, xv_ring, xv_wm_text, h_speed, h_spread,
    xv_hat, xv_hat_col, xv_hat_r, xv_hat_h, xv_hat_spin, xv_hat_flip, xv_hat_off,
    esp_enable, esp_name, esp_dist, esp_health, esp_weapon, esp_res, esp_snap, esp_col,
    hm_enable, hm_col, cx_enable, cx_size, cx_gap, cx_thick, cx_dot, cx_col,
    fov_enable, fov_r, fov_col, am_enable, am_pct,
    cu_enable, cu_style, cu_size, cu_speed, cu_col, cu_hide, cu_offx, cu_offy,
    sc_enable, sc_gap, sc_thick, sc_dot, sc_col, sc_hide,
    st_stand_real, st_stand_fake, st_run_real, st_run_fake,
    st_crouch_real, st_crouch_fake, st_air_real, st_air_fake,
}

-- base64 (pure Lua)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64IDX = {}
for i = 1, 64 do B64IDX[string.sub(B64, i, i)] = i - 1 end

local function b64enc(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = string.byte(s, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = string.sub(B64, c1 + 1, c1 + 1)
            .. string.sub(B64, c2 + 1, c2 + 1)
            .. (b and string.sub(B64, c3 + 1, c3 + 1) or "=")
            .. (c and string.sub(B64, c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function b64dec(s)
    s = (string.gsub(s, "[^%w%+/=]", ""))
    local out = {}
    for i = 1, #s, 4 do
        local ch1, ch2 = string.sub(s, i, i), string.sub(s, i + 1, i + 1)
        local ch3, ch4 = string.sub(s, i + 2, i + 2), string.sub(s, i + 3, i + 3)
        local n1, n2 = B64IDX[ch1], B64IDX[ch2]
        if not n1 or not n2 then return nil end
        local n3, n4 = B64IDX[ch3] or 0, B64IDX[ch4] or 0
        local n = n1 * 262144 + n2 * 4096 + n3 * 64 + n4
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if ch3 ~= "=" and ch3 ~= "" then
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if ch4 ~= "=" and ch4 ~= "" then
            out[#out + 1] = string.char(n % 256)
        end
    end
    return table.concat(out)
end

local function encodeConfig()
    local values = {}
    for i, h in ipairs(CFG) do
        local v = h:get()
        if typeof(v) == "Color3" then
            v = {
                math.floor(v.R * 255 + 0.5),
                math.floor(v.G * 255 + 0.5),
                math.floor(v.B * 255 + 0.5),
            }
        end
        values[i] = v
    end
    return CODE_PREFIX .. b64enc(json.stringify({ v = CODE_VERSION, n = #CFG, d = values }))
end

-- returns ok, message
local function decodeConfig(code)
    code = string.gsub(tostring(code or ""), "%s", "")
    if code == "" then
        return false, "No code entered"
    end
    if string.sub(code, 1, #CODE_PREFIX) ~= CODE_PREFIX then
        return false, "Invalid code (must start with " .. CODE_PREFIX .. ")"
    end

    local raw = b64dec(string.sub(code, #CODE_PREFIX + 1))
    if not raw then
        return false, "Code is corrupted"
    end

    local ok, data = pcall(json.parse, raw)
    if not ok or type(data) ~= "table" or type(data.d) ~= "table" then
        return false, "Code is corrupted"
    end
    if data.v ~= CODE_VERSION or data.n ~= #CFG then
        return false, "Code is from a different script version"
    end

    for i, h in ipairs(CFG) do
        local val = data.d[i]
        if val ~= nil then
            if type(val) == "table" then
                val = Color3.fromRGB(val[1] or 255, val[2] or 255, val[3] or 255)
            end
            pcall(function() h:set(val) end)
        end
    end
    return true, "Config loaded"
end

-- UI
local code_out = share_sec:new_textbox("Your Code", "Press Show Code", "")
share_sec:new_button("Show Code", function()
    local code = encodeConfig()
    code_out:set(code)
    client.log("[config code] " .. code)
    pcall(function() setclipboard(code) end) -- copies too, if the executor supports it
    notify("Config", "Code generated (also in the console)", 3, false)
end)

local code_in = share_sec:new_textbox("Paste Code", "Paste a SKEED code here", "")
share_sec:new_button("Load Code", function()
    local ok, msg = decodeConfig(code_in:get())
    if ok then
        notify("Config", msg, 3, true)
    else
        notify("Config", msg, 4, false)
        client.error(msg)
    end
end)

-- GLOBAL CHAT TAB + HELPER TAB (filter + premade Q&A data live here)

-- Profanity filter (always on)
local LEET = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t", ["@"] = "a", ["$"] = "s", ["!"] = "i" }

local function collapse(s)
    local out, last = {}, ""
    for ch in string.gmatch(s, ".") do
        if ch ~= last then
            out[#out + 1] = ch
            last = ch
        end
    end
    return table.concat(out)
end

local function lettersOnly(s)
    local lowered = string.lower(s)
    lowered = string.gsub(lowered, "[013457@%$!]", LEET)
    return (string.gsub(lowered, "[^%a]", ""))
end

-- matched anywhere inside a word (long, unambiguous words)
local SUBSTRING_WORDS = { "fuck", "shit", "bitch", "cunt", "asshole", "putain", "connard", "salope", "encule" }
-- matched only as a whole word (short words that appear inside innocent ones)
local WHOLE_WORDS = { "dick", "pussy", "bastard", "whore", "slut", "nique", "merde", "retard", "fag", "faggot", "nigga", "nigger", "fck", "fvck", "fuk", "sht", "btch" }

local SUB_C, WHOLE_SET = {}, {}
for _, w in ipairs(SUBSTRING_WORDS) do SUB_C[#SUB_C + 1] = collapse(w) end
for _, w in ipairs(WHOLE_WORDS) do WHOLE_SET[collapse(w)] = true end
-- innocent words that contain a blocked word
local ALLOW_SET = { [collapse("scunthorpe")] = true }

local function isBad(norm)
    if #norm == 0 then return false end
    local c = collapse(norm)
    if ALLOW_SET[c] then return false end
    for _, w in ipairs(SUB_C) do
        if string.find(c, w, 1, true) then return true end
    end
    local noPlural = string.gsub(c, "s$", "")
    return WHOLE_SET[c] == true or WHOLE_SET[noPlural] == true
end

-- returns cleanedText, wasFiltered
local function filterText(text)
    local tokens = {}
    for tk in string.gmatch(tostring(text or ""), "%S+") do
        tokens[#tokens + 1] = tk
    end

    local bad = {}
    for i, tk in ipairs(tokens) do
        if isBad(lettersOnly(tk)) then bad[i] = true end
    end

    -- catch spaced-out letters like "f u c k"
    local i = 1
    while i <= #tokens do
        if #tokens[i] == 1 then
            local j, buf = i, ""
            while j <= #tokens and #tokens[j] == 1 do
                buf = buf .. lettersOnly(tokens[j])
                j += 1
            end
            if j - i >= 3 and isBad(buf) then
                for k = i, j - 1 do bad[k] = true end
            end
            i = j
        else
            i += 1
        end
    end

    local flagged = false
    for idx, tk in ipairs(tokens) do
        if bad[idx] then
            tokens[idx] = string.rep("*", #tk)
            flagged = true
        end
    end
    return table.concat(tokens, " "), flagged
end

-- Helper bot data (rule-based, not a real AI)
local FAQ = {
    { q = "How to load a skeed code?",
      a = "Open the HVH More tab > Config Sharing. Paste the code (it starts with SKEED) into Paste Code, then press Load Code. If it says wrong version, ask for a fresh code from the same script version.",
      kw = { "load", "code", "skeed", "import", "paste", "apply" } },
    { q = "How to share my config?",
      a = "HVH More > Config Sharing > press Show Code. Copy it from the box or the Lua console (Menu > Settings > Lua scripts > Open lua console) and send it. Keybinds are not included in codes. Cloud Configs in the Chat tab give you a short ID instead.",
      kw = { "share", "show code", "export", "give", "send config", "friend", "my config" } },
    { q = "How do I turn on anti-aim?",
      a = "HVH Config > Anti-Aim: enable it, then set Pitch to Down, Yaw Offset 180 and Desync 58 to start. Invert Side flips the fake, and Fake Lag 8 is a good default.",
      kw = { "anti", "aa", "desync", "yaw", "pitch", "enable" } },
    { q = "How do manual AA keys work?",
      a = "HVH Extras > Advanced AA has Manual Left / Right / Back keybinds (Toggle mode). Press one to force that direction. A MANUAL indicator shows near your crosshair. Press it again to turn it off.",
      kw = { "manual", "left", "right", "back", "arrow", "direction" } },
    { q = "Why am I missing shots?",
      a = "Check the Hit/Miss stats top-left. Resolver misses: try Brute-force mode or lower BAim After Misses. Spread misses: use the Spread Helper and scope in. Occlusion misses: lower Min Damage.",
      kw = { "miss", "missing", "resolver", "hit", "accuracy", "shots" } },
    { q = "Why is the ragebot not shooting?",
      a = "Run HVH Extras > Utilities > Run API Self-Test and read the result. Make sure Override Ragebot is on and Min Damage is not too high. The Spread Helper (off by default) can pause fire. Script errors pop up as notifications and go to the Lua console.",
      kw = { "not shooting", "ragebot", "wont shoot", "doesnt shoot", "no fire", "shoot", "rage", "working" } },
    { q = "What does the Spread Helper do?",
      a = "It cannot remove weapon spread. It selects a hitchance for unscoped snipers, crouching, and moving, and can raise hitchance after spread misses. Optional gates can pause firing.",
      kw = { "spread", "nospread", "helper", "inaccuracy", "noscope", "no-scope", "crouch", "moving", "assist", "chance" } },
    { q = "What is Defensive AA?",
      a = "HVH Extras > Advanced AA > Defensive AA. When double-tap is charged it shifts ticks and flicks pitch and yaw for 2 ticks to throw enemy resolvers off. It's off by default.",
      kw = { "defensive", "double tap", "dt", "shift", "flick" } },
    { q = "How do I change hitsounds?",
      a = "HVH Config > Misc: pick a Hitsound and a Killsound preset. They reset automatically when the script unloads.",
      kw = { "hitsound", "killsound", "sound", "audio" } },
    { q = "How do I set a clantag?",
      a = "HVH Config > Misc: turn on Clantag, type your text and choose Static, Marquee or Typewriter. Tags are filtered by the server.",
      kw = { "clantag", "tag", "name tag", "marquee" } },
    { q = "What are the presets?",
      a = "HVH More > Presets has Legit, Rage and Max. They set yaw, desync, fake lag, min damage, hitchance and BAim. Save Custom Slot stores your own values.",
      kw = { "preset", "legit", "rage", "max", "slot", "save" } },
    { q = "How do I use the global chat?",
      a = "Open the Chat tab. Enter the Server URL and a nickname, then turn on Connect To Global Chat. Type in Message and press Send Message. Messages show inside the Chat tab under Global Chat. It never goes to the Roblox chat.",
      kw = { "chat", "global", "connect", "server", "url", "nickname", "message", "send" } },
    { q = "How do the cursors work?",
      a = "HVH More > Cursor. Custom Cursor draws a spinning crosshair, diamond, triangle or star at your mouse and hides the normal one. Sniper Cursor draws its own scope reticle while a sniper is scoped in, in place of the game's. Size, speed, gap and colors are adjustable.",
      kw = { "cursor", "mouse", "pointer", "sniper", "scope", "reticle", "rotate", "spin" } },
    { q = "What is in the HVH ESP tab?",
      a = "Enemy ESP shows names, distance, a health bar, their weapon, resolver info and snaplines (turn on Enemy ESP first). Aim Helpers has a hitmarker, a custom crosshair, an FOV circle and a low ammo warning. Everything is off by default.",
      kw = { "esp", "name", "health", "snapline", "hitmarker", "crosshair", "fov", "ammo", "warning" } },
    { q = "What extra visuals are there?",
      a = "HVH Extras > Extra Visuals has Enemy Wire Boxes, Target Ring, China Hat (a spinning cone above your head, on/off toggle), path prediction and an editable Watermark Text. HVH More > HUD can show speed and state, plus spread and inaccuracy, under your crosshair.",
      kw = { "visual", "wire", "box", "ring", "watermark", "esp", "hud", "indicator", "speed", "hat", "china", "chinese" } },
    { q = "How do cloud configs work?",
      a = "Chat tab > Cloud Configs. Press Upload My Config to get a short ID and send that ID to a friend. They paste it in Config ID and press Download Config. It needs the Server URL set. Keybinds are not included.",
      kw = { "cloud", "config id", "upload", "download", "online config", "id" } },
    { q = "Why was my message blocked?",
      a = "The profanity filter blocks swearing, even with symbols or spaced-out letters. Rephrase and try again. Incoming messages are censored the same way.",
      kw = { "blocked", "filter", "censor", "swear", "profanity", "stars" } },
    { q = "How do I change the UI theme?",
      a = "HVH More > Theme. Pick a preset, Rainbow, or Custom with your own accent color. Apply Theme To Visual Colors also recolors chams, hat, wire boxes and cursors. Your choice is saved.",
      kw = { "theme", "color", "colour", "style", "rainbow", "accent", "skin" } },
}

local function findAnswer(query)
    local q = string.lower(query)
    local best, bestScore = nil, 0
    for _, entry in ipairs(FAQ) do
        local score = 0
        for _, kw in ipairs(entry.kw) do
            if string.find(q, kw, 1, true) then score += 1 end
        end
        if score > bestScore then
            best, bestScore = entry, score
        end
    end
    return best
end

-- GLOBAL CHAT TAB + HELPER TAB
-- (scoped in do ... end so the locals don't pile up in the main chunk)
do

local WHITE  = Color3.fromRGB(255, 255, 255)
local GRAY   = Color3.fromRGB(150, 155, 170)
local GREEN  = Color3.fromRGB(120, 255, 160)
local ACCENT = Color3.fromRGB(70, 130, 240)
local PANEL  = Color3.fromRGB(20, 22, 30)
local WRAP_CHARS = 40

local function wrap(text, width)
    local lines, cur = {}, ""
    for word in string.gmatch(tostring(text), "%S+") do
        if cur == "" then
            cur = word
        elseif #cur + #word + 1 > width then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = cur .. " " .. word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

local function trim(s)
    return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1"))
end

-- GLOBAL CHAT (talks to your relay server, NOT the Roblox chat)
-- Put the address of your relay server here (see skeed-chat-server/server.js),
-- e.g. "https://skeed-chat-server.onrender.com". It can also be typed in the menu.
local DEFAULT_SERVER_URL = "https://skeed.onrender.com"
local POLL_SECONDS = 4

local ctab       = menu.new_tab("Chat", ICON)
local c_log_sec  = ctab:new_section("Global Chat", "Left")
local c_send_sec = ctab:new_section("Send Message", "Left")
local c_conn_sec = ctab:new_section("Connection", "Right")
local c_view_sec = ctab:new_section("Display Options", "Right")

local defaultNick = "player"
do
    local ok, nm = pcall(function() return game:GetService("Players").LocalPlayer.Name end)
    if ok and nm then
        local cleaned = string.gsub(tostring(nm), "[^%w_%.%- ]", "")
        if #cleaned >= 2 then defaultNick = string.sub(cleaned, 1, 24) end
    end
end

local c_online = c_conn_sec:new_toggle("Connect To Global Chat", false)
local c_url    = c_conn_sec:new_textbox("Server URL", "https://your-server.example", DEFAULT_SERVER_URL)
local c_nick   = c_conn_sec:new_textbox("Nickname", "2-24 letters/numbers", defaultNick)
local c_status = c_conn_sec:new_textbox("Status", "", "offline")

local c_input  = c_send_sec:new_textbox("Message", "Type a message...", "")
c_send_sec:new_label("Profanity filter is always on.")

-- chat window settings
local c_overlay  = c_view_sec:new_toggle("Also Show On Screen (optional)", false)
local c_ox       = c_view_sec:new_slider("On-Screen X", 0, 90, 1, 0, "%")
local c_oy       = c_view_sec:new_slider("On-Screen Y", 0, 90, 38, 0, "%")
local c_olines   = c_view_sec:new_slider("On-Screen Lines", 4, 16, 10, 0, " lines")
local c_menuonly = c_view_sec:new_toggle("Only While Menu Is Open", false)
local c_toast    = c_view_sec:new_toggle("Pop-Up New Messages", false)

-- the chat log lives inside the tab: one read-only-style text box per line
local MAX_LOG = 12
local logBoxes = {}
for i = 1, MAX_LOG do
    logBoxes[i] = c_log_sec:new_textbox(" ", "", "")
end

local YELLOW = Color3.fromRGB(255, 210, 90)

-- theme hook: panels and new chat lines follow the active theme
themeHooks[#themeHooks + 1] = function()
    WHITE, GRAY, GREEN, ACCENT, PANEL, YELLOW =
        theme.text, theme.sub, theme.good, theme.header, theme.panel, theme.warn
end
pcall(function()
    WHITE, GRAY, GREEN, ACCENT, PANEL, YELLOW =
        theme.text, theme.sub, theme.good, theme.header, theme.panel, theme.warn
end)

local onlineNow, lastMotd = 0, ""

local function urlSafe(s)
    return (string.gsub(s, "[^%w_%.%-]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local statusText = "offline"
local function setStatus(text)
    statusText = text
    pcall(function() c_status:set(text, true) end)
end

-- log (wrapped lines, newest last)
local logLines = {}

local function refreshLog()
    for i = 1, MAX_LOG do
        local ln = logLines[#logLines - MAX_LOG + i]
        pcall(function() logBoxes[i]:set(ln and ln.text or "", true) end)
    end
    pcall(function() c_status:set(statusText, true) end)
end

local function addLine(who, text, col)
    local full = string.format("[%s] %s", who, text)
    for i, chunk in ipairs(wrap(full, WRAP_CHARS)) do
        logLines[#logLines + 1] = { text = (i > 1 and "  " or "") .. chunk, col = col or WHITE }
    end
    while #logLines > 120 do table.remove(logLines, 1) end
    refreshLog()
    client.log("[chat] " .. full) -- also in the Lua console
end

c_view_sec:new_button("Clear Chat", function()
    for i = #logLines, 1, -1 do logLines[i] = nil end
    refreshLog()
end)

local function serverBase()
    local url = trim(c_url:get())
    url = string.gsub(url, "/+$", "")
    if string.sub(url, 1, 7) ~= "http://" and string.sub(url, 1, 8) ~= "https://" then
        return nil
    end
    return url
end

local function nickname()
    local n = trim(c_nick:get())
    if #n < 2 then n = defaultNick end
    return string.sub(n, 1, 24)
end

local function httpCall(opts)
    local ok, res = pcall(request, opts)
    if ok and type(res) == "table" then return res end
    return { Success = false, StatusCode = 0, Error = tostring(res) }
end

local function errorFromBody(res)
    local ok, data = pcall(http.json_decode, res.Body or "")
    if ok and type(data) == "table" and data.error then return tostring(data.error) end
    return res.Error or res.StatusMessage or ("HTTP " .. tostring(res.StatusCode))
end

-- polling
local lastId = 0
local backoff = 0

local function pollOnce()
    local base = serverBase()
    if not base then
        setStatus("enter a valid Server URL")
        return
    end

    local res = httpCall({ Url = base .. "/messages?after=" .. tostring(lastId) .. "&name=" .. urlSafe(nickname()), Method = "GET" })
    if not res.Success then
        if res.StatusCode == 429 then
            backoff = 8
            setStatus("rate limited, slowing down")
        else
            setStatus("can't reach server (" .. tostring(res.StatusCode) .. ")")
        end
        return
    end

    local ok, data = pcall(http.json_decode, res.Body or "")
    if not ok or type(data) ~= "table" then
        setStatus("server sent bad data")
        return
    end

    if type(data.last) == "number" and data.last < lastId then
        lastId = data.last -- server was restarted
    end

    if type(data.online) == "number" then onlineNow = data.online end
    if type(data.motd) == "string" and data.motd ~= "" and data.motd ~= lastMotd then
        lastMotd = data.motd
        addLine("server", data.motd, YELLOW)
    end

    local me = string.lower(nickname())
    for _, m in ipairs(data.messages or {}) do
        if type(m.id) == "number" and m.id > lastId then
            lastId = m.id
            -- second filter layer on the client, in case the server is outdated
            local name = filterText(tostring(m.name or "?"))
            local text = filterText(tostring(m.text or ""))
            local mine = string.lower(tostring(m.name or "")) == me
            local col = mine and GREEN or WHITE
            if tostring(m.name) == "SERVER" then col = YELLOW end
            addLine(name, text, col)
            if c_toast:get() and not mine then
                pcall(function() notify(name, text, 4, false) end)
            end
        end
    end
    setStatus("connected, " .. onlineNow .. " online")
end

task.spawn(function()
    while true do
        task.wait(POLL_SECONDS + backoff)
        backoff = 0
        if c_online:get() then
            local ok, err = pcall(pollOnce)
            if not ok then reportError("chat poll", err) end
        end
    end
end)

c_online:set_callback(function()
    if c_online:get() then
        setStatus("connecting...")
        task.spawn(function() pcall(pollOnce) end)
    else
        setStatus("offline")
    end
end)

-- sending
local lastSend = 0

local function sendMessage(raw)
    raw = trim(raw)
    if raw == "" then return end
    if #raw > 120 then raw = string.sub(raw, 1, 120) end

    local base = serverBase()
    if not base then
        addLine("system", "Set a valid Server URL first (http:// or https://).", GRAY)
        return
    end
    if not c_online:get() then
        addLine("system", "Turn on 'Connect To Global Chat' first.", GRAY)
        return
    end

    local now = globals.realtime()
    if now - lastSend < 1.5 then
        addLine("system", "Slow down a bit.", GRAY)
        return
    end

    local _, flagged = filterText(raw)
    if flagged then
        addLine("system", "Message blocked: please keep it clean.", GRAY)
        return
    end

    lastSend = now
    task.spawn(function()
        local res = httpCall({
            Url = base .. "/send",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = http.json_encode({ name = nickname(), text = raw }),
        })
        if res.Success then
            pcall(pollOnce) -- show our own message right away
        else
            addLine("system", "Not sent: " .. errorFromBody(res), GRAY)
        end
    end)
end

c_send_sec:new_button("Send Message", function()
    sendMessage(c_input:get())
    c_input:set("", true)
end)


-- cloud configs: upload your settings, share the short ID, download someone else's
local c_cloud_sec = ctab:new_section("Cloud Configs", "Right")
local c_cfg_id = c_cloud_sec:new_textbox("Config ID", "e.g. 7j32nn", "")

c_cloud_sec:new_button("Upload My Config", function()
    local base = serverBase()
    if not base then
        addLine("system", "Set a valid Server URL first.", GRAY)
        return
    end
    task.spawn(function()
        local res = httpCall({
            Url = base .. "/config/save",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = http.json_encode({ name = nickname(), code = encodeConfig() }),
        })
        local ok, data = false, nil
        if res.Success then ok, data = pcall(http.json_decode, res.Body or "") end
        if ok and type(data) == "table" and data.id then
            pcall(function() c_cfg_id:set(tostring(data.id), true) end)
            addLine("system", "Config uploaded. ID: " .. tostring(data.id) .. " (share this ID)", GREEN)
            pcall(function() notify("Cloud Config", "Uploaded. ID: " .. tostring(data.id), 6, false) end)
        else
            addLine("system", "Upload failed: " .. errorFromBody(res), GRAY)
        end
    end)
end)

c_cloud_sec:new_button("Download Config", function()
    local id = string.lower(trim(c_cfg_id:get()))
    if not string.match(id, "^[a-z0-9]+$") then
        addLine("system", "Enter a config ID first.", GRAY)
        return
    end
    local base = serverBase()
    if not base then
        addLine("system", "Set a valid Server URL first.", GRAY)
        return
    end
    task.spawn(function()
        local res = httpCall({ Url = base .. "/config/" .. id, Method = "GET" })
        if not res.Success then
            addLine("system", "Download failed: " .. errorFromBody(res), GRAY)
            return
        end
        local ok, data = pcall(http.json_decode, res.Body or "")
        if not ok or type(data) ~= "table" or type(data.code) ~= "string" then
            addLine("system", "Download failed: bad data from server.", GRAY)
            return
        end
        local loaded, msg = decodeConfig(data.code)
        if loaded then
            addLine("system", "Config " .. id .. " by " .. tostring(data.by) .. " loaded.", GREEN)
            pcall(function() notify("Cloud Config", "Loaded config " .. id, 4, false) end)
        else
            addLine("system", msg, GRAY)
        end
    end)
end)

addLine("system", "Global chat. Set the Server URL, then turn on Connect.", GRAY)

-- HELPER TAB (premade Q&A bot, separate tab)
local htab      = menu.new_tab("Helper", ICON)
local h_q_sec   = htab:new_section("Skeed Helper", "Left")
local h_ans_sec = htab:new_section("Answer", "Left")
local h_ask_sec = htab:new_section("Ask The Helper", "Right")

local questionNames = {}
for i, entry in ipairs(FAQ) do questionNames[i] = entry.q end

local h_toast   = h_ask_sec:new_toggle("Also Show As Pop-Up", false)
local h_overlay = h_ask_sec:new_toggle("Also Show On Screen (optional)", false)

-- the answer lives inside the tab: one text box per line
local MAX_ANSWER = 10
local answerBoxes = {}
for i = 1, MAX_ANSWER do
    answerBoxes[i] = h_ans_sec:new_textbox(" ", "", "")
end

local helperLines, helperTitle, helperUntil = {}, "", 0

local function setAnswer(text, title)
    helperLines = wrap(text, 40)
    helperTitle = title or "skeed helper"
    helperUntil = globals.realtime() + 60
    for i = 1, MAX_ANSWER do
        pcall(function() answerBoxes[i]:set(helperLines[i] or "", true) end)
    end
    client.log("[helper] " .. text) -- also in the Lua console
    if h_toast:get() then
        pcall(function() notify("Skeed Helper", text, 10, false) end)
    end
end

local function showQuestion(question)
    for _, entry in ipairs(FAQ) do
        if entry.q == question then
            setAnswer(entry.a, entry.q)
            return
        end
    end
end

local h_question = h_q_sec:new_combobox("Question", questionNames, questionNames[1], showQuestion)
h_q_sec:new_button("Show Answer", function()
    showQuestion(h_question:get())
end)
h_q_sec:new_button("Clear Answer", function()
    helperUntil = 0
    for i = 1, MAX_ANSWER do
        pcall(function() answerBoxes[i]:set("", true) end)
    end
end)

local function ask(query)
    query = trim(query)
    if query == "" then return end
    local _, flagged = filterText(query)
    if flagged then
        setAnswer("Let's keep it clean :) Try asking again without swearing.", "skeed helper")
        return
    end
    local entry = findAnswer(query)
    if entry then
        setAnswer(entry.a, entry.q)
    else
        setAnswer("I don't know that one yet. Try the Question list, or use words like 'code', 'resolver', 'anti-aim' or 'preset'.", "skeed helper")
    end
end

local h_ask = h_ask_sec:new_textbox("Your Question", "e.g. how do I load a code", "")
h_ask_sec:new_button("Ask Helper", function()
    ask(h_ask:get())
    h_ask:set("", true)
end)
h_ask_sec:new_label("Premade Q&A bot, not a real AI.")

setAnswer("Hi! I'm the Skeed Helper. Pick a question and press Show Answer, or type your own.", "skeed helper")

-- On-screen boxes (drawn with render, so they always update)
local LINE_H = 16

local function panel(x, y, w, title, lines, footer)
    local h = 26 + #lines * LINE_H + 10
    render.rect_filled(x, y, w, h, PANEL, 6, 1)
    render.rect_filled(x, y, w, 22, ACCENT, 6, 2)
    render.text(x + 8, y + 4, title, WHITE, 13, false, false, nil, 5)
    for i, ln in ipairs(lines) do
        render.text(x + 8, y + 26 + (i - 1) * LINE_H, ln.text, ln.col or WHITE, 13, true, false, nil, 5)
    end
end

onEvent("paint", function()
    local sw, sh = render.screen_size()

    -- global chat window
    if c_overlay:get() and (not c_menuonly:get() or ui.is_menu_open()) then
        local n = c_olines:get()
        local first = math.max(1, #logLines - n + 1)
        local shown = {}
        for i = first, #logLines do shown[#shown + 1] = logLines[i] end
        panel(math.floor(sw * c_ox:get() / 100), math.floor(sh * c_oy:get() / 100), 360,
            "skeed global chat  -  " .. statusText, shown)
    end

    -- helper answer
    if h_overlay:get() and globals.realtime() < helperUntil and #helperLines > 0 then
        local lines = {}
        for i, t in ipairs(helperLines) do lines[i] = { text = t } end
        panel(math.floor(sw / 2 - 230), math.floor(sh * 0.12), 460, "Helper: " .. helperTitle, lines)
    end
end)

-- API self-test (button in HVH Extras > Utilities)
x_misc:new_button("Run API Self-Test", function()
    local roots = {
        aa = aa, rage = rage, plist = plist, entity = entity, movement = movement,
        weapon = weapon, chams = chams, sounds = sounds, clantag = clantag,
        render = render, render3d = render3d, http = http, chat = chat,
        client = client, globals = globals, input = input, json = json, ui = ui,
    }
    local names = {
        "aa.override_pitch", "aa.override_yaw", "aa.override_yaw_modifier", "aa.override_body_yaw",
        "aa.override_inverter", "aa.override_desync_limits", "aa.override_fake_lag",
        "aa.override_fake_lag_limit", "aa.override_fake_lag_variability", "aa.set_manual",
        "aa.get_manual", "aa.get_inverter", "aa.is_fake_lag_choking", "aa.reset",
        "rage.set_resolver_enabled", "rage.set_resolver_mode", "rage.set_resolver_miss_limit",
        "rage.set_resolver_baim_after_misses", "rage.reset_resolver_state", "rage.override_enabled",
        "rage.override_min_damage", "rage.override_hitchance", "rage.override_target_selection",
        "rage.override_force_baim", "rage.override_force_safe_point", "rage.override_hitboxes",
        "rage.override_hitbox_priority", "rage.set_hitbox_config", "rage.get_target",
        "rage.get_min_damage", "rage.is_force_baim", "rage.is_force_safe_point",
        "rage.is_double_tap_charged", "rage.get_double_tap_charge", "rage.shift_ticks", "rage.reset",
        "plist.set", "plist.reset_all",
        "entity.get_enemies", "entity.is_alive", "entity.get_local_player", "entity.get_anim_state",
        "entity.get_info", "entity.get_player_position",
        "movement.get_state", "movement.get_speed", "movement.predict_position",
        "weapon.get_active", "weapon.is_scoped",
        "chams.set_enabled", "chams.override_visible", "chams.override_occluded", "chams.clear_overrides",
        "chams.get_materials", "sounds.override_hitsound", "sounds.override_killsound",
        "sounds.get_hitsound_names", "clantag.set", "clantag.reset",
        "render.text", "render.rect_filled", "render.measure_text", "render.screen_size", "render.clear",
        "render3d.box", "render3d.line", "render3d.sphere", "render3d.wire_box", "render3d.ring", "render.world_to_screen", "render.circle",
        "entity.get_player_health", "entity.get_player_weapon_name", "entity.get_player_hitbox_position",
        "weapon.get_ammo", "weapon.get_max_ammo", "weapon.is_reloading", "entity.get_local_player", "render.line", "render.circle_filled", "input.get_pointer_position",
        "weapon.get_spread", "weapon.get_inaccuracy", "sounds.play_hitsound", "sounds.play_killsound",
        "http.json_encode", "http.json_decode", "chat.on_message", "client.latency",
        "client.get_camera_angles_deg", "globals.realtime", "globals.tickcount",
        "input.is_typing", "json.stringify", "json.parse", "ui.is_menu_open",
    }

    local missing, total = {}, #names
    for _, path in ipairs(names) do
        local root, key = string.match(path, "^(%w+)%.(.+)$")
        local ok, v = pcall(function() return roots[root][key] end)
        if not ok or v == nil then missing[#missing + 1] = path end
    end

    for _, g in ipairs({ "notify", "request", "task" }) do
        total += 1
        local found = false
        if g == "notify" then found = notify ~= nil
        elseif g == "request" then found = request ~= nil
        else found = task ~= nil end
        if not found then missing[#missing + 1] = g end
    end

    if #missing == 0 then
        client.log("[self-test] all " .. total .. " API functions found")
        notify("Self-Test", "All " .. total .. " API functions found", 4, false)
    else
        client.error("[self-test] MISSING: " .. table.concat(missing, ", "))
        notify("Self-Test", #missing .. " of " .. total .. " missing - see Lua console", 8, false)
    end
end)

end -- do (chat + helper)

-- THEME MENU
do
    local tsec     = ttab:new_section("Theme", "Left")
    local names    = { "Default", "Ocean", "Sunset", "Purple", "Rose", "Mono", "Rainbow", "Custom" }

    local saved
    pcall(function() saved = database.read("skeed_theme") end)
    local startName = (type(saved) == "table" and THEMES[saved.name]) and saved.name or "Default"

    local t_sel    = tsec:new_combobox("UI Theme", names, startName)
    local t_custom = tsec:new_colorpicker("Custom Accent", Color3.fromRGB(0, 255, 160))

    local function buildCustom()
        local a = t_custom:get()
        local function mix(w) return Color3.new(a.R + (1 - a.R) * w, a.G + (1 - a.G) * w, a.B + (1 - a.B) * w) end
        THEMES.Custom = {
            accent = a, accent2 = mix(0.4), good = C(120,255,120), bad = C(255,100,100), warn = C(255,200,60),
            text = C(255,255,255), sub = C(200,200,200),
            panel = Color3.new(a.R * 0.15 + 0.04, a.G * 0.15 + 0.04, a.B * 0.15 + 0.05),
            header = a, target = a,
        }
    end

    local t_auto = tsec:new_toggle("Apply Theme To Visual Colors Automatically", true)

    local function pushVisuals()
        pcall(function() v_vis_col:set(theme.accent, true) end)
        pcall(function() v_hid_col:set(theme.accent2, true) end)
        pcall(function() xv_wire_col:set(theme.accent, true) end)
        pcall(function() xv_hat_col:set(theme.accent, true) end)
        pcall(function() cu_col:set(theme.accent, true) end)
        pcall(function() sc_col:set(theme.accent2, true) end)
    end

    local function choose(name, fromUser)
        if name == "Custom" then buildCustom() end
        applyTheme(name)
        -- only on a real change by the user; loading must not overwrite saved colors
        if fromUser and t_auto:get() and name ~= "Rainbow" then pushVisuals() end
        pcall(function()
            database.write("skeed_theme", { name = name })
            database.flush()
        end)
    end

    t_sel:set_callback(function() choose(t_sel:get(), true) end)
    t_custom:set_callback(function()
        if currentTheme == "Custom" then choose("Custom", true) end
    end)

    -- push the theme into the other color pickers (chams, hat, cursor, wire boxes)
    tsec:new_button("Apply Theme To Visual Colors", function()
        pushVisuals()
        notify("Theme", "Applied " .. currentTheme .. " to visual colors", 2, false)
    end)

    -- Rainbow animation
    local rainbowPush = 0
    onEvent("paint", function()
        if currentTheme ~= "Rainbow" then return end
        local h = (globals.realtime() * 0.15) % 1
        theme.accent  = Color3.fromHSV(h, 0.75, 1)
        theme.accent2 = Color3.fromHSV((h + 0.5) % 1, 0.75, 1)
        theme.header, theme.target = theme.accent, theme.accent2
        theme.panel = Color3.fromHSV(h, 0.5, 0.18)
        runThemeHooks()
        if t_auto:get() and globals.realtime() - (rainbowPush or 0) > 0.1 then
            rainbowPush = globals.realtime()
            pushVisuals()
        end
    end)

    choose(startName)
end

-- CLEANUP
onEvent("shutdown", function()
    aa.set_manual(nil)
    aa.reset()
    rage.reset()
    plist.reset_all()
    psetClear()
    chams.clear_overrides()
    sounds.reset_hitsound()
    sounds.reset_killsound()
    clantag.reset()
    render.clear()
    render3d.clear()
    _G.__hvh_reset_stats = nil
end)
