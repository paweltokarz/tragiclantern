-- 750D Lua exposure bracket test
-- Final/user-facing test script for Canon EOS 750D / firmware 1.1.0.
-- 9 frames total: 3x ISO, 3x aperture, 3x shutter.
-- Uses standard ML Lua API only: menu.close(), camera.*.raw and camera.shoot(false).
-- Restores original ISO/Tv/Av at the end.

local LOG_PATH = "ML/LOGS/EXPOBRKT.TXT"

local GAP_SECONDS = 3

local ISO_RAW = {72, 80, 88}
local AV_RAW  = {43, 48, 56}
local TV_RAW  = {88, 93, 99}

local lines = {}
local elapsed = 0

local function out(s)
    print(s)
    lines[#lines + 1] = string.format("T+%04ds %s", elapsed, tostring(s))
end

local function write_log()
    local ok, err = pcall(function()
        local f = assert(io.open(LOG_PATH, "w"))
        for i = 1, #lines do
            f:write(lines[i])
            f:write("\n")
        end
        f:close()
    end)

    if ok then
        print("Log written: " .. LOG_PATH)
    else
        print("Log write FAILED: " .. tostring(err))
    end
end

local function flush()
    write_log()
end

local function notify(s)
    if display and display.notify_box then
        display.notify_box(s, 3000)
    end
end

local function sleep_s(seconds)
    local s = seconds or 1
    pcall(function() sleep(s) end)
    elapsed = elapsed + s
end

local function read_value(label, fn)
    local ok, ret = pcall(fn)
    if ok then
        out("READ_OK " .. label .. "=" .. tostring(ret))
        return ret
    else
        out("READ_FAIL " .. label .. ": " .. tostring(ret))
        return nil
    end
end

local function read_state(tag)
    out("[" .. tag .. "]")
    read_value("camera.model", function() return camera.model end)
    read_value("camera.firmware", function() return camera.firmware end)
    read_value("camera.mode", function() return camera.mode end)
    read_value("camera.gui.idle", function() return camera.gui.idle end)
    read_value("camera.gui.menu", function() return camera.gui.menu end)
    read_value("camera.gui.play", function() return camera.gui.play end)
    read_value("camera.gui.qr", function() return camera.gui.qr end)
    read_value("lens.name", function() return lens.name end)
    read_value("lens.af", function() return lens.af end)
    read_value("lens.autofocusing", function() return lens.autofocusing end)
    read_value("camera.iso.raw", function() return camera.iso.raw end)
    read_value("camera.iso.value", function() return camera.iso.value end)
    read_value("camera.shutter.raw", function() return camera.shutter.raw end)
    read_value("camera.shutter.ms", function() return camera.shutter.ms end)
    read_value("camera.aperture.raw", function() return camera.aperture.raw end)
    read_value("camera.aperture.value", function() return camera.aperture.value end)
    read_value("camera.aperture.min.raw", function() return camera.aperture.min.raw end)
    read_value("camera.aperture.max.raw", function() return camera.aperture.max.raw end)
end

local function wait_idle(label, max_seconds)
    max_seconds = max_seconds or 10
    for i = 1, max_seconds do
        local ok_menu, gui_menu = pcall(function() return camera.gui.menu end)
        local ok_idle, gui_idle = pcall(function() return camera.gui.idle end)
        local ok_qr, gui_qr = pcall(function() return camera.gui.qr end)

        out("WAIT_IDLE " .. tostring(label)
            .. " step=" .. tostring(i)
            .. " menu=" .. tostring(ok_menu and gui_menu)
            .. " idle=" .. tostring(ok_idle and gui_idle)
            .. " qr=" .. tostring(ok_qr and gui_qr))

        if ok_menu and not gui_menu and ok_idle and gui_idle then
            return true
        end

        sleep_s(1)
    end

    return false
end

local function close_menu()
    out("[close_menu]")
    read_value("menu.visible.before", function() return menu.visible end)
    read_value("camera.gui.menu.before", function() return camera.gui.menu end)

    local ok, err = pcall(function() menu.close() end)
    if ok then
        out("MENU_CLOSE_OK")
    else
        out("MENU_CLOSE_FAIL " .. tostring(err))
    end

    local idle_ok = wait_idle("after_menu_close", 10)
    out("MENU_CLOSE_IDLE_OK=" .. tostring(idle_ok))
    return ok and idle_ok
end

local function clamp(v, lo, hi)
    if v == nil then return nil end
    if lo ~= nil and v < lo then return lo end
    if hi ~= nil and v > hi then return hi end
    return v
end

local function set_raw(label, getter, setter, target, attempts)
    attempts = attempts or 3
    if target == nil then
        out("SET_SKIP " .. label .. " target=nil")
        return false
    end

    for i = 1, attempts do
        out("SET_TRY " .. label .. " attempt=" .. tostring(i) .. "/" .. tostring(attempts) .. " target=" .. tostring(target))
        local before = read_value(label .. ".before", getter)

        local ok_set, err_set = pcall(function() setter(target) end)
        if ok_set then
            out("SET_OK " .. label .. "=" .. tostring(target))
        else
            out("SET_FAIL " .. label .. "=" .. tostring(target) .. ": " .. tostring(err_set))
        end

        sleep_s(1)

        local after = read_value(label .. ".after", getter)
        if ok_set and after == target then
            out("VERIFY_OK " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
            return true
        end

        out("VERIFY_FAIL " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
    end

    out("SET_GIVE_UP " .. label .. " target=" .. tostring(target))
    return false
end

local function set_iso(raw, label)
    return set_raw(label .. ".iso.raw", function() return camera.iso.raw end, function(v) camera.iso.raw = v end, raw, 3)
end

local function set_tv(raw, label)
    return set_raw(label .. ".shutter.raw", function() return camera.shutter.raw end, function(v) camera.shutter.raw = v end, raw, 3)
end

local function set_av(raw, label)
    return set_raw(label .. ".aperture.raw", function() return camera.aperture.raw end, function(v) camera.aperture.raw = v end, raw, 3)
end

local old_iso = nil
local old_tv = nil
local old_av = nil

local function restore_exposure(reason)
    out("[restore " .. tostring(reason) .. "]")
    local av_ok = set_av(old_av, "restore")
    local tv_ok = set_tv(old_tv, "restore")
    local iso_ok = set_iso(old_iso, "restore")
    out("RESTORE_SUMMARY av_ok=" .. tostring(av_ok) .. " tv_ok=" .. tostring(tv_ok) .. " iso_ok=" .. tostring(iso_ok))
    return av_ok and tv_ok and iso_ok
end

local function shoot_frame(frame_no, block_name, setting_label)
    out("[frame " .. tostring(frame_no) .. " " .. tostring(block_name) .. " " .. tostring(setting_label) .. "]")
    read_state("before_frame_" .. tostring(frame_no))

    local ok, ret = pcall(function() return camera.shoot(false) end)
    if ok then
        out("SHOOT_RET frame=" .. tostring(frame_no) .. " ret=" .. tostring(ret))
    else
        out("SHOOT_FAIL frame=" .. tostring(frame_no) .. " err=" .. tostring(ret))
    end

    sleep_s(1)
    read_state("after_frame_" .. tostring(frame_no))
    flush()

    if frame_no < 9 then
        out("FRAME_GAP seconds=" .. tostring(GAP_SECONDS))
        sleep_s(GAP_SECONDS)
    end

    return ok and ret == 0
end

local function run()
    out("[750D Lua exposure bracket]")
    out("Script=EXPOBRKT.LUA")
    out("Frames=9: 3x ISO, 3x aperture, 3x shutter.")
    out("Gap=" .. tostring(GAP_SECONDS) .. "s")
    out("Uses menu.close(), camera.*.raw, camera.shoot(false).")
    out("_VERSION=" .. tostring(_VERSION))
    flush()

    old_iso = read_value("initial.iso.raw", function() return camera.iso.raw end)
    old_tv = read_value("initial.shutter.raw", function() return camera.shutter.raw end)
    old_av = read_value("initial.aperture.raw", function() return camera.aperture.raw end)
    local av_min = read_value("initial.aperture.min.raw", function() return camera.aperture.min.raw end)
    local av_max = read_value("initial.aperture.max.raw", function() return camera.aperture.max.raw end)
    flush()

    local av_values = {
        clamp(AV_RAW[1], av_min, av_max),
        clamp(AV_RAW[2], av_min, av_max),
        clamp(AV_RAW[3], av_min, av_max),
    }

    read_state("startup")

    out("[planned_sequence]")
    out("iso_values=" .. tostring(ISO_RAW[1]) .. "," .. tostring(ISO_RAW[2]) .. "," .. tostring(ISO_RAW[3]))
    out("av_values=" .. tostring(av_values[1]) .. "," .. tostring(av_values[2]) .. "," .. tostring(av_values[3]))
    out("tv_values=" .. tostring(TV_RAW[1]) .. "," .. tostring(TV_RAW[2]) .. "," .. tostring(TV_RAW[3]))
    flush()

    local close_ok = close_menu()
    read_state("after_menu_close")
    flush()

    local frame = 0
    local all_ok = true

    out("[block ISO]")
    for i = 1, #ISO_RAW do
        frame = frame + 1
        local set_ok = set_iso(ISO_RAW[i], "frame" .. tostring(frame))
        local shoot_ok = shoot_frame(frame, "ISO", "iso.raw=" .. tostring(ISO_RAW[i]))
        all_ok = all_ok and set_ok and shoot_ok
    end

    restore_exposure("before Av block")
    flush()

    out("[block Av]")
    for i = 1, #av_values do
        frame = frame + 1
        local set_ok = set_av(av_values[i], "frame" .. tostring(frame))
        local shoot_ok = shoot_frame(frame, "Av", "aperture.raw=" .. tostring(av_values[i]))
        all_ok = all_ok and set_ok and shoot_ok
    end

    restore_exposure("before Tv block")
    flush()

    out("[block Tv]")
    for i = 1, #TV_RAW do
        frame = frame + 1
        local set_ok = set_tv(TV_RAW[i], "frame" .. tostring(frame))
        local shoot_ok = shoot_frame(frame, "Tv", "shutter.raw=" .. tostring(TV_RAW[i]))
        all_ok = all_ok and set_ok and shoot_ok
    end

    local restore_ok = restore_exposure("final")
    read_state("after_restore")

    out("[summary]")
    out("close_ok=" .. tostring(close_ok))
    out("frames_total=" .. tostring(frame))
    out("all_ok=" .. tostring(all_ok))
    out("restore_ok=" .. tostring(restore_ok))
    out("elapsed_seconds=" .. tostring(elapsed))
    out("[done]")

    flush()
    notify("EXPOBRKT done: " .. tostring(frame) .. " frames")
end

local ok, err = pcall(run)
if not ok then
    out("[fatal_error]")
    out(tostring(err))
    pcall(function() restore_exposure("fatal") end)
    write_log()
    notify("EXPOBRKT failed")
end
