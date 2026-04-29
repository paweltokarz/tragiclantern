-- 750D Lua shutter probe
-- Tests key.press(KEY.FULLSHUTTER) / half+full shutter path separately from camera.shoot().
-- Menu actions arm a background task: close ML menu, wait, then trigger.
-- No exposure changes. No camera.wait(). No generic property.request_change.

local LOG_PATH = "ML/LOGS/SHUTPROB.TXT"

local m = menu.new{
    parent = "Debug",
    name = "Lua Shutter Probe",
    help = "Test Lua shutter triggering paths on 750D.",
    submenu = {
        {
            name = "Status/log only",
            help = "Log current state. No shooting.",
            icon_type = ICON_TYPE.ACTION,
        },
        {
            name = "Key full only",
            help = "Close menu, press FULLSHUTTER, then release.",
            icon_type = ICON_TYPE.ACTION,
        },
        {
            name = "Key half+full",
            help = "Close menu, press HALFSHUTTER + FULLSHUTTER, release both.",
            icon_type = ICON_TYPE.ACTION,
        },
        {
            name = "Camera shoot no wait",
            help = "Close menu, call camera.shoot(false), no camera.wait().",
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

local function read_line(label, fn)
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
    read_line("camera.model", function() return camera.model end)
    read_line("camera.firmware", function() return camera.firmware end)
    read_line("camera.mode", function() return camera.mode end)
    read_line("camera.gui.idle", function() return camera.gui.idle end)
    read_line("camera.gui.menu", function() return camera.gui.menu end)
    read_line("camera.gui.play", function() return camera.gui.play end)
    read_line("lens.name", function() return lens.name end)
    read_line("lens.af", function() return lens.af end)
    read_line("lens.autofocusing", function() return lens.autofocusing end)
    read_line("camera.iso.raw", function() return camera.iso.raw end)
    read_line("camera.iso.value", function() return camera.iso.value end)
    read_line("camera.shutter.raw", function() return camera.shutter.raw end)
    read_line("camera.shutter.ms", function() return camera.shutter.ms end)
    read_line("camera.aperture.raw", function() return camera.aperture.raw end)
    read_line("camera.aperture.value", function() return camera.aperture.value end)
end

local function write_log()
    local ok, err = pcall(function()
        local f = assert(io.open(LOG_PATH, "w"))
        for i = 1, #lines do
            f:pwrite(lines[i])
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

local function reset_keys()
    pcall(function() key.press(KEY.UNPRESS_FULLSHUTTER) end)
    settle(1)
    pcall(function() key.press(KEY.UNPRESS_HALFSHUTTER) end)
    settle(1)
end

local function close_menu_and_wait(label)
    local ok_menu, menu_state = pcall(function() return camera.gui.menu end)
    out("MENU_BEFORE " .. tostring(ok_menu) .. " " .. tostring(menu_state))

    if ok_menu and menu_state then
        local ok_close, err_close = pcall(function() camera.gui.menu = false end)
        out((ok_close and "MENU_CLOSE_OK" or "MENU_CLOSE_FAIL") .. (ok_close and "" or (": " .. tostring(err_close))))
    end

    for i = 1, 30 do
        local ok, visible = pcall(function() return camera.gui.menu end)
        if ok and not visible then
            out("MENU_CLOSED after=" .. tostring(i))
            break
        end
        settle(1)
    end

    local ok_after, state_after = pcall(function() return camera.gui.menu end)
    out("MENU_AFTER " .. tostring(ok_after) .. " " .. tostring(state_after))
    settle(2)
end

local function run_common_start(label)
    console.show()
    lines = {}
    out("[750D Lua shutter probe]")
    out("label=" .. tostring(label))
    out("No exposure changes. No camera.wait().")
    out("_VERSION=" .. tostring(_VERSION))
    read_line("KEY.HALFSHUTTER", function() return KEY.HALFSHUTTER end)
    read_line("KEY.UNPRESS_HALFSHUTTER", function() return KEY.UNPRESS_HALFSHUTTER end)
    read_line("KEY.FULLSHUTTER", function() return KEY.FULLSHUTTER end)
    read_line("KEY.UNPRESS_FULLSHUTTER", function() return KEY.UNPRESS_FULLSHUTTER end)
    reset_keys()
    close_menu_and_wait(label)
    log_state("before")
end

local function finish(label)
    reset_keys()
    log_state("after")
    out("[done]")
    out("label=" .. tostring(label))
    write_log()
    notify("Shutter probe done: " .. tostring(label))
end

local function run_status()
    run_common_start("status")
    finish("status")
end

local function run_key_full_only()
    run_common_start("key_full_only")
    out("[action]")
    out("press FULLSHUTTER")
    local ok1, err1 = pcall(function() key.press(KEY.FULLSHUTTER) end)
    out((ok1 and "KEY_OK " or "KEY_FAIL ") .. "FULLSHUTTER" .. (ok1 and "" or (": " .. tostring(err1))))
    settle(1)
    out("press UNPRESS_FULLSHUTTER")
    local ok2, err2 = pcall(function() key.press(KEY.UNPRESS_FULLSHUTTER) end)
    out((ok2 and "KEY_OK " or "KEY_FAIL ") .. "UNPRESS_FULLSHUTTER" .. (ok2 and "" or (": " .. tostring(err2))))
    settle(3)
    finish("key_full_only")
end

local function run_key_half_full()
    run_common_start("key_half_full")
    out("[action]")
    out("press HALFSHUTTER")
    local ok1, err1 = pcall(function() key.press(KEY.HALFSHUTTER) end)
    out((ok1 and "KEY_OK " or "KEY_FAIL ") .. "HALFSHUTTER" .. (ok1 and "" or (": " .. tostring(err1))))
    settle(1)

    out("press FULLSHUTTER")
    local ok2, err2 = pcall(function() key.press(KEY.FULLSHUTTER) end)
    out((ok2 and "KEY_OK " or "KEY_FAIL ") .. "FULLSHUTTER" .. (ok2 and "" or (": " .. tostring(err2))))
    settle(1)

    out("press UNPRESS_FULLSHUTTER")
    local ok3, err3 = pcall(function() key.press(KEY.UNPRESS_FULLSHUTTER) end)
    out((ok3 and "KEY_OK " or "KEY_FAIL ") .. "UNPRESS_FULLSHUTTER" .. (ok3 and "" or (": " .. tostring(err3))))
    settle(1)

    out("press UNPRESS_HALFSHUTTER")
    local ok4, err4 = pcall(function() key.press(KEY.UNPRESS_HALFSHUTTER) end)
    out((ok4 and "KEY_OK " or "KEY_FAIL ") .. "UNPRESS_HALFSHUTTER" .. (ok4 and "" or (": " .. tostring(err4))))
    settle(3)

    finish("key_half_full")
end

local function run_camera_shoot_no_wait()
    run_common_start("camera_shoot_no_wait")
    out("[action]")
    out("camera.shoot(false)")
    local ok, ret = pcall(function() return camera.shoot(false) end)
    if ok then
        out("SHOOT_RET " .. tostring(ret))
    else
        out("SHOOT_FAIL " .. tostring(ret))
    end
    settle(5)
    finish("camera_shoot_no_wait")
end

local function arm(label, fn)
    notify("Armed: " .. tostring(label) .. " - closing menu")
    task.create(function()
        local ok, err = pcall(fn)
        if not ok then
            console.show()
            lines = {}
            out("[750D Lua shutter probe]")
            out("label=" .. tostring(label))
            out("TASK_FAIL " .. tostring(err))
            write_log()
            notify("Shutter probe failed: " .. tostring(label))
            reset_keys()
        end
    end, nil, nil, true)
end

m.submenu["Status/log only"].select = function(this)
    arm("status", run_status)
end

m.submenu["Key full only"].select = function(this)
    arm("key_full_only", run_key_full_only)
end

m.submenu["Key half+full"].select = function(this)
    arm("key_half_full", run_key_half_full)
end

m.submenu["Camera shoot no wait"].select = function(this)
    arm("camera_shoot_no_wait", run_camera_shoot_no_wait)
end
