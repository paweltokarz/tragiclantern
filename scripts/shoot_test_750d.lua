-- 750D Lua shoot test
-- Controlled single-shot test for Canon EOS 750D / ML Lua.
-- Uses camera.shoot(false), camera.wait(), and optional ISO/Tv/Av set+restore.
-- No autofocus. No generic property.request_change.

local LOG_PATH = "ML/LOGS/SHOOTEST.TXT"

local m = menu.new{
    parent = "Debug",
    name = "Lua Shoot Test",
    help = "Single-shot Lua test for 750D. No autofocus by default.",
    submenu = {
        {
            name = "Status/log only",
            help = "Write current camera/exposure state to ML/LOGS/SHOOTEST.TXT. No shooting.",
            icon_type = ICON_TYPE.ACTION,
        },
        {
            name = "Shoot current",
            help = "Take one picture with current camera settings, no autofocus.",
            icon_type = ICON_TYPE.ACTION,
        },
        {
            name = "Set+shoot+restore",
            help = "Set ISO/Tv/Av, shoot once, then restore previous settings with retries.",
            icon_type = ICON_TYPE.ACTION,
        },
    },
}

local lines = {}

local function out(s)
    print(s)
    lines[#lines + 1] = s
end

local function notify(s)
    if display and display.notify_box then
        display.notify_box(s, 3000)
    end
end

local function settle(seconds)
    pcall(function() sleep(seconds or 1) end)
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

local function snapshot(tag)
    out("[" .. tag .. "]")
    read_value("camera.model", function() return camera.model end)
    read_value("camera.firmware", function() return camera.firmware end)
    read_value("camera.mode", function() return camera.mode end)
    read_value("camera.gui.idle", function() return camera.gui.idle end)
    read_value("lens.name", function() return lens.name end)
    read_value("lens.af", function() return lens.af end)
    read_value("camera.iso.raw", function() return camera.iso.raw end)
    read_value("camera.iso.value", function() return camera.iso.value end)
    read_value("camera.shutter.raw", function() return camera.shutter.raw end)
    read_value("camera.shutter.ms", function() return camera.shutter.ms end)
    read_value("camera.aperture.raw", function() return camera.aperture.raw end)
    read_value("camera.aperture.value", function() return camera.aperture.value end)
    read_value("camera.aperture.min.raw", function() return camera.aperture.min.raw end)
    read_value("camera.aperture.max.raw", function() return camera.aperture.max.raw end)
end

local function set_verify_once(label, setter, getter, target)
    local ok_before, before = pcall(getter)

    local ok_set, err = pcall(function()
        setter(target)
    end)

    if ok_set then
        out("SET_OK " .. label .. "=" .. tostring(target))
    else
        out("SET_FAIL " .. label .. "=" .. tostring(target) .. ": " .. tostring(err))
        return false
    end

    settle(1)

    local ok_after, after = pcall(getter)
    if not ok_after then
        out("VERIFY_FAIL " .. label .. ": readback failed: " .. tostring(after))
        return false
    end

    if after == target then
        out(
            "VERIFY_OK " .. label ..
            " before=" .. tostring(ok_before and before or "ERR") ..
            " target=" .. tostring(target) ..
            " after=" .. tostring(after)
        )
        return true
    end

    out(
        "VERIFY_FAIL " .. label ..
        " before=" .. tostring(ok_before and before or "ERR") ..
        " target=" .. tostring(target) ..
        " after=" .. tostring(after)
    )
    return false
end

local function set_verify_retry(label, setter, getter, target, attempts)
    attempts = attempts or 3
    for i = 1, attempts do
        out("TRY " .. label .. " attempt=" .. tostring(i) .. "/" .. tostring(attempts))
        if set_verify_once(label, setter, getter, target) then
            return true
        end
        settle(2)
    end
    out("GIVE_UP " .. label .. " target=" .. tostring(target))
    return false
end

local function restore_value(label, setter, getter, target)
    if target == nil then
        out("RESTORE_SKIP " .. label .. ": no saved value")
        return false
    end
    return set_verify_retry("restore " .. label, setter, getter, target, 5)
end

local function shoot_once(label)
    out("[shoot]")
    out("shoot_label=" .. tostring(label))
    notify("Lua Shoot Test: shooting")

    local ok, ret = pcall(function()
        return camera.shoot(false)
    end)

    if ok then
        out("SHOOT_CALL_OK ret=" .. tostring(ret))
    else
        out("SHOOT_CALL_FAIL " .. tostring(ret))
        notify("Lua shoot failed")
        return false
    end

    out("WAIT_START")
    local ok_wait, err_wait = pcall(function()
        camera.wait()
    end)

    if ok_wait then
        out("WAIT_OK")
    else
        out("WAIT_FAIL " .. tostring(err_wait))
    end

    settle(2)
    notify("Lua Shoot Test: done")
    return ok and ok_wait
end

local function init_log(title)
    console.show()
    lines = {}
    out("[750D Lua shoot test]")
    out(title)
    out("_VERSION=" .. tostring(_VERSION))
end

local function run_status()
    init_log("Status/log only. No shooting.")
    snapshot("status")
    write_log()
end

local function run_current_shot()
    init_log("Shoot current settings. No AF. No setting changes.")
    snapshot("before")
    if camera.mode ~= 3 then
        out("WARNING camera.mode is not observed 750D manual mode value 3; Canon automation may affect exposure.")
    end
    shoot_once("current")
    snapshot("after")
    write_log()
end

local function run_set_shoot_restore()
    init_log("Set ISO/Tv/Av, shoot once, restore old values with retries. No AF.")

    local old_iso = read_value("initial.iso.raw", function() return camera.iso.raw end)
    local old_tv = read_value("initial.shutter.raw", function() return camera.shutter.raw end)
    local old_av = read_value("initial.aperture.raw", function() return camera.aperture.raw end)
    local av_min = read_value("initial.aperture.min.raw", function() return camera.aperture.min.raw end)
    local av_max = read_value("initial.aperture.max.raw", function() return camera.aperture.max.raw end)

    snapshot("before")

    if camera.mode ~= 3 then
        out("WARNING camera.mode is not observed 750D manual mode value 3; Canon automation may affect exposure.")
    end

    local target_iso = 80 -- ISO 200, observed on 750D
    local target_tv = 88  -- around 1/60 s on this 750D
    local target_av = old_av

    if av_min ~= nil and av_max ~= nil and old_av ~= nil then
        if old_av ~= av_min then
            target_av = av_min
        elseif old_av + 5 <= av_max then
            target_av = old_av + 5
        end
    end

    out("[targets]")
    out("iso.raw=" .. tostring(target_iso))
    out("shutter.raw=" .. tostring(target_tv))
    out("aperture.raw=" .. tostring(target_av))

    local iso_ok = set_verify_retry("camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, target_iso, 3)
    local tv_ok = set_verify_retry("camera.shutter.raw", function(v) camera.shutter.raw = v end, function() return camera.shutter.raw end, target_tv, 3)
    local av_ok = true

    if target_av ~= nil then
        av_ok = set_verify_retry("camera.aperture.raw", function(v) camera.aperture.raw = v end, function() return camera.aperture.raw end, target_av, 3)
    end

    snapshot("before shoot")

    if iso_ok and tv_ok and av_ok then
        shoot_once("set_shoot_restore")
    else
        out("ABORT_SHOOT because one or more exposure setters failed.")
        notify("Lua Shoot Test: setter failed")
    end

    snapshot("after shoot before restore")

    out("[restore]")
    settle(2)

    -- Restore ISO first and retry. On 750D, ISO restore may be refused immediately after a shot.
    restore_value("camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, old_iso)
    restore_value("camera.shutter.raw", function(v) camera.shutter.raw = v end, function() return camera.shutter.raw end, old_tv)
    restore_value("camera.aperture.raw", function(v) camera.aperture.raw = v end, function() return camera.aperture.raw end, old_av)

    snapshot("after restore")
    write_log()
end

m.submenu["Status/log only"].select = function(this)
    run_status()
end

m.submenu["Shoot current"].select = function(this)
    run_current_shot()
end

m.submenu["Set+shoot+restore"].select = function(this)
    run_set_shoot_restore()
end
