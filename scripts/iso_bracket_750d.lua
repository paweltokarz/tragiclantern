-- 750D Lua ISO bracket shoot test
-- Simple script: no menu.new, no task.create, no background state.
-- Workflow: save ISO/Tv/Av, close menu, shoot 3 frames with different ISO, restore old values.
-- No autofocus. No generic property.request_change. No camera.wait.

local LOG_PATH = "ML/LOGS/ISOBRACK.TXT"

local lines = {}

local function out(s)
    print(s)
    lines[#lines + 1] = s
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

local function settle(seconds)
    pcall(function() sleep(seconds or 1) end)
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

local function log_state(tag)
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
    read_value("camera.iso.apex", function() return camera.iso.apex end)
    read_value("camera.shutter.raw", function() return camera.shutter.raw end)
    read_value("camera.shutter.ms", function() return camera.shutter.ms end)
    read_value("camera.shutter.apex", function() return camera.shutter.apex end)
    read_value("camera.aperture.raw", function() return camera.aperture.raw end)
    read_value("camera.aperture.value", function() return camera.aperture.value end)
    read_value("camera.aperture.apex", function() return camera.aperture.apex end)
end

local function close_gui()
    local ok_menu, menu_state = pcall(function() return camera.gui.menu end)
    out("MENU_BEFORE ok=" .. tostring(ok_menu) .. " value=" .. tostring(menu_state))

    if ok_menu and menu_state then
        local ok_close, err_close = pcall(function() camera.gui.menu = false end)
        if ok_close then
            out("MENU_CLOSE_OK camera.gui.menu=false")
        else
            out("MENU_CLOSE_FAIL " .. tostring(err_close))
        end
    end

    local closed = false
    for i = 1, 10 do
        settle(1)
        local ok, visible = pcall(function() return camera.gui.menu end)
        out("MENU_WAIT " .. tostring(i) .. " ok=" .. tostring(ok) .. " visible=" .. tostring(visible))
        if ok and not visible then
            closed = true
            break
        end
    end

    out("MENU_CLOSED_RESULT " .. tostring(closed))
    return closed
end

local function set_verify(label, setter, getter, target, attempts)
    attempts = attempts or 3
    for i = 1, attempts do
        out("TRY " .. label .. " attempt=" .. tostring(i) .. "/" .. tostring(attempts))

        local before = nil
        local ok_before, value_before = pcall(getter)
        if ok_before then
            before = value_before
        end

        local ok_set, err_set = pcall(function()
            setter(target)
        end)

        if ok_set then
            out("SET_OK " .. label .. "=" .. tostring(target))
        else
            out("SET_FAIL " .. label .. "=" .. tostring(target) .. ": " .. tostring(err_set))
            settle(1)
        end

        if ok_set then
            settle(1)
            local ok_after, after = pcall(getter)
            if ok_after and after == target then
                out("VERIFY_OK " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
                return true
            elseif ok_after then
                out("VERIFY_MISMATCH " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
            else
                out("VERIFY_FAIL " .. label .. ": " .. tostring(after))
            end
        end
    end

    out("GIVE_UP " .. label .. " target=" .. tostring(target))
    return false
end

local function shoot_one(label)
    out("[shoot " .. tostring(label) .. "]")
    log_state("before_shoot_" .. tostring(label))
    flush()

    local ok, ret = pcall(function() return camera.shoot(false) end)
    if ok then
        out("SHOOT_RET " .. tostring(label) .. "=" .. tostring(ret))
    else
        out("SHOOT_FAIL " .. tostring(label) .. ": " .. tostring(ret))
        flush()
        return false
    end

    -- Let Canon finish enough for the next exposure change.
    settle(4)
    log_state("after_shoot_" .. tostring(label))
    flush()
    return ret == 0
end

local function main()
    console.show()
    lines = {}

    out("[750D Lua ISO bracket]")
    out("Simple script, 3 frames at different ISO values.")
    out("No autofocus. No generic property.request_change. No camera.wait.")
    out("_VERSION=" .. tostring(_VERSION))

    local old_iso = read_value("initial.iso.raw", function() return camera.iso.raw end)
    local old_tv = read_value("initial.shutter.raw", function() return camera.shutter.raw end)
    local old_av = read_value("initial.aperture.raw", function() return camera.aperture.raw end)

    if old_iso == nil or old_tv == nil or old_av == nil then
        out("ABORT initial exposure read failed")
        write_log()
        notify("ISO bracket aborted: read failed")
        return
    end

    log_state("startup")
    flush()

    -- 750D observed raw ISO mapping:
    -- 72 = ISO 100, 80 = ISO 200, 88 = ISO 400.
    local iso_steps = {72, 80, 88}

    out("[iso_sequence]")
    for i = 1, #iso_steps do
        out("frame_" .. tostring(i) .. "_iso.raw=" .. tostring(iso_steps[i]))
    end

    local menu_closed = close_gui()
    if not menu_closed then
        out("WARNING menu may still be active; shooting may fail")
    end

    local all_ok = true

    for i = 1, #iso_steps do
        local iso = iso_steps[i]
        out("[frame " .. tostring(i) .. "]")
        local iso_ok = set_verify("frame" .. tostring(i) .. " camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, iso, 3)
        if not iso_ok then
            out("FRAME_ABORT " .. tostring(i) .. " iso set failed")
            all_ok = false
            break
        end

        local shot_ok = shoot_one("frame" .. tostring(i))
        if not shot_ok then
            out("FRAME_FAIL " .. tostring(i) .. " shoot failed")
            all_ok = false
            break
        end
    end

    out("[restore]")
    local tv_restore_ok = set_verify("restore camera.shutter.raw", function(v) camera.shutter.raw = v end, function() return camera.shutter.raw end, old_tv, 5)
    local av_restore_ok = set_verify("restore camera.aperture.raw", function(v) camera.aperture.raw = v end, function() return camera.aperture.raw end, old_av, 5)
    local iso_restore_ok = set_verify("restore camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, old_iso, 5)

    out("[summary]")
    out("all_frames_ok=" .. tostring(all_ok))
    out("tv_restore_ok=" .. tostring(tv_restore_ok))
    out("av_restore_ok=" .. tostring(av_restore_ok))
    out("iso_restore_ok=" .. tostring(iso_restore_ok))

    log_state("after_restore")
    out("[done]")
    write_log()

    if all_ok and tv_restore_ok and av_restore_ok and iso_restore_ok then
        notify("ISO bracket OK")
    else
        notify("ISO bracket finished with warning")
    end
end

local ok, err = pcall(main)
if not ok then
    lines = lines or {}
    out("[FATAL]")
    out(tostring(err))
    write_log()
    notify("ISO bracket failed")
end
