local testState = dofile("tests/support/placement_harness.lua")()
local check = testState.check
local worldObject = testState.worldObject
local save = testState.save
local fire = testState.fire
local start = testState.start
local loaded = testState.loaded
local runtime = testState.runtime
local carried = testState.carried
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local placedReading = testState.placedReading
local key = testState.key
local definitions = testState.definitions


-- Durable installation data uses the same save and pickup path as devices.
do
    testState.registry, testState.java = start()
    local sourceSquare, wireSquare, displaySquare = floorTile(80, 80), floorTile(81, 80), floorTile(82, 80)
    local source = worldObject(sourceSquare, {
        id = "module-test-source", kind = "endpoint", definitionId = "ZedComm.DebugByteSource",
    })
    local wire = worldObject(wireSquare, { id = "module-test-wire", kind = "cable" })
    fire("OnObjectAdded", source)
    fire("OnObjectAdded", wire)
    assert(testState.registry:link("module-test-wire", "module-test-source"))
    local ok, displayId = runPlacement(displaySquare, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(ok, displayId)
    local moduleId = ZedComm.SignalModules.BYTE_READOUT
    local configuration = { module = { id = moduleId, config = { label = "North bench" } } }
    assert(testState.registry:setDeviceState(displayId, configuration))
    assert(testState.registry:link("module-test-wire", displayId))
    assert(runtime.setTestByte(testState.registry, "module-test-source", "170"))
    check(placedReading(displayId) == 170, "explicit byte readout installation works through the runtime")

    testState.registry, testState.java = start(save(testState.java))
    local saved = testState.registry.network:record(displayId).state.module
    check(saved.id == moduleId and saved.config.label == "North bench" and saved.request == nil
        and saved.attached == nil and placedReading(displayId) == 170,
        "reload restores module identity and config and rebuilds the live reading")

    assert(testState.registry:setDeviceState(displayId, { module = { id = "Example.MissingModule" } }))
    local value, _, attached = placedReading(displayId)
    check(value == nil and not attached and testState.registry.network:record(displayId).state.module.id == "Example.MissingModule"
        and testState.registry.network.pieces[displayId].ports.signal == "module-test-wire",
        "incompatible saved module disables delivery while preserving configuration and wiring")
    assert(testState.registry:setDeviceState(displayId, configuration))
    check(placedReading(displayId) == 170, "restored module receives the held byte without a source change")

    assert(target(displaySquare, displayId, "pickup"))
    fire("OnTick")
    local item = carried[#carried]
    local kept = item:getModData().zedcommPlacement.state.module
    check(kept.id == moduleId and kept.config.label == "North bench" and testState.registry.network.pieces["module-test-wire"],
        "pickup retains module configuration and leaves the wire in place")
    local replaced, idAgain = runPlacement(displaySquare, { kind = "place", item = item })
    assert(replaced, idAgain)
    local valueAgain, _, attachedAgain = placedReading(idAgain)
    check(idAgain == displayId and valueAgain == nil and not attachedAgain
        and testState.registry.network.pieces[idAgain].ports.signal == false,
        "replacement retains identity and waits for a new wire connection")
    assert(testState.registry:link("module-test-wire", idAgain))
    check(placedReading(idAgain) == 170, "reconnecting the recovered fixture restores the held byte")
    assert(testState.registry:unlink("module-test-wire", idAgain))

    local calls = { binds = 0, releases = 0, values = {} }
    assert(definitions.register({
        id = "Example.ModularFixture", role = "receiver", ports = { "signal" },
        match = function() return false end, receiverModule = moduleId,
        bindFixture = function(_, _, config)
            calls.binds = calls.binds + 1
            calls.label = config.label
            config.label = "changed by fixture"
            return {
                apply = function(_, byte)
                    calls.values[#calls.values + 1] = { byte = byte }
                    return "applied"
                end,
                release = function() calls.releases = calls.releases + 1 end,
            }
        end,
    }))
    local otherSquare = floorTile(81, 81)
    local modular = worldObject(otherSquare, {
        id = "modular-fixture", kind = "endpoint", definitionId = "Example.ModularFixture",
        state = { module = { id = moduleId, config = { label = "copied" } } },
    })
    fire("OnObjectAdded", modular)
    assert(testState.registry:link("module-test-wire", "modular-fixture"))
    fire("OnTick")
    fire("OnTick")
    check(calls.binds == 1 and #calls.values == 1 and calls.values[1].byte == 170
        and calls.label == "copied" and testState.registry.network:record("modular-fixture").state.module.config.label == "copied",
        "runtime binds once and gives the adapter a copy of durable config")
    loaded[key(81, 81, 0)] = nil
    fire("OnTick")
    fire("OnTick")
    check(calls.releases == 1, "unloading a receiver releases its module exactly once")
    loaded[key(81, 81, 0)] = true
    fire("OnTick")
    check(calls.binds == 2 and #calls.values == 2 and calls.values[2].byte == 170,
        "reloading the fixture attaches a fresh module and reads the held byte")

    assert(testState.registry:unlink("module-test-wire", "modular-fixture"))
end

testState.finish()
