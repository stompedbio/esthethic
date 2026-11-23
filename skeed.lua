-- skeed
-- Tabs: HVH Config, HVH Extras, HVH More, Chat, Helper
-- Network use: only the Chat tab, and only to the Server URL you type in.
-- No loadstring, no obfuscation. Everything is reset when the script unloads.

local ICON = "rbxassetid://10734975692"

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
    local ok, t = pcall(rage.get_target)
    if not ok or type(t) ~= "table" or t.slot == nil or t.player == nil then return end
    local ok2, id = pcall(function() return t.player.UserId end)
    if ok2 and id then slotMap[t.slot] = id end
end

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
onTick(function(tick)
    if not aa_enable:get() then
        aa.reset()
        return
    end

    aa.override_pitch(aa_pitch:get())
    aa.override_yaw(aa_yaw:get(), "camera")

    local mod = aa_mod:get()
    if mod == "Sway" then
        local amt = aa_sway_amt:get()
        aa.override_yaw_modifier(function(t, baseYaw)
            return math.sin(t * 0.2) * amt
        end)
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
            plist.set(enemy, "Force body yaw", true)
            plist.set(enemy, "Override yaw offset", BRUTE_ANGLES[s.stage] or 0)

            local limit = res_baim:get()
            if limit > 0 and s.misses >= limit then
                plist.set(enemy, "Override prefer body aim", "Force")
            else
                plist.set(enemy, "Override prefer body aim", "-")
            end
        end
    end
end)

-- RAGEBOT OVERRIDES
onTick(function(tick)
    if not rb_enable:get() then
        rage.reset()
        return
    end

    rage.override_min_damage(rb_dmg:get())
    rage.override_hitchance(rb_hc:get())
    rage.override_target_selection(rb_target:get())
    rage.override_force_baim(rb_baim_key:get())
    rage.override_force_safe_point(rb_safe_key:get())
    rage.override_hitboxes({ "head", "chest", "pelvis", "legs" })
    rage.override_hitbox_priority({ "pelvis", "chest", "head" })
    rage.set_hitbox_config("head", { min_damage = rb_dmg:get(), hitchance = rb_hc:get(), multipoint = true })
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
    local target = rage.get_target()

    if v_target3d:get() and target and (target.aim_point or target.point) then
        render3d.box(CFrame.new(target.aim_point or target.point), Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(255, 40, 40), 0.4, true)
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
            line(string.format("AA: %d° [%s] | CHOKE: %s", aa_desync:get(), side, choke), color(240, 60, 70))
        end

        if res_enable:get() then
            if target and target.slot ~= nil then
                local s = getState(target.slot)
                line(string.format("RESOLVER: %d° | MISS: %d", BRUTE_ANGLES[s.stage] or 0, s.misses), color(0, 255, 160))
            else
                line("RESOLVER: ACTIVE", color(200, 200, 200))
            end
        end

        if rage.is_double_tap_charged() then
            line("DT: READY", color(120, 255, 120))
        else
            line(string.format("DT: %d/14", rage.get_double_tap_charge()), color(255, 120, 120))
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
local stats = { fired = 0, hits = 0, misses = 0, reasons = { resolver = 0, spread = 0, occlusion = 0, death = 0 } }

_G.__hvh_reset_stats = function()
    stats.fired, stats.hits, stats.misses = 0, 0, 0
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
        local txt = label .. string.format(" | %d fps | %d ms", fps, ping)
        local size = render.measure_text(txt, 14)
        render.text(sw - size.X - 20, 12, txt, color(255, 255, 255), 14, true)
    end

    -- hit / miss stats, top left
    if xv_stats:get() then
        local total = stats.hits + stats.misses
        local pct = total > 0 and math.floor(stats.hits / total * 100) or 0
        render.text(20, 40, string.format("Hits %d | Misses %d | %d%%", stats.hits, stats.misses, pct), color(0, 255, 160), 14, true)
        render.text(20, 58, string.format("Miss: resolver %d, spread %d, occ %d, death %d",
            stats.reasons.resolver, stats.reasons.spread, stats.reasons.occlusion, stats.reasons.death),
            color(200, 200, 200), 13, true)
    end

    -- predicted enemy paths
    if xv_predict:get() then
        local ticks = xv_pred_tick:get()
        for _, enemy in ipairs(entity.get_enemies()) do
            if entity.is_alive(enemy) then
                local now = entity.get_player_position(enemy)
                local future = movement.predict_position(enemy, ticks)
                if now and future then
                    render3d.line(now, future, Color3.fromRGB(0, 255, 120), 2)
                    render3d.sphere(future, 0.5, Color3.fromRGB(0, 255, 120), 0.2)
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

    -- ring under the current ragebot target
    if xv_ring:get() then
        local target = rage.get_target()
        if target and target.player then
            local pos = entity.get_player_position(target.player)
            if pos then
                render3d.ring(pos - Vector3.new(0, 2.8, 0), 3, 0.4, Color3.fromRGB(255, 60, 60), 0.2, true)
            end
        end
    end

    -- manual direction indicator
    local manual = aa.get_manual()
    if manual then
        render.text(sw / 2 - 40, sh / 2 + 60, "MANUAL: " .. manual, color(255, 200, 60), 14, true, true)
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
onTick(function(tick)
    if not res_enable:get() then return end
    local useAnim = sr_anim:get() and res_mode:get() == "Adaptive"

    for _, enemy in ipairs(entity.get_enemies()) do
        if entity.is_alive(enemy) then
            -- use the enemy's evaluated animstate desync as the yaw offset
            if useAnim then
                local anim = entity.get_anim_state(enemy)
                if anim and anim.desync then
                    local off = math.max(-86, math.min(86, anim.desync))
                    plist.set(enemy, "Force body yaw", true)
                    plist.set(enemy, "Override yaw offset", off)
                end
            end

            -- airborne enemies: require safe points
            if sr_air_sp:get() then
                local info = entity.get_info(enemy)
                if info and info.is_in_air then
                    plist.set(enemy, "Override safe point", "Force")
                else
                    plist.set(enemy, "Override safe point", "-")
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
        color(120, 255, 120))
end)

onEvent("aim_miss", function(e)
    pushLog(string.format("Missed %s in %s due to %s",
        nameOf(e.target), tostring(e.hitbox), tostring(e.reason)),
        color(255, 100, 100))
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
            ind("DT", color(120, 255, 120))
        else
            ind(string.format("DT %d/14", rage.get_double_tap_charge()), color(255, 120, 120))
        end
        ind("DMG " .. tostring(rage.get_min_damage()), color(255, 255, 255))
        if h_speed:get() then
            ind(string.format("%s %d", tostring(movement.get_state()), math.floor(movement.get_speed() or 0)), color(200, 200, 200))
        end
        if h_spread:get() then
            ind(string.format("SPREAD %.2f  INACC %.2f", weapon.get_spread() or 0, weapon.get_inaccuracy() or 0), color(255, 200, 120))
        end
        if rage.is_force_baim() then ind("BAIM", color(255, 200, 60)) end
        if rage.is_force_safe_point() then ind("SAFE", color(120, 200, 255)) end
        if aa.get_manual() then ind("MAN " .. aa.get_manual():upper(), color(255, 200, 60)) end
    end

    -- keybind list, left-middle
    if h_keys:get() then
        local y = cy - 40
        render.text(20, y, "Keybinds", color(255, 255, 255), 14, true)
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
                render.text(20, y, b[1] .. " [on]", color(0, 255, 160), 13, true)
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
            render.text(sw - size.X - 20, sh - 40, txt, color(255, 255, 255), 14, true)
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

-- CONFIG SHARING: "Show Code" / "Load Code" (codes start with SKEED)
local share_sec = ttab:new_section("Config Sharing", "Right")

local CODE_PREFIX = "SKEED"
local CODE_VERSION = 6

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
    sr_anim, sr_air_sp,
    h_cross, h_keys, h_hitlog, h_weapon,
    sp_enable, sp_speed, sp_maxspd, sp_scope, sp_adapt, sp_step,
    x_fake, x_ext_on, x_ext_amt, x_fpitch,
    m_hs_id, m_hs_vol, m_hs_pitch,
    -- new controls are appended at the end
    sp_noscope, sp_crouch, sp_moving,
    xv_wire, xv_wire_col, xv_ring, xv_wm_text, h_speed, h_spread,
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
    { q = "What extra visuals are there?",
      a = "HVH Extras > Extra Visuals has Enemy Wire Boxes, Target Ring, path prediction and an editable Watermark Text. HVH More > HUD can show speed and state, plus spread and inaccuracy, under your crosshair.",
      kw = { "visual", "wire", "box", "ring", "watermark", "esp", "hud", "indicator", "speed" } },
    { q = "How do cloud configs work?",
      a = "Chat tab > Cloud Configs. Press Upload My Config to get a short ID and send that ID to a friend. They paste it in Config ID and press Download Config. It needs the Server URL set. Keybinds are not included.",
      kw = { "cloud", "config id", "upload", "download", "online config", "id" } },
    { q = "Why was my message blocked?",
      a = "The profanity filter blocks swearing, even with symbols or spaced-out letters. Rephrase and try again. Incoming messages are censored the same way.",
      kw = { "blocked", "filter", "censor", "swear", "profanity", "stars" } },
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
        "render3d.box", "render3d.line", "render3d.sphere", "render3d.wire_box", "render3d.ring", "render.line", "render.circle_filled", "input.get_pointer_position",
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

-- CLEANUP
onEvent("shutdown", function()
    aa.set_manual(nil)
    aa.reset()
    rage.reset()
    plist.reset_all()
    chams.clear_overrides()
    sounds.reset_hitsound()
    sounds.reset_killsound()
    clantag.reset()
    render.clear()
    render3d.clear()
    _G.__hvh_reset_stats = nil
end)
