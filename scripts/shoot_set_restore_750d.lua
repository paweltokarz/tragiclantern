-- 750D Lua set-shoot-restore test
-- Simple script: no menu.new, no task.create, no background state.
-- Workflow: read old ISO/Tv/Av, set test values, close menu, shoot once, restore old values.
-- No autofocus. No generic property.request_change. No camera.wait.

local LOG_PATH = "ML/LOGS/SHOOTSR.TXT"

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
    read_value("camera.aperture.min.raw", function() return camera.aperture.min.raw end)
    read_value("camera.aperture.max.raw", function() return camera.aperture.max.raw end)
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
    settle(2)
    return closed
end

local function set_verify(label, setter, getter, target, attempts)
    attempts = attempts or 3
    for i = 1, attempts do
        local before = nil
        local ok_before, ret_before = pcall(getter)
        if ok_before then before = ret_before end

        out("TRY " .. label .. " attempt=" .. tostring(i) .. "/" .. tostring(attempts))
        local ok_set, err = pcall(function()
            setter(target)
        end)

        if ok_set then
            out("SET_OK " .. label .. "=" .. tostring(target))
        else
            out("SET_FAIL " .. label .. "=" .. tostring(target) .. ": " .. tostring(err))
            settle(2)
            flush()
        end

        settle(1)

        local ok_after, after = pcall(getter)
        if ok_after and after == target then
            out("VERIFY_OK " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
            flush()
            return true
        elseif ok_after then
            out("VERIFY_MISMATCH " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
        else
            out("VERIFY_FAIL " .. label .. ": " .. tostring(after))
        end

        settle(2)
        flush()
    end

    out("GIVE_UP " .. label .. " target=" .. tostring(target))
    flush()
    return false
end

local function choose_target_iso(old_iso)
    if old_iso == 80 then return 72 end
    return 80
end

local function choose_target_tv(old_tv)
    if old_tv == 88 then return 93 end
    return 88
end

local function valid_av(v, min_av, max_av)
    if min_av == nil or max_av == nil then return false end
    if v < min_av or v > max_av then return false end
    if v == min_av or v == max_av then return true end
    local r = v % 8
    return r == 0 or r == 3 or r == 4 or r == 5
end

local function choose_target_av(old_av, min_av, max_av)
    if min_av ~= nil and old_av ~= min_av then
        return min_av
    end
    if max_av ~= nil then
        for v = old_av + 1, max_av do
            if valid_av(v, min_av, max_av) then return v end
        end
    end
    if min_av ~= nil then
        for v = old_av - 1, min_av, -1 do
            if valid_av(v, min_av, max_av) then return v end
        end
    end
    return old_av
end

local function shoot_once()
    out("[shoot]")
    out("camera.shoot(false)")
    flush()

    local ok, ret = pcall(function()
        return camera.shoot(false)
    end)

    if ok then
        out("SHOOT_RET " .. tostring(ret))
    else
        out("SHOOT_FAIL " .. tostring(ret))
    end

    flush()
    settle(5)
    return ok, ret
end

local function main()
    console.show()
    lines = {}

    out("[750D Lua set-shoot-restore]")
    out("Simple script, no menu.new, no task.create, no camera.wait.")
    out("No autofocus. No generic property.request_change.")
    out("_VERSION=" .. tostring(_VERSION))
    flush()

    local old_iso = read_value("initial.iso.raw", function() return camera.iso.raw end)
    local old_tv = read_value("initial.shutter.raw", function() return camera.shutter.raw end)
    local old_av = read_value("initial.aperture.raw", function() return camera.aperture.raw end)
    local min_av = read_value("initial.aperture.min.raw", function() return camera.aperture.min.raw end)
    local max_av = read_value("initial.aperture.max.raw", function() return camera.aperture.max.raw end)

    if old_iso == nil or old_tv == nil or old_av == nil then
        out("ABORT initial read failed")
        flush()
        notify("SHOOTSR abort: initial read failed")
        return
    end

    log_state("startup")
    flush()

    if camera.mode ~= MODE.M then
        out("WARNING not MODE.M; Canon automation may override exposure settings")
    end

    local target_iso = choose_target_iso(old_iso)
    local target_tv = choose_target_tv(old_tv)
    local target_av = choose_target_av(old_av, min_av, max_av)

    out("[targets]")
    out("iso.raw=" .. tostring(target_iso) .. " old=" .. tostring(old_iso))
    out("shutter.raw=" .. tostring(target_tv) .. " old=" .. tostring(old_tv))
    out("aperture.raw=" .. tostring(target_av) .. " old=" .. tostring(old_av) .. " range=" .. tostring(min_av) .. ".." .. tostring(max_av))
    flush()

    local ok_iso = set_verify("camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, target_iso, 3)
    local ok_tv = set_verify("camera.shutter.raw", function(v) camera.shutter.raw = v end, function() return camera.shutter.raw end, target_tv, 3)
    local ok_av = set_verify("camera.aperture.raw", function(v) camera.aperture.raw = v end, function() return camera.aperture.raw end, target_av, 3)

    out("[set_summary]")
    out("iso_set_ok=" .. tostring(ok_iso))
    out("tv_set_ok=" .. tostring(ok_tv))
    out("av_set_ok=" .. tostring(ok_av))
    log_state("after_set")
    flush()

    close_gui()
    log_state("before_shoot")
    flush()

    local shoot_ok, shoot_ret = shoot_once()

    log_state("after_shoot_before_restore")
    flush()

    out("[restore]")
    local restore_av = set_verify("restore camera.aperture.raw", function(v) camera.aperture.raw = v end, function() return camera.aperture.raw end, old_av, 5)
    local restore_tv = set_verify("restore camera.shutter.raw", function(v) camera.shutter.raw = v end, function() return camera.shutter.raw end, old_tv, 5)
    local restore_iso = set_verify("restore camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, old_iso, 5)

    out("[restore_summary]")
    out("av_restore_ok=" .. tostring(restore_av))
    out("tv_restore_ok=" .. tostring(restore_tv))
    out("iso_restore_ok=" .. tostring(restore_iso))
    out("shoot_ok=" .. tostring(shoot_ok))
    out("shoot_ret=" .. tostring(shoot_ret))
    log_state("after_restore")
    out("[done]")
    flush()

    notify("SHOOTSR done")
end

main()
