-- 750D Lua exposure controller
-- Practical menu-driven ISO/Tv/Av control through ML Lua camera API.
-- No shooting. No generic property.request_change.

local LOG_PATH = "ML/LOGS/EXPOCTRL.TXT"

local iso_steps = {72, 80, 88, 96, 104, 112}
local tv_steps  = {72, 75, 77, 80, 83, 85, 88, 91, 93, 96, 99, 101, 104, 107, 109, 112}
local av_steps  = {}

local startup = {
    iso = nil,
    tv = nil,
    av = nil,
    av_min = nil,
    av_max = nil,
}

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

local function read_value(label, fn)
    local ok, ret = pcall(fn)
    if ok then
        return ret
    end
    out("READ_FAIL " .. label .. ": " .. tostring(ret))
    return nil
end

local function log_state(tag)
    local iso = read_value("camera.iso.raw", function() return camera.iso.raw end)
    local iso_value = read_value("camera.iso.value", function() return camera.iso.value end)
    local tv = read_value("camera.shutter.raw", function() return camera.shutter.raw end)
    local tv_ms = read_value("camera.shutter.ms", function() return camera.shutter.ms end)
    local av = read_value("camera.aperture.raw", function() return camera.aperture.raw end)
    local av_value = read_value("camera.aperture.value", function() return camera.aperture.value end)
    local mode = read_value("camera.mode", function() return camera.mode end)
    local idle = read_value("camera.gui.idle", function() return camera.gui.idle end)

    out(
        tag
        .. " mode=" .. tostring(mode)
        .. " idle=" .. tostring(idle)
        .. " iso_raw=" .. tostring(iso)
        .. " iso=" .. tostring(iso_value)
        .. " tv_raw=" .. tostring(tv)
        .. " tv_ms=" .. tostring(tv_ms)
        .. " av_raw=" .. tostring(av)
        .. " av=" .. tostring(av_value)
    )
end

local function valid_av(v)
    if startup.av_min == nil or startup.av_max == nil then
        return false
    end
    if v == startup.av_min or v == startup.av_max then
        return true
    end
    if v < startup.av_min or v > startup.av_max then
        return false
    end
    local r = v % 8
    return r == 0 or r == 3 or r == 4 or r == 5
end

local function build_av_steps()
    av_steps = {}
    if startup.av_min == nil or startup.av_max == nil then
        return
    end
    for v = startup.av_min, startup.av_max do
        if valid_av(v) then
            av_steps[#av_steps + 1] = v
        end
    end
end

local function nearest_index(list, value)
    if value == nil or #list == 0 then
        return nil
    end
    local best_i = 1
    local best_d = math.abs(list[1] - value)
    for i = 2, #list do
        local d = math.abs(list[i] - value)
        if d < best_d then
            best_i = i
            best_d = d
        end
    end
    return best_i
end

local function clamp_index(i, list)
    if i < 1 then return 1 end
    if i > #list then return #list end
    return i
end

local function set_and_verify(label, setter, getter, target)
    local before = read_value(label .. ".before", getter)
    local ok, err = pcall(function()
        setter(target)
    end)

    if not ok then
        out("SET_FAIL " .. label .. "=" .. tostring(target) .. ": " .. tostring(err))
        write_log()
        return false
    end

    sleep(1)

    local after = read_value(label .. ".after", getter)
    if after == target then
        out("SET_OK " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
        write_log()
        return true
    end

    out("VERIFY_FAIL " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
    write_log()
    return false
end

local function init_startup()
    if startup.iso ~= nil then
        return
    end

    startup.iso = read_value("startup.iso", function() return camera.iso.raw end)
    startup.tv = read_value("startup.tv", function() return camera.shutter.raw end)
    startup.av = read_value("startup.av", function() return camera.aperture.raw end)
    startup.av_min = read_value("startup.av_min", function() return camera.aperture.min.raw end)
    startup.av_max = read_value("startup.av_max", function() return camera.aperture.max.raw end)
    build_av_steps()

    out("[ExpoCtrl startup]")
    log_state("startup")
    out("startup_iso=" .. tostring(startup.iso))
    out("startup_tv=" .. tostring(startup.tv))
    out("startup_av=" .. tostring(startup.av) .. " range=" .. tostring(startup.av_min) .. ".." .. tostring(startup.av_max))
    out("av_steps_count=" .. tostring(#av_steps))
    write_log()
end

local function notify(msg)
    if display and display.notify_box then
        display.notify_box(msg, 2000)
    end
end

local function change_iso(delta)
    init_startup()
    local current = read_value("iso.current", function() return camera.iso.raw end)
    local idx = nearest_index(iso_steps, current)
    if idx == nil then
        out("ABORT iso: no index")
        write_log()
        return
    end
    local target = iso_steps[clamp_index(idx + delta, iso_steps)]
    set_and_verify("camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, target)
    log_state("after iso")
    notify("ISO raw " .. tostring(target))
end

local function change_tv(delta)
    init_startup()
    local current = read_value("tv.current", function() return camera.shutter.raw end)
    local idx = nearest_index(tv_steps, current)
    if idx == nil then
        out("ABORT tv: no index")
        write_log()
        return
    end
    local target = tv_steps[clamp_index(idx + delta, tv_steps)]
    set_and_verify("camera.shutter.raw", function(v) camera.shutter.raw = v end, function() return camera.shutter.raw end, target)
    log_state("after tv")
    notify("Tv raw " .. tostring(target))
end

local function change_av(delta)
    init_startup()
    if #av_steps == 0 then
        out("ABORT av: no valid aperture steps")
        write_log()
        return
    end
    local current = read_value("av.current", function() return camera.aperture.raw end)
    local idx = nearest_index(av_steps, current)
    if idx == nil then
        out("ABORT av: no index")
        write_log()
        return
    end
    local target = av_steps[clamp_index(idx + delta, av_steps)]
    set_and_verify("camera.aperture.raw", function(v) camera.aperture.raw = v end, function() return camera.aperture.raw end, target)
    log_state("after av")
    notify("Av raw " .. tostring(target))
end

local function restore_startup()
    init_startup()
    out("[restore startup]")
    if startup.av ~= nil then
        set_and_verify("restore camera.aperture.raw", function(v) camera.aperture.raw = v end, function() return camera.aperture.raw end, startup.av)
    end
    if startup.tv ~= nil then
        set_and_verify("restore camera.shutter.raw", function(v) camera.shutter.raw = v end, function() return camera.shutter.raw end, startup.tv)
    end
    if startup.iso ~= nil then
        set_and_verify("restore camera.iso.raw", function(v) camera.iso.raw = v end, function() return camera.iso.raw end, startup.iso)
    end
    log_state("after restore")
    notify("Exposure restored")
end

local function status()
    init_startup()
    console.show()
    out("[status]")
    log_state("status")
    write_log()
    notify("Expo status logged")
end

local expo_menu = menu.new{
    parent = "Debug",
    name = "Lua Expo Ctrl",
    help = "Practical ISO/Tv/Av control via Lua camera API.",
    submenu = {
        {
            name = "Status",
            help = "Show current ISO/Tv/Av and log them.",
            icon_type = ICON_TYPE.ACTION,
        },
        {
            name = "ISO raw",
            help = "Left/right changes ISO raw over safe tested values.",
            min = 1,
            max = #iso_steps,
            value = 1,
            unit = UNIT.DEC,
        },
        {
            name = "Tv raw",
            help = "Left/right changes shutter raw over tested values.",
            min = 1,
            max = #tv_steps,
            value = 1,
            unit = UNIT.DEC,
        },
        {
            name = "Av raw",
            help = "Left/right changes aperture raw over lens-valid values.",
            min = 1,
            max = 64,
            value = 1,
            unit = UNIT.DEC,
        },
        {
            name = "Restore startup",
            help = "Restore ISO/Tv/Av captured when script first loaded.",
            icon_type = ICON_TYPE.ACTION,
        },
    },
}

expo_menu.submenu["Status"].select = function(this)
    status()
end

expo_menu.submenu["ISO raw"].select = function(this, delta)
    if delta == nil or delta == 0 then delta = 1 end
    change_iso(delta)
    local current = read_value("iso.menu.current", function() return camera.iso.raw end)
    local idx = nearest_index(iso_steps, current)
    if idx then this.value = idx end
end

expo_menu.submenu["ISO raw"].update = function(this)
    init_startup()
    local current = read_value("iso.menu.update", function() return camera.iso.raw end)
    local idx = nearest_index(iso_steps, current)
    if idx then this.value = idx end
    return current
end

expo_menu.submenu["Tv raw"].select = function(this, delta)
    if delta == nil or delta == 0 then delta = 1 end
    change_tv(delta)
    local current = read_value("tv.menu.current", function() return camera.shutter.raw end)
    local idx = nearest_index(tv_steps, current)
    if idx then this.value = idx end
end

expo_menu.submenu["Tv raw"].update = function(this)
    init_startup()
    local current = read_value("tv.menu.update", function() return camera.shutter.raw end)
    local idx = nearest_index(tv_steps, current)
    if idx then this.value = idx end
    return current
end

expo_menu.submenu["Av raw"].select = function(this, delta)
    if delta == nil or delta == 0 then delta = 1 end
    change_av(delta)
    local current = read_value("av.menu.current", function() return camera.aperture.raw end)
    local idx = nearest_index(av_steps, current)
    if idx then this.value = idx end
end

expo_menu.submenu["Av raw"].update = function(this)
    init_startup()
    local current = read_value("av.menu.update", function() return camera.aperture.raw end)
    local idx = nearest_index(av_steps, current)
    if idx then this.value = idx end
    this.max = #av_steps
    return current
end

expo_menu.submenu["Restore startup"].select = function(this)
    restore_startup()
end

init_startup()
