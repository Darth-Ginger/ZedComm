-- Load the shared native bootstrap and exercise its registered callbacks.
next = nil
local shared = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/shared/"
package.path = shared .. "?.lua;" .. package.path

local checks, failures = 0, 0
local function check(condition, message)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL: " .. message)
    end
end

require "ZedComm/NativeDevices"
local definitions = ZedComm.DeviceDefinitions
local sensorId = "ZedComm.PressureSensor"
local displayId = "ZedComm.NumericDisplay"
local sensor = assert(definitions.get(sensorId))
local display = assert(definitions.get(displayId))
local occupancy = assert(definitions.get("ZedComm.OccupancyPlate"))
local weightPlate = assert(definitions.get("ZedComm.WeightPlate"))
check(weightPlate.role == "source" and #weightPlate.ports == 1 and weightPlate.ports[1] == "signal",
    "weight plate registers one source port")
check(occupancy.role == "source" and #occupancy.ports == 1 and occupancy.ports[1] == "signal",
    "occupancy plate registers a single source port")
check(sensor.role == "source" and #sensor.ports == 1 and sensor.ports[1] == "signal",
    "sensor registers one source port")
check(display.role == "receiver" and #display.ports == 1 and display.ports[1] == "signal",
    "display registers one receiver port")

local context = {
    getDefinitionId = function(object)
        return object.definitionId
    end,
    isPressurePlateOccupied = function(object) return object.occupied end,
    getPressureOutput = function(object) return object.occupiedOutput or 1 end,
    getWeightPlateLoad = function(object) return object.load end,
    getOccupantCount = function(object) return object.count end,
    clearDisplay = function(object) object.value, object.lit = nil, nil end,
    setDisplay = function(object, value, lit)
        object.value = value
        object.lit = lit
    end,
}
local sensorObject = { definitionId = sensorId }
local displayObject = { definitionId = displayId }

local match, reason = definitions.match(sensorObject, context)
check(match and match.id == sensorId and reason == nil, "sensor identity matches")
match, reason = definitions.match(displayObject, context)
check(match and match.id == displayId and reason == nil, "display identity matches")
match, reason = definitions.match({ kind = "lamp" }, context)
check(match == nil and reason == nil, "untagged objects do not match")
match, reason = definitions.match({ definitionId = "Other.Display" }, context)
check(match == nil and reason == nil, "foreign identity does not match")

local function checkSample(occupied, expected, message)
    sensorObject.occupied = occupied
    check(sensor.sample(sensorObject, context) == expected, message)
end
checkSample(false, 0, "empty tile is OFF")
checkSample(true, 1, "an occupied tile uses the default output")
sensorObject.occupiedOutput = 255
checkSample(true, 255, "an occupied tile uses the configured byte")
checkSample(false, 0, "vacating the tile clears the signal")

local occupied = { definitionId = "ZedComm.OccupancyPlate", count = 4 }
check(occupancy.sample(occupied, context) == 4, "occupancy plate supplies the sampled actor count")

local weightObject = { definitionId = "ZedComm.WeightPlate" }
weightObject.load = 1150.25
check(weightPlate.readingKind == "weight" and weightPlate.sample(weightObject, context) == 1150.25,
    "the weight plate supplies the full unquantized load to its sender")

local modules = ZedComm.SignalModules
local readout = assert(modules.newReceiver(display.receiverModule, display.bindFixture(displayObject, context)))
check(display.receiverModule == modules.BYTE_READOUT, "display chooses the shared byte readout module")
local function checkDisplay(value, lit, message)
    readout:receive(value)
    check(displayObject.value == value and displayObject.lit == lit, message)
end
checkDisplay(255, true, "full-scale signal lights the indicator")
checkDisplay(0, false, "valid zero is preserved and the indicator turns off")
checkDisplay(0x5A, true, "mixed byte is preserved and lights the indicator")
checkDisplay(nil, false, "signal loss clears the previous value and turns the indicator off")
checkDisplay(0xA5, true, "restored signal replaces unavailable state")
check(readout:detach() == "detached" and displayObject.value == nil and displayObject.lit == nil,
    "display adapter clears its reading when detached")

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
