-- 750D controlled exposure write/restore test
-- Safe test: no shooting, no property.request_change, Lua camera API only.

local LOG_PATH = "ML/LOGS/PHOTOSET.TXT"

local m = menu.new{
    parent = "Debug",
    name = "Lua Photo Set Test",
    help = "Temporarily set ISO/Tv/Av via Lua, then restore old values.",
    submenu = {{
        name = "Run safe test",
        help = "Write/verify/restore ISO, shutter and aperture values.",
        icon_type = ICON_TYPE.ACTION,
    }},
}

local lines = {}
local function out(s)
    print(s)
    lines[#lines + 1] = s
end

local function safe(name, fn)
    local ok, ret = pcall(fn)
    if ok then out("OK   " .. name .. ": " .. tostring(ret))
    else out("FAIL " .. name .. ": " .. tostring(ret)) end
end

local function snap(tag)
    out("[" .. tag .. "]")
    safe("camera.mode", function() return camera.mode end)
    safe("camera.gui.idle", function() return camera.gui.idle end)
    safe("camera.shutter.raw", function() return camera.shutter.raw end)
    safe("camera.shutter.ms", function() return camera.shutter.ms end)
    safe("camera.shutter.apex", function() return camera.shutter.apex end)
    safe("camera.aperture.raw", function() return camera.aperture.raw end)
    safe("camera.aperture.value", function() return camera.aperture.value end)
    safe("camera.aperture.apex", function() return camera.aperture.apex end)
    safe("camera.iso.raw", function() return camera.iso.raw end)
    safe("camera.iso.value", function() return camera.iso.value end)
    safe("camera.iso.apex", function() return camera.iso.apex end)
end

local function write_log()
    local ok, err = pcall(function()
        local f = assert(io.open(LOG_PATH, "w"))
        for i = 1, #lines do f:write(lines[i]); f:write("\n") end
        f:close()
    end)
    if ok then print("Log written: " .. LOG_PATH) else print("Log write FAILED: " .. tostring(err)) end
end

local function set_and_wait(label, fn)
    local ok, err = pcall(fn)
    if ok then out("SET_OK " .. label) else out("SET_FAIL " .. label .. ": " .. tostring(err)) end
    sleep(1)
end

local function run_test()
    console.show()
    lines = {}
    out("[750D Lua photo set test]")
    out("No shooting. No property.request_change. Restore old values at end.")
    out("_VERSION=" .. tostring(_VERSION))

    local old_iso, old_tv, old_av, min_av, max_av
    local ok, err = pcall(function()
        old_iso = camera.iso.raw
        old_tv = camera.shutter.raw
        old_av = camera.aperture.raw
        min_av = camera.aperture.min.raw
        max_av = camera.aperture.max.raw
    end)
    if not ok then
        out("ABORT initial read failed: " .. tostring(err))
        write_log()
        return
    end

    snap("before")
    if camera.mode ~= MODE.M then out("WARNING not MODE.M; Canon automation may affect result") end

    local test_iso = 80 -- ISO 200, observed on 750D
    local test_tv = 88  -- around 1/60 s, observed on 750D
    local test_av = old_av
    if old_av + 1 <= max_av then test_av = old_av + 1 elseif old_av - 1 >= min_av then test_av = old_av - 1 end

    out("[targets]")
    out("iso.raw=" .. tostring(test_iso))
    out("shutter.raw=" .. tostring(test_tv))
    out("aperture.raw=" .. tostring(test_av) .. " range=" .. tostring(min_av) .. ".." .. tostring(max_av))

    set_and_wait("camera.iso.raw=" .. tostring(test_iso), function() camera.iso.raw = test_iso end)
    snap("after iso")
    set_and_wait("camera.shutter.raw=" .. tostring(test_tv), function() camera.shutter.raw = test_tv end)
    snap("after shutter")
    if test_av ~= old_av then
        set_and_wait("camera.aperture.raw=" .. tostring(test_av), function() camera.aperture.raw = test_av end)
        snap("after aperture")
    else
        out("SKIP aperture: no safe one-step value in range")
    end

    out("[restore]")
    set_and_wait("restore aperture.raw=" .. tostring(old_av), function() camera.aperture.raw = old_av end)
    set_and_wait("restore shutter.raw=" .. tostring(old_tv), function() camera.shutter.raw = old_tv end)
    set_and_wait("restore iso.raw=" .. tostring(old_iso), function() camera.iso.raw = old_iso end)
    snap("after restore")

    write_log()
    if display and display.notify_box then display.notify_box("Photo set test done", 3000) end
end

m.submenu["Run safe test"].select = function(this) run_test() end
