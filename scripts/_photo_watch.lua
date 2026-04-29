-- 750D photo property watcher
-- Read-only property event logger for Canon EOS 750D / ML Lua.

local LOG_PATH = "ML/LOGS/PHOTOWAT.TXT"

local watch_menu = menu.new
{
    parent = "Debug",
    name = "Lua Photo Watch",
    help = "Read-only property watcher for photo/exposure events",
    submenu =
    {
        {
            name = "Start watch",
            help = "Register property handlers and log changes to ML/LOGS/PHOTOWAT.TXT.",
            icon_type = ICON_TYPE.ACTION,
        },
        {
            name = "Stop watch",
            help = "Unregister property handlers.",
            icon_type = ICON_TYPE.ACTION,
        },
    },
}

local active = false
local lines = {}

local props = {
    { name = "MODE",          obj = property.MODE },
    { name = "SHUTTER",       obj = property.SHUTTER },
    { name = "APERTURE",      obj = property.APERTURE },
    { name = "APERTURE3",     obj = property.APERTURE3 },
    { name = "ISO",           obj = property.ISO },
    { name = "AE",            obj = property.AE },
    { name = "ISO_AUTO",      obj = property.ISO_AUTO },
    { name = "SHUTTER_AUTO",  obj = property.SHUTTER_AUTO },
    { name = "APERTURE_AUTO", obj = property.APERTURE_AUTO },
    { name = "GUI_STATE",     obj = property.GUI_STATE },
    { name = "HALF_SHUTTER",  obj = property.HALF_SHUTTER },
    { name = "METERING_MODE", obj = property.METERING_MODE },
    { name = "DRIVE",         obj = property.DRIVE },
    { name = "AF_MODE",       obj = property.AF_MODE },
}

local function log_line(s)
    print(s)
    lines[#lines + 1] = s
    local ok, err = pcall(function()
        local f = assert(io.open(LOG_PATH, "a"))
        f:write(s)
        f:write("\n")
        f:close()
    end)
    if not ok then
        print("PHOTOWAT log write failed: " .. tostring(err))
    end
end

local function safe_value(label, fn)
    local ok, ret = pcall(fn)
    if ok then
        return label .. "=" .. tostring(ret)
    else
        return label .. "=<ERR " .. tostring(ret) .. ">"
    end
end

local function exposure_snapshot()
    return table.concat({
        safe_value("mode", function() return camera.mode end),
        safe_value("gui_idle", function() return camera.gui.idle end),
        safe_value("tv_raw", function() return camera.shutter.raw end),
        safe_value("tv_ms", function() return camera.shutter.ms end),
        safe_value("tv_apex", function() return camera.shutter.apex end),
        safe_value("av_raw", function() return camera.aperture.raw end),
        safe_value("av_value", function() return camera.aperture.value end),
        safe_value("av_apex", function() return camera.aperture.apex end),
        safe_value("iso_raw", function() return camera.iso.raw end),
        safe_value("iso_value", function() return camera.iso.value end),
        safe_value("iso_apex", function() return camera.iso.apex end),
        safe_value("ec_raw", function() return camera.ec.raw end),
        safe_value("ec_value", function() return camera.ec.value end),
    }, " ")
end

local function register_handlers()
    for i = 1, #props do
        local p = props[i]
        p.obj.handler = function(self, value)
            log_line("PROP " .. p.name .. " value=" .. tostring(value) .. " | " .. exposure_snapshot())
        end
    end
end

local function unregister_handlers()
    for i = 1, #props do
        local p = props[i]
        p.obj.handler = nil
    end
end

local function start_watch()
    console.show()
    if active then
        log_line("PHOTOWAT already active")
        return
    end

    local ok, err = pcall(function()
        local f = assert(io.open(LOG_PATH, "w"))
        f:write("[750D photo property watch]\n")
        f:close()
    end)
    if not ok then
        print("PHOTOWAT cannot create log: " .. tostring(err))
    end

    lines = {}
    active = true
    register_handlers()
    log_line("PHOTOWAT started")
    log_line("Initial: " .. exposure_snapshot())

    if display and display.notify_box then
        display.notify_box("Photo watch started", 3000)
    end
end

local function stop_watch()
    console.show()
    if not active then
        print("PHOTOWAT not active")
        return
    end
    unregister_handlers()
    active = false
    log_line("PHOTOWAT stopped")
    if display and display.notify_box then
        display.notify_box("Photo watch stopped", 3000)
    end
end

watch_menu.submenu["Start watch"].select = function(this)
    start_watch()
end

watch_menu.submenu["Stop watch"].select = function(this)
    stop_watch()
end
