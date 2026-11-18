local testState = dofile("tests/support/pz_harness.lua")()
local check = testState.check
local list = testState.list
local square = testState.square
local worldObject = testState.worldObject
local save = testState.save
local fire = testState.fire
local start = testState.start
local loaded = testState.loaded
local handlers = testState.handlers
local runtime = testState.runtime
local simulation = testState.simulation
local player = testState.player
local key = testState.key
local definitions = testState.definitions

local runtimeRegistry, runtimeJava = start()
local sensorSquare, displaySquare = square(20, 20, 0), square(21, 20, 0)
local sensor = worldObject(sensorSquare, { id = "sensor", kind = "endpoint", definitionId = "ZedComm.PressureSensor" })
local cable = worldObject(sensorSquare, { id = "wire", kind = "cable" })
local display = worldObject(displaySquare, { id = "display", kind = "endpoint", definitionId = "ZedComm.NumericDisplay" })
local definitions = ZedComm.DeviceDefinitions

local actors = {}
function sensorSquare.getMovingObjects() return list(actors) end
instanceof = function(object, class)
    return object.class == class or (class == "IsoPlayer" and object.class == "IsoAnimal")
end
for _, object in ipairs({ sensor, cable, display }) do fire("OnObjectAdded", object) end
assert(runtimeRegistry:link("wire", "sensor"))
assert(runtimeRegistry:link("wire", "display"))
require "ZedComm/SimulationRunner"
local runtime = ZedComm.DeviceRuntime
local simulation = ZedComm.Simulation
local function expectReading(value, lit, present, message)
    fire("OnTick")
    local got, on, connected = runtime.getDisplay(display)
    check(got == value and on == lit and connected == present, message)
end

check(#handlers.OnTick == 1, "runtime uses the single simulation tick handler")
expectReading(0, false, true, "empty sensor delivers valid zero on the first tick")
actors = { { class = "BaseVehicle" } }
expectReading(0, false, true, "an unrelated moving object does not activate the sensor")
actors = { { class = "IsoPlayer" } }
expectReading(1, true, true, "player activates the display in the same tick")
local processed = simulation.processed
expectReading(1, true, true, "held input keeps the display on")
check(simulation.processed == processed, "held input schedules no duplicate recompute")
actors = {}
expectReading(0, false, true, "leaving the square updates the display to zero")
actors = { { class = "IsoZombie" } }
expectReading(1, true, true, "zombie activates the display")

assert(runtimeRegistry:unlink("wire", "sensor"))
expectReading(nil, false, true, "cutting source leaves display attached with no signal")
assert(runtimeRegistry:link("wire", "sensor"))
expectReading(1, true, true, "reconnecting restores the same held value")
assert(runtimeRegistry:unlink("wire", "display"))
expectReading(nil, false, false, "detached display has no runtime reading")
assert(runtimeRegistry:link("wire", "display"))
expectReading(1, true, true, "reattached display reads the current source")

loaded[key(20, 20, 0)] = nil
expectReading(nil, false, true, "unloaded source fails off without replaying its saved byte")
loaded[key(20, 20, 0)] = true
expectReading(1, true, true, "source returning with the same byte restores the signal")
loaded[key(21, 20, 0)] = nil
expectReading(nil, false, false, "unloaded receiver loses its transient reading")
loaded[key(21, 20, 0)] = true
expectReading(1, true, true, "loaded receiver reconciles even with a quiet source")

local runtimeSave = save(runtimeJava)
runtimeRegistry, runtimeJava = start(runtimeSave)
actors = {}
expectReading(0, false, true, "reload samples live occupancy before delivering the saved high byte")
processed = simulation.processed
expectReading(0, false, true, "reload maintains a stable reading")
check(simulation.processed == processed and #handlers.OnTick == 1,
    "reloaded registry does not add subscriptions or repeatedly dirty the circuit")

-- A broken extension callback is isolated and drives no signal.
local broken = {
    id = "Example.BrokenSource", role = "source", ports = { "signal" },
    match = function() return false end,
    sample = function() error("test callback failure") end,
}
assert(definitions.register(broken))
local brokenSensor = worldObject(sensorSquare, {
    id = "broken", kind = "endpoint", definitionId = broken.id, value = 255,
})
fire("OnObjectAdded", brokenSensor)
assert(runtimeRegistry:unlink("wire", "sensor"))
assert(runtimeRegistry:link("wire", "broken"))
expectReading(nil, false, true, "sample exception fails off without breaking the game tick")

testState.finish()
