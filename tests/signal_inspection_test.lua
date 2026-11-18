local testState = dofile("tests/support/placement_harness.lua")()
local check = testState.check
local worldObject = testState.worldObject
local save = testState.save
local fire = testState.fire
local start = testState.start
local loaded = testState.loaded
local runtime = testState.runtime
local simulation = testState.simulation
local floorTile = testState.floorTile
local key = testState.key

local p0, w0, w1, d0, plateId, displayId, replacement, secondWire = dofile("tests/support/bend_fixture.lua")(testState)

-- The development source drives arbitrary bytes through the actual runtime.
local byteTile, byteWireTile, byteDisplayTile = floorTile(60, 60), floorTile(61, 60), floorTile(62, 60)
local byteSource = worldObject(byteTile, {
    id = "debug-byte", kind = "endpoint", definitionId = "ZedComm.DebugByteSource", rigWire = "debug-wire",
})
byteSource.sprite = "zedcomm_devices_01_0"
function byteSource.getSprite() return getSprite(byteSource.sprite) end
function byteSource.setSprite(_, sprite) byteSource.sprite = sprite:getName() end
local byteWire = worldObject(byteWireTile, { id = "debug-wire", kind = "cable" })
local byteDisplay = worldObject(byteDisplayTile, {
    id = "debug-display", kind = "endpoint", definitionId = "ZedComm.NumericDisplay",
})
for _, object in ipairs({ byteSource, byteWire, byteDisplay }) do fire("OnObjectAdded", object) end
assert(testState.registry:link("debug-wire", "debug-byte", "signal"))
assert(testState.registry:link("debug-wire", "debug-display", "signal"))
fire("OnTick")
check(byteSource.sprite == "zedcomm_devices_01_0", "the byte test source keeps its original sprite")
local report = runtime.inspect("debug-wire")
check(report.status == "ok" and report.sourceByte == 0 and report.receivers[1].value == 0,
    "inspector distinguishes valid zero from signal loss")
for _, value in ipairs({ 85, 170, 42, 255 }) do
    assert(runtime.setTestByte(testState.registry, "debug-byte", tostring(value)))
    fire("OnTick")
    report = runtime.inspect("debug-display")
    check(report.sourceId == "debug-byte" and report.sourceByte == value
        and report.receivers[1].value == value, "inspector reports byte " .. value .. " end to end")
end
do
    local model = testState.registry.network
    local function deliverWeight(fallback, expected)
        assert(model:setPacket("debug-byte", {
            type = "signal.advanced", value = { kind = "weight", amount = 1150, unit = "kg" },
            basicValue = fallback,
        }))
        simulation.tick()
        local value, _, attached = runtime.getDisplay(byteDisplay)
        return value == expected and attached and runtime.inspect("debug-wire").status == "ok"
    end
    check(deliverWeight(115, 115), "an advanced packet's sender-provided fallback reaches the byte display")
    check(deliverWeight(0, 0), "zero remains a valid advanced fallback")
    check(deliverWeight(256, nil), "an invalid fallback leaves the attached display without a reading")
    check(deliverWeight(nil, nil), "an absent fallback leaves the attached display without a reading")
end
check(not runtime.setTestByte(testState.registry, "debug-byte", "256")
    and not runtime.setTestByte(testState.registry, "debug-byte", "0.5")
    and not runtime.setTestByte(testState.registry, plateId, "85")
    and testState.registry.network:record("debug-byte").state.byte == 255,
    "invalid bytes and non-debug devices are rejected without changing the source")
assert(runtime.setTestByte(testState.registry, "debug-byte", "170"))
fire("OnTick")
testState.registry, testState.java = start(save(testState.java))
fire("OnTick")
check(runtime.inspect("debug-display").receivers[1].value == 170,
    "the debug source and receiver recover their configured byte after reload")
loaded[key(60, 60, 0)] = nil
fire("OnTick")
report = runtime.inspect("debug-display")
check(report.status == "no-source" and report.sourceByte == nil
    and report.receivers[1].reading and report.receivers[1].value == nil,
    "an unloaded source yields no signal while its attached receiver stays bound")
loaded[key(60, 60, 0)] = true
fire("OnTick")
check(runtime.inspect("debug-display").receivers[1].value == 170,
    "source reload restores the current byte without a sender change")

testState.finish()
