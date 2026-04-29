-- Lua 750D diagnostic
-- Safe menu-driven runtime test for Canon EOS 750D / ML 1.1.0

local diag_menu = menu.new
{
    parent = "Debug",
    name = "Lua 750D Diag",
    help = "Safe Lua runtime diagnostic for 750D",
    submenu =
    {
        {
            name = "Run diag",
            help = "Show console, print API status, and write ML/LOGS/LUA750D.TXT.",
            icon_type = ICON_TYPE.ACTION,
        },
    },
}

local function line_value(name, fn)
    local ok, ret = pcall(fn)
    if ok then
        return "OK   " .. name .. ": " .. tostring(ret)
    else
        return "FAIL " .. name .. ": " .. tostring(ret)
    end
end

local function write_log(lines)
    local ok, err = pcall(function()
        local f = assert(io.open("ML/LOGS/LUA750D.TXT", "w"))
        for i = 1, #lines do
            f:write(lines[i])
            f:write("\n")
        end
        f:close()
    end)

    if ok then
        print("Log written: ML/LOGS/LUA750D.TXT")
    else
        print("Log write FAILED: " .. tostring(err))
    end
end

local function run_diag()
    console.show()

    local lines = {}
    local function out(s)
        print(s)
        lines[#lines + 1] = s
    end

    out("[750D Lua diag]")
    out("Lua runtime is alive.")
    out("_VERSION=" .. tostring(_VERSION))
    out(line_value("console.visible", function() return console.visible end))
    out(line_value("camera", function() return type(camera) end))
    out(line_value("camera.mode", function() return camera.mode end))
    out(line_value("camera.gui.idle", function() return camera.gui.idle end))
    out(line_value("lens", function() return type(lens) end))
    out(line_value("lens.focal_length", function() return lens.focal_length end))
    out(line_value("battery.level", function() return battery.level end))
    out(line_value("display.notify_box", function() return type(display.notify_box) end))
    out(line_value("menu", function() return type(menu) end))
    out(line_value("key", function() return type(key) end))

    write_log(lines)

    if display and display.notify_box then
        display.notify_box("Lua 750D diag OK", 3000)
    end

    out("Done.")
end

diag_menu.submenu["Run diag"].select = function(this)
    run_diag()
end
