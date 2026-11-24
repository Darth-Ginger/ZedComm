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
local key = testState.key

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
expectReading(nil, false, true, "unloaded source fails off without replaying its last byte")
loaded[key(20, 20, 0)] = true
expectReading(1, true, true, "source returning with the same byte restores the signal")
loaded[key(21, 20, 0)] = nil
expectReading(nil, false, false, "unloaded receiver loses its transient reading")
loaded[key(21, 20, 0)] = true
expectReading(1, true, true, "loaded receiver reconciles even with a quiet source")

local runtimeSave = save(runtimeJava)
runtimeRegistry, runtimeJava = start(runtimeSave)
actors = {}
expectReading(0, false, true, "reload delivers live occupancy instead of the former high byte")
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

do
    local sourceTile, receiverTile = square(25, 20, 0), square(26, 20, 0)
    local available, calls = true, 0
    local definitionId = "Example.PoweredReceiver"
    assert(definitions.register({
        id = definitionId, role = "receiver", ports = { "signal" },
        match = function() return false end,
        receiverModule = ZedComm.SignalModules.ON_OFF,
        bindFixture = function()
            return {
                isAvailable = function()
                    if available == "error" then error("broken power callback") end
                    return available
                end,
                apply = function() calls = calls + 1; return "applied" end,
            }
        end,
    }))
    for _, object in ipairs({
        worldObject(sourceTile, { id = "powered-source", kind = "endpoint", definitionId = "ZedComm.DebugByteSource" }),
        worldObject(sourceTile, { id = "powered-wire", kind = "cable" }),
        worldObject(receiverTile, { id = "powered-receiver", kind = "endpoint", definitionId = definitionId }),
    }) do
        fire("OnObjectAdded", object)
    end
    assert(runtimeRegistry:link("powered-wire", "powered-source"))
    assert(runtimeRegistry:link("powered-wire", "powered-receiver"))
    fire("OnTick")
    local applied = calls
    available = "error"
    fire("OnTick")
    fire("OnTick")
    local errors = 0
    for _, line in ipairs(testState.logged) do
        if line:find("availability check failed:", 1, true) and line:find("broken power callback", 1, true) then
            errors = errors + 1
        end
    end
    check(errors == 1, "a repeating extension power error logs once")
    available = true
    fire("OnTick")
    check(applied > 0 and calls == applied, "an extension exception does not simulate power loss and recovery")
    available = false
    fire("OnTick")
    available = true
    fire("OnTick")
    check(calls == applied + 1, "actual power recovery still retries the latest signal")
end

do
    local registry = start()
    local sourceTile, sinkTile, boardTile = square(40, 40, 0), square(41, 40, 0), square(42, 40, 0)
    local sourceTag = { id = "weight", kind = "endpoint", definitionId = "ZedComm.WeightPlate" }
    local sinkTag = { id = "readout", kind = "endpoint", definitionId = "ZedComm.AdvancedDisplay" }
    local weight = worldObject(sourceTile, sourceTag)
    local readout = worldObject(sinkTile, sinkTag)
    local weightCable = worldObject(sourceTile, { id = "weight-wire", kind = "cable" })
    local cabinet = worldObject(boardTile, {
        id = "cabinet", kind = "endpoint", definitionId = "ZedComm.SmallCabinet",
        state = { circuit = { modules = {}, links = {} } },
    })
    local modules = ZedComm.SignalModules
    local mass = 80
    sourceTile.overlappingVehicle = { getMass = function() return mass end }
    function sourceTile.getMovingObjects() return list({}) end
    for _, object in ipairs({ weight, readout, weightCable, cabinet }) do fire("OnObjectAdded", object) end
    assert(registry:link("weight-wire", "weight"))
    assert(registry:link("weight-wire", "readout"))
    assert(runtime.setWeightPlateSender(registry, "weight", modules.ADVANCED_SENDER))

    local scans, loadScans, copies, encodes, publications = 0, 0, 0, 0, 0
    local getSourceObjects = sourceTile.getObjects
    function sourceTile:getObjects()
        loadScans = loadScans + 1
        return getSourceObjects(self)
    end
    for _, tile in ipairs({ sinkTile, boardTile }) do
        local getObjects = tile.getObjects
        function tile:getObjects()
            scans = scans + 1
            return getObjects(self)
        end
    end
    local getDefinition, encode, setPacket = definitions.get, modules.Sender.encode, registry.network.setPacket
    function definitions.get(id)
        copies = copies + 1
        return getDefinition(id)
    end
    function modules.Sender.encode(...)
        encodes = encodes + 1
        return encode(...)
    end
    function registry.network:setPacket(...)
        publications = publications + 1
        return setPacket(self, ...)
    end
    fire("OnTick")
    local function expectAdvanced(kg, message)
        local byte, _, attached, packet = runtime.getDisplay(readout)
        check(attached and byte == 8 and packet and packet.value.amount == kg, message)
    end
    expectAdvanced(80, "advanced receiver gets the first full reading")
    local beforeScans, beforeLoads, beforeCopies, beforePublishes = scans, loadScans, copies, publications
    for i = 1, 3 do fire("OnTick") end
    check(beforeScans >= 2 and scans == beforeScans and beforeCopies > 0 and copies == beforeCopies,
        "maintained fixtures reuse bindings and definitions across quiet ticks")
    check(loadScans == beforeLoads + 3, "a held weight source scans only for live furniture on each quiet tick")
    check(encodes == 1 and publications == beforePublishes,
        "the unchanged weight skips sender encoding and packet publication")
    mass = 81
    fire("OnTick")
    expectAdvanced(81, "changed weight reaches the advanced receiver with the same fallback byte")
    check(encodes == 2 and publications == beforePublishes + 1, "changed full reading publishes once")

    local old = readout
    testState.takeOff(sinkTile, old)
    readout = worldObject(sinkTile, sinkTag)
    registry:OnChunkLoaded(5, 5)
    fire("OnTick")
    local _, _, oldAttached = runtime.getDisplay(old)
    check(not oldAttached, "chunk reload removes the previous object's transient reading")
    expectAdvanced(81, "replacement on the same square receives the held reading")
    assert(runtime.setWeightPlateSender(registry, "weight", modules.BASIC_SENDER))
    fire("OnTick")
    local value, _, _, packet = runtime.getDisplay(readout)
    check(value == 8 and packet and packet.type == "signal.basic", "sender swap reencodes an unchanged sample")
end

testState.finish()
