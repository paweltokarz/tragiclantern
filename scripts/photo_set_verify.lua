-- 750D controlled exposure write/restore verifier
-- Safe test: no shooting, no generic property.request_change, Lua camera API only.

local LOG_PATH = "ML/LOGS/PHOTOSET2.TXT"

local m = menu.new{
    parent = "Debug",
    name = "Lua Photo Set Verify",
    help = "Set, verify and restore ISO/Tv/Av via Lua camera API.",
    submenu = {{
        name = "Run verify",
        help = "Hard-verify ISO, shutter and aperture writes, then restore old values.",
        icon_type = ICON_TYPE.ACTION,
    }},
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

local function get_raw(label, fn)
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
    get_raw("camera.mode", function() return camera.mode end)
    get_raw("camera.gui.idle", function() return camera.gui.idle end)
    get_raw("camera.iso.raw", function() return camera.iso.raw end)
    get_raw("camera.iso.value", function() return camera.iso.value end)
    get_raw("camera.iso.apex", function() return camera.iso.apex end)
    get_raw("camera.shutter.raw", function() return camera.shutter.raw end)
    get_raw("camera.shutter.ms", function() return camera.shutter.ms end)
    get_raw("camera.shutter.apex", function() return camera.shutter.apex end)
    get_raw("camera.aperture.raw", function() return camera.aperture.raw end)
    get_raw("camera.aperture.value", function() return camera.aperture.value end)
    get_raw("camera.aperture.apex", function() return camera.aperture.apex end)
    get_raw("camera.aperture.min.raw", function() return camera.aperture.min.raw end)
    get_raw("camera.aperture.max.raw", function() return camera.aperture.max.raw end)
end

local function set_verify(label, setter, getter, target)
    local before = nil
    local ok_read, value_before = pcall(getter)
    if ok_read then before = value_before end

    local ok_set, err = pcall(function()
        setter(target)
    end)

    if ok_set then
        out("SET_OK " .. label .. "=" .. tostring(target))
    else
        out("SET_FAIL " .. label .. "=" .. tostring(target) .. ": " .. tostring(err))
        return false
    end

    -- Give Canon property handlers a short chance to settle.
    -- sleep() is available in ML Lua; use 1 second to avoid relying on subsecond support.
    pcall(function() sleep(1) end)

    local ok_after, after = pcall(getter)
    if not ok_after then
        out("VERIFY_FAIL " .. label .. ": readback failed: " .. tostring(after))
        return false
    end

    if after == target then
        out("VERIFY_OK " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
        return true
    else
        out("VERIFY_FAIL " .. label .. " before=" .. tostring(before) .. " target=" .. tostring(target) .. " after=" .. tostring(after))
        return false
    end
end

local function choose_iso(old)
    if old == 80 then return 72 end
    return 80
end

local function choose_shutter(old)
    if old == 88 then return 93 end
    return 88
end

local function valid_av_candidate(v, minv, maxv)
    if v == minv or v == maxv then return true end
    if v < minv or v > maxv then return false end
    local r = v % 8
    return r == 0 or r == 3 or r == 4 or r == 5
end

local function choose_aperture(old, minv, maxv)
    -- Prefer known Canon-friendly raw Av steps. On EF-S18-55 at ~34mm,
    -- old often is 48 and min is 43; 43/45/48 were observed from manual changes.
    local candidates = { minv, minv + 2, minv + 5, old + 3, old - 3, maxv }
    for i = 1, #candidates do
        local v = candidates[i]
        if v ~= old and valid_av_candidate(v, minv, maxv) then
            return v
        end
    end
    return old
end

local function run_verify()
    console.show()
    lines = {}

    out("[750D Lua photo set verify]")
    out("Hard verification: setter success is not enough; readback must match target.")
    out("No shooting. No generic property.request_change.")
    out("_VERSION=" .. tostring(_VERSION))

    local old_iso = get_raw("initial.iso.raw", function() return camera.iso.raw end)
    local old_tv = get_raw("initial.shutter.raw", function() return camera.shutter.raw end)
    local old_av = get_raw("initial.aperture.raw", function() return camera.aperture.raw end)
    local min_av = get_raw("initial.aperture.min.raw", function() return camera.aperture.min.raw end)
    local max_av = get_raw("initial.aperture.max.raw", function() return camera.aperture.max.raw end)

    snapshot("before")

    if old_iso == nil or old_tv == nil or old_av == nil or min_av == nil or max_av == nil then
        out("ABORT missing initial readback")
        write_log()
        return
    end

    local target_iso = choose_iso(old_iso)
    local target_tv = choose_shutter(old_tv)
    local target_av = choose_aperture(old_av, min_av, max_av)

    out("[targets]")
    out("iso.raw=" .. tostring(target_iso))
    out("shutter.raw=" .. tostring(target_tv))
    out("aperture.raw=" .. tostring(target_av) .. " range=" .. tostring(min_av) .. ".." .. tostring(max_av))

    local iso_ok = set_verify(
        "camera.iso.raw",
        function(v) camera.iso.raw = v end,
        function() return camera.iso.raw end,
        target_iso
    )
    snapshot("after iso")

    local tv_ok = set_verify(
        "camera.shutter.raw",
        function(v) camera.shutter.raw = v end,
        function() return camera.shutter.raw end,
        target_tv
    )
    snapshot("after shutter")

    local av_ok = false
    if target_av ~= old_av then
        av_ok = set_verify(
            "camera.aperture.raw",
            function(v) camera.aperture.raw = v end,
            function() return camera.aperture.raw end,
            target_av
        )
    else
        out("SKIP camera.aperture.raw: no alternative candidate")
    end
    snapshot("after aperture")

    out("[restore]")
    set_verify(
        "restore camera.aperture.raw",
        function(v) camera.aperture.raw = v end,
        function() return camera.aperture.raw end,
        old_av
    )
    set_verify(
        "restore camera.shutter.raw",
        function(v) camera.shutter.raw = v end,
        function() return camera.shutter.raw end,
        old_tv
    )
    set_verify(
        "restore camera.iso.raw",
        function(v) camera.iso.raw = v end,
        function() return camera.iso.raw end,
        old_iso
    )
    snapshot("after restore")

    out("[summary]")
    out("iso_ok=" .. tostring(iso_ok))
    out("shutter_ok=" .. tostring(tv_ok))
    out("aperture_ok=" .. tostring(av_ok))

    write_log()

    if display and display.notify_box then
        display.notify_box("PHOTOSET2 done", 3000)
    end
end

m.submenu["Run verify"].select = function(this)
    run_verify()
end
