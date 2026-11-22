local test = dofile("tests/support/pz_harness.lua")()
local check, fire = test.check, test.fire
local registry, java = test.start()
local Sensors = ZedComm.EnvironmentalSensors
local hour, minute, delta = 0, 0, 0
getGameTime = function()
    return {
        getHour = function() return hour end,
        getMinutes = function() return minute end,
        getRealworldSecondsSinceLastUpdate = function() return delta end,
    }
end

local power, powerQueries = false, 0
ItemContainer = { isObjectPowered = function(_, allowGenerator)
    assert(allowGenerator)
    powerQueries = powerQueries + 1
    return power
end }
local snow, rain, light = false, 0, 1
getClimateManager = function()
    return {
        getPrecipitationIsSnow = function() return snow end,
        getRainIntensity = function() return rain end,
        getDayLightStrength = function() return light end,
    }
end

local function circuit(id, definition, x)
    local tile, sinkTile = test.square(x, 1, 0), test.square(x + 1, 1, 0)
    tile.outside, tile.roofed = true, false
    function tile:isOutside() return self.outside end
    function tile:haveRoofFull() return self.roofed end
    local sensor = test.worldObject(tile, { id = id, kind = "endpoint", definitionId = definition })
    local wire = test.worldObject(tile, { id = id .. "wire", kind = "cable" })
    local display = test.worldObject(sinkTile, {
        id = id .. "display", kind = "endpoint", definitionId = "ZedComm.NumericDisplay",
    })
    for _, object in ipairs({ sensor, wire, display }) do fire("OnObjectAdded", object) end
    assert(registry:link(id .. "wire", id))
    assert(registry:link(id .. "wire", id .. "display"))
    return display, tile
end

local clockDisplay = circuit("clock", Sensors.CLOCK, 10)
local powerDisplay = circuit("power", Sensors.POWER, 20)
local daylightDisplay, daylightTile = circuit("light", Sensors.DAYLIGHT, 30)
local rainDisplay, rainTile = circuit("rain", Sensors.RAIN, 40)
require "ZedComm/SimulationRunner"
local Runtime = ZedComm.DeviceRuntime
local function sample(step)
    delta = step or 1
    fire("OnTick")
end

sample(0)
check(Runtime.getDisplay(clockDisplay) == 0, "same start and end defaults to off")
check(Runtime.getDisplay(powerDisplay) == 0, "power loss publishes valid zero")
check(Runtime.getDisplay(daylightDisplay) == 255 and Runtime.getDisplay(rainDisplay) == 0,
    "full daylight and dry weather publish opposite byte endpoints")
check(not Sensors.configureSchedule(registry, "clock", "24:00, 00:00"), "invalid hours are refused")
check(not Sensors.configureSchedule(registry, "clock", "10:60, 11:00"), "invalid minutes are refused")
check(Sensors.formatTime(21 * 60 + 5) == "21:05", "time is formatted at minute precision")

hour, minute = 22, 0
assert(Sensors.configureSchedule(registry, "clock", "22:00, 06:00"))
sample(0.1)
check(Runtime.getDisplay(clockDisplay) == 255, "configuration publishes immediately and includes starting minute")
hour, minute = 5, 59
sample()
check(Runtime.getDisplay(clockDisplay) == 255, "schedule remains on after crossing midnight")
hour, minute = 6, 0
sample()
check(Runtime.getDisplay(clockDisplay) == 0, "schedule excludes ending minute")
check(Sensors.scheduleValue(12 * 60, 10 * 60, 18 * 60) == 255
    and Sensors.scheduleValue(9 * 60, 10 * 60, 18 * 60) == 0, "daytime schedule follows the same boundaries")

local previousQueries = powerQueries
power = true
sample(0.2)
check(powerQueries == previousQueries and Runtime.getDisplay(powerDisplay) == 0, "slow sensors reuse their reading between samples")
sample()
check(Runtime.getDisplay(powerDisplay) == 255, "native grid or generator power publishes on")
test.loaded[test.key(20, 1, 0)] = nil
sample(0.1)
check(Runtime.getDisplay(powerDisplay) == nil, "unloading clears the reading without waiting for the next sample")
test.loaded[test.key(20, 1, 0)] = true
sample(0.1)
check(Runtime.getDisplay(powerDisplay) == 255, "a reloaded source samples immediately")
power = false
sample()
check(Runtime.getDisplay(powerDisplay) == 0, "power loss continues to provide a valid byte")

rain, light = 0.5, 0.25
sample()
check(Runtime.getDisplay(rainDisplay) == 128 and Runtime.getDisplay(daylightDisplay) == 64, "environmental values round to the nearest byte")
rainTile.roofed, daylightTile.outside = true, false
sample()
check(Runtime.getDisplay(rainDisplay) == 0 and Runtime.getDisplay(daylightDisplay) == 0, "roofed exterior and indoor sensors read zero")
rainTile.roofed, snow = false, true
sample()
check(Runtime.getDisplay(rainDisplay) == 0, "snow does not produce a rain byte")
snow, rain = false, 1.5
sample()
check(Runtime.getDisplay(rainDisplay) == 255, "rain levels clamp at the upper limit")

registry = test.start(test.save(java))
hour, minute = 23, 59
sample(0.1)
check(registry.network.pieces.clock.state.endMinute == 360 and Runtime.getDisplay(clockDisplay) == 255,
    "saved schedule is used immediately after reload")

test.finish()
