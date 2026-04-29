-- 750D photo diagnostics
-- Safe read-only exposure/property probe for Canon EOS 750D / ML Lua.

local photo_menu = menu.new
{
    parent = "Debug",
    name = "Lua Photo Diag",
    help = "Read-only photo/exposure/property diagnostics for 750D",
    submenu =
    {
        {
            name = "Run readout",
            help = "Print and log current camera, lens and exposure values.",
            icon_type = ICON_TYPE.ACTION,
        },
    },
}

local function safe(name, fn)
    local ok, ret = pcall(fn)
    if ok then
        return "OK   " .. name .. ": " .. tostring(ret)
    else
        return "FAIL " .. name .. ": " .. tostring(ret)
    end
end

local function write_log(path, lines)
    local ok, err = pcall(function()
        local f = assert(io.open(path, "w"))
        for i = 1, #lines do
            f:write(lines[i])
            f:write("\n")
        end
        f:close()
    end)
    if ok then
        print("Log written: " .. path)
    else
        print("Log write FAILED: " .. tostring(err))
    end
end

local function add_exposure_object(lines, label, obj, fields)
    lines[#lines + 1] = "[" .. label .. "]"
    lines[#lines + 1] = safe(label .. ".tostring", function() return tostring(obj) end)
    for i = 1, #fields do
        local field = fields[i]
        lines[#lines + 1] = safe(label .. "." .. field, function() return obj[field] end)
    end
end

local function run_readout()
    console.show()

    local lines = {}
    local function out(s)
        print(s)
        lines[#lines + 1] = s
    end

    out("[750D photo diag]")
    out("Read-only Lua exposure/property probe.")
    out("_VERSION=" .. tostring(_VERSION))

    out("[camera]")
    out(safe("camera.model", function() return camera.model end))
    out(safe("camera.model_short", function() return camera.model_short end))
    out(safe("camera.firmware", function() return camera.firmware end))
    out(safe("camera.mode", function() return camera.mode end))
    out(safe("camera.metering_mode", function() return camera.metering_mode end))
    out(safe("camera.drive_mode", function() return camera.drive_mode end))
    out(safe("camera.temperature", function() return camera.temperature end))
    out(safe("camera.gui.idle", function() return camera.gui.idle end))
    out(safe("camera.gui.menu", function() return camera.gui.menu end))
    out(safe("camera.gui.play", function() return camera.gui.play end))
    out(safe("camera.gui.qr", function() return camera.gui.qr end))

    out("[lens]")
    out(safe("lens.name", function() return lens.name end))
    out(safe("lens.focal_length", function() return lens.focal_length end))
    out(safe("lens.focus_distance", function() return lens.focus_distance end))
    out(safe("lens.focus_pos", function() return lens.focus_pos end))
    out(safe("lens.af", function() return lens.af end))
    out(safe("lens.af_mode", function() return lens.af_mode end))
    out(safe("lens.autofocusing", function() return lens.autofocusing end))

    add_exposure_object(lines, "camera.shutter", camera.shutter, {"raw", "value", "ms", "apex"})
    add_exposure_object(lines, "camera.aperture", camera.aperture, {"raw", "value", "apex"})
    add_exposure_object(lines, "camera.aperture.min", camera.aperture.min, {"raw", "value", "apex"})
    add_exposure_object(lines, "camera.aperture.max", camera.aperture.max, {"raw", "value", "apex"})
    add_exposure_object(lines, "camera.iso", camera.iso, {"raw", "value", "apex"})
    add_exposure_object(lines, "camera.ec", camera.ec, {"raw", "value"})
    add_exposure_object(lines, "camera.flash_ec", camera.flash_ec, {"raw", "value"})

    out("[property objects]")
    out(safe("property.MODE", function() return tostring(property.MODE) end))
    out(safe("property.SHUTTER", function() return tostring(property.SHUTTER) end))
    out(safe("property.APERTURE", function() return tostring(property.APERTURE)
end))
    out(safe("property.ISO", function() return tostring(property.ISO) end))
    out(safe("property.AE", function() return tostring(property.AE) end))
    out(safe("property.GUI_STATE", function() return tostring(property.GUI_STATE) end))
    out(safe("property.HALF_SHUTTER", function() return tostring(property.HALF_SHUTTER) end))

    for i = 1, #lines do
        print(lines[i])
    end

    write_log("ML/LOGS/PHOTODIA.TXT", lines)

    if display and display.notify_box then
        display.notify_box("Photo diag log written", 3000)
    end
end

photo_menu.submenu["Run readout"].select = function(this)
    run_readout()
end
