-- 750D Lua simple shoot test
-- Simple script: no menu.new, no task.create, no background state.
-- Run from Scripts menu. It closes ML/Canon menu, waits, then triggers one no-AF shot.

local LOG_PATH = "ML/LOGS/SHOOTSMP.TXT"

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
    read_line("camera.gui.qr", function() return camera.gui.qr end)
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

local function close_gui()
    local ok_menu, menu_state = pcall(function() return camera.gui.menu end)
    out("MENU_BEFORE ok=" .. tostring(ok_menu) .. " value=" .. tostring(menu_state))

    if ok_menu and menu_state then
        local ok_close, err_close = pcall(function() camera.gui.menu = false end)
        if ok_close then
            out("MENU_CLOSE_OK camera.gui.menu=false")
        else
            out("MENU_CLOSE_FAIL " .. tostring(err_close))
            pcall(function() key.press(KEY.MENU) end)
            out("MENU_CLOSE_FALLBACK key.press(KEY.MENU)")
        end
    end

    for i = 1, 12 do
        settle(1)
        local ok, visible = pcall(function() return camera.gui.menu end)
        out("MENU_WAIT " .. tostring(i) .. " ok=" .. tostring(ok) .. " visible=" .. tostring(visible))
        if ok and not visible then
            return true
        end
    end

    return false
end

local function reset_keys()
    pcall(function() key.press(KEY.UNPRESS_FULLSHUTTER) end)
    settle(1)
    pcall(function() key.press(KEY.UNPRESS_HALFSHUTTER) end)
    settle(1)
end

local function shoot_via_camera()
    out("[shoot camera.shoot]")
    local ok, ret = pcall(function() return camera.shoot(false) end)
    if ok then
        out("SHOOT_RET " .. tostring(ret))
    else
        out("SHOOT_FAIL " .. tostring(ret))
    end
    settle(8)
end

local function shoot_via_keys()
    out("[shoot key half+full]")
    local ok1, err1 = pcall(function() key.press(KEY.HALFSHUTTER) end)
    out((ok1 and "KEY_OK " or "KEY_FAIL ") .. "HALFSHUTTER" .. (ok1 and "" or (": " .. tostring(err1))))
    settle(2)

    local ok2, err2 = pcall(function() key.press(KEY.FULLSHUTTER) end)
    out((ok2 and "KEY_OK " or "KEY_FAIL ") .. "FULLSHUTTER" .. (ok2 and "" or (": " .. tostring(err2))))
    settle(2)

    local ok3, err3 = pcall(function() key.press(KEY.UNPRESS_FULLSHUTTER) end)
    out((ok3 and "KEY_OK " or "KEY_FAIL ") .. "UNPRESS_FULLSHUTTER" .. (ok3 and "" or (": " .. tostring(err3))))
    settle(1)

    local ok4, err4 = pcall(function() key.press(KEY.UNPRESS_HALFSHUTTER) end)
    out((ok4 and "KEY_OK " or "KEY_FAIL ") .. "UNPRESS_HALFSHUTTER" .. (ok4 and "" or (": " .. tostring(err4))))
    settle(8)
end

console.show()
lines = {}
out("[750D Lua simple shoot test]")
out("Simple script, no menu.new, no task.create, no camera.wait.")
out("_VERSION=" .. tostring(_VERSION))

notify("Simple shoot test armed")
reset_keys()
log_state("startup")

local closed = close_gui()
out("MENU_CLOSED_RESULT " .. tostring(closed))
settle(2)
log_state("before_shoot")

-- Prefer camera.shoot first; it uses ML's normal take_a_pic path.
shoot_via_camera()

log_state("after_camera_shoot")

-- Also probe raw key path, but only after camera.shoot attempt.
shoot_via_keys()

reset_keys()
log_state("after_key_shoot")
out("[done]")
write_log()
notify("Simple shoot test done")
