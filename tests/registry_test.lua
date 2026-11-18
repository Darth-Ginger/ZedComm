local testState = dofile("tests/support/pz_harness.lua")()
local Packet = testState.Packet
local check = testState.check
local square = testState.square
local worldObject = testState.worldObject
local takeOff = testState.takeOff
local save = testState.save
local fire = testState.fire
local start = testState.start
local tileIds = testState.tileIds
local loaded = testState.loaded
local key = testState.key
local definitions = testState.definitions


-- Layout: sensor S and cable c1 share square (0,0); c2 at (1,0); display D at (1,1).
local reg, java = start()
check(reg ~= nil and reg.network ~= nil, "the system starts and builds an empty network")
check(java.objectKeys and java.objectKeys[1] == "pieces", "only the pieces table is saved per square")

local sq00, sq10, sq11 = square(0, 0, 0), square(1, 0, 0), square(1, 1, 0)
local oS = worldObject(sq00, { id = "S", kind = "endpoint", definitionId = "ZedComm.DebugByteSource" })
local oC1 = worldObject(sq00, { id = "c1", kind = "cable" })
local oC2 = worldObject(sq10, { id = "c2", kind = "cable" })
local oD = worldObject(sq11, { id = "D", kind = "endpoint", definitionId = "ZedComm.NumericDisplay" })
local oC9 = worldObject(sq00, { id = "c9", kind = "cable" }) -- spare, never linked
for _, o in ipairs({ oS, oC1, oC2, oD, oC9 }) do fire("OnObjectAdded", o) end

check(tileIds(java, 0, 0, 0) == "S,c1,c9", "three pieces on one square share one record")
fire("OnObjectAdded", oC1)
check(tileIds(java, 0, 0, 0) == "S,c1,c9", "adding a known object again registers nothing twice")
local clash = worldObject(sq10, { id = "S", kind = "cable" })
fire("OnObjectAdded", clash)
takeOff(sq10, clash)
check(reg.network.pieces.S.kind == "endpoint", "a clashing id is refused, not overwritten")

check(reg:link("c1", "S"), "a cable terminates on the sensor on its own square")
check(reg:link("c1", "c2"), "adjacent cables link")
check(reg:link("c2", "D"), "the run terminates on the display")
check(reg.network:setPacket("S", Packet.basic(255)), "the sensor value can change")
local net = reg.network
check(net:networkOf("S") == net:networkOf("D"), "sensor and display share a network")

local recS = java:getObjectAt(0, 0, 0).data.pieces.S
local recC2 = java:getObjectAt(1, 0, 0).data.pieces.c2
check(recS.ports.signal == "c1" and recS.value == nil and recS.packet == nil, "the sensor record holds its link without a live packet")
check(recC2.links.c1 == true and recC2.links.D == "signal", "a cable's record holds both its links")

-- Save and load: the network is rebuilt from the records alone.
local saved = save(java)
local reg2, java2 = start(saved)
local net2 = reg2.network
check(net2:networkOf("S") == net2:networkOf("D"), "connectivity is derived again after load")
check(net2:recompute(net2:networkOf("D")) == nil, "reload waits for the source to publish")
for _, o in ipairs({ oS, oC1, oC2, oD, oC9 }) do fire("OnObjectAdded", o) end
local count = 0
for _ in pairs(net2.pieces) do count = count + 1 end
check(count == 5 and java2:getObjectCount() == 3, "objects reloading after the records registers nothing twice")

-- Removing one of two pieces on a square leaves the other.
takeOff(sq00, oS)
fire("OnObjectAboutToBeRemoved", oS)
check(tileIds(java2, 0, 0, 0) == "c1,c9", "removing one piece keeps the others' records, linked or not")
check(java2:getObjectAt(0, 0, 0).data.pieces.c1.links.S == nil, "the partner's record forgets the link")
check(net2:recompute(net2:networkOf("D")) == nil, "the display is disconnected once the sensor is gone")

-- A record whose world object vanished is dropped when its chunk loads.
takeOff(sq11, oD)
fire("OnObjectAdded", oS) -- unrelated: sensor placed back on (0,0)
sq00.objects[#sq00.objects + 1] = oS
reg2:OnChunkLoaded(0, 0)
check(net2.pieces.D == nil, "a piece with no world object is dropped on chunk load")
check(java2:getObjectAt(1, 1, 0) == nil, "an emptied square loses its record")
check(java2:getObjectAt(1, 0, 0).data.pieces.c2.links.D == nil, "the cable's record forgets the vanished display")
check(net2.pieces.c1 and net2.pieces.c2, "the cable run is kept")

-- An unloaded square means unavailable, not destroyed.
loaded[key(1, 0, 0)] = nil
takeOff(sq10, oC2)
reg2:OnChunkLoaded(0, 0)
check(net2.pieces.c2 ~= nil, "a record on an unloaded square is kept")
loaded[key(1, 0, 0)] = true

-- A one-sided link in a damaged save is dropped and reported on load.
local damaged = save(java2)
for _, rec in ipairs(damaged) do
    if rec.data.pieces.c1 then rec.data.pieces.c1.links.c2 = nil end
end
testState.logged = {}
local reg3, java3 = start(damaged)
local reported = false
for _, line in ipairs(testState.logged) do
    if string.find(line, "one-sided", 1, true) then reported = true end
end
check(reported, "a one-sided link is reported on load")
check(java3:getObjectAt(1, 0, 0).data.pieces.c2.links.c1 == nil, "the dropped link is removed from the save")
check(reg3.network:networkOf("c1") ~= reg3.network:networkOf("c2"), "the dropped link does not connect")

-- Defined endpoints are saved through the same record path.
local defined, definedJava = start()
local sensorSquare, displaySquare = square(20, 20, 0), square(21, 20, 0)
local seed = { calibration = { threshold = 10 }, enabled = false }
local sensor = worldObject(sensorSquare, {
    id = "sensor", kind = "endpoint", definitionId = "ZedComm.PressureSensor", state = seed,
})
local cable = worldObject(sensorSquare, { id = "wire", kind = "cable" })
local display = worldObject(displaySquare, {
    id = "display", kind = "endpoint", definitionId = "ZedComm.NumericDisplay",
})
for _, object in ipairs({ sensor, cable, display }) do fire("OnObjectAdded", object) end
local function savedPiece(system, x, id)
    return system:getObjectAt(x, 20, 0).data.pieces[id]
end
local sensorRecord = savedPiece(definedJava, 20, "sensor")
local displayRecord = savedPiece(definedJava, 21, "display")
check(sensorRecord.definitionId == "ZedComm.PressureSensor" and sensorRecord.role == "source",
    "source definition supplies the saved identity and role")
check(displayRecord.definitionId == "ZedComm.NumericDisplay" and displayRecord.role == "sink",
    "receiver definition maps to the model sink role")
check(sensorRecord.ports.signal == false and displayRecord.ports.signal == false,
    "both endpoints start with the registered signal port")
seed.calibration.threshold = 99
check(defined.network:record("sensor").state.calibration.threshold == 10,
    "seed state is copied into the model")
local changed = { calibration = { threshold = 14 }, enabled = false, [1] = "armed" }
check(defined:setDeviceState("sensor", changed), "state update goes through the registry")
changed.calibration.threshold = 99
local exported = defined.network:record("sensor")
exported.state.calibration.threshold = 99
check(savedPiece(definedJava, 20, "sensor").state.calibration.threshold == 14
    and defined.network:record("sensor").state.calibration.threshold == 14,
    "saved state and returned records do not alias callers")
local cyclic = {}
cyclic.self = cyclic
check(not defined:setDeviceState("sensor", cyclic), "cyclic state is rejected")
check(not defined:setDeviceState("sensor", { callback = function() end }), "callback state is rejected")
check(not defined:setDeviceState("sensor", { value = math.huge }), "nonfinite state is rejected")
check(not defined:setDeviceState("sensor", { [true] = 1 }), "unsupported state keys are rejected")
check(savedPiece(definedJava, 20, "sensor").state.calibration.threshold == 14,
    "failed updates leave the saved state unchanged")
check(defined:link("wire", "sensor") and defined:link("wire", "display"),
    "old-format cable links to defined endpoints")
check(defined.network:setPacket("sensor", Packet.basic(90)), "defined source can publish a byte")

local definedSave = save(definedJava)
local loadedRegistry, loadedJava = start(definedSave)
for _, object in ipairs({ sensor, cable, display, sensor }) do fire("OnObjectAdded", object) end
local loadedRecord = savedPiece(loadedJava, 20, "sensor")
check(loadedRecord.definitionId == "ZedComm.PressureSensor"
    and loadedRecord.state.calibration.threshold == 14
    and loadedRecord.state.enabled == false and loadedRecord.state[1] == "armed",
    "identity and nested durable state round-trip and override old tag seed")
check(tileIds(loadedJava, 20, 20, 0) == "sensor,wire" and loadedJava:getObjectCount() == 2,
    "replayed object hooks do not duplicate pieces")
check(loadedRegistry.network:networkOf("sensor") == loadedRegistry.network:networkOf("display")
    and loadedRegistry.network:recompute(loadedRegistry.network:networkOf("display")) == nil,
    "cable links round-trip and packets await live sampling")

-- Simulate two definitions being absent during a load/save cycle.
for _, tile in ipairs(definedSave) do
    local pieces = tile.data.pieces
    if pieces.sensor then pieces.sensor.definitionId = "Example.Sensor" end
    if pieces.display then pieces.display.definitionId = "Example.Display" end
end
testState.logged = {}
local missing, missingJava = start(definedSave)
local missingId = missing.network:networkOf("sensor")
check(missingId == missing.network:networkOf("display"), "missing definitions keep saved topology")
check(missing.network:recompute(missingId) == nil, "missing sender cannot replay a stale byte")
check(#missing.network:sinksOf(missingId) == 0, "missing receiver is excluded from delivery")
check(not missing.network:setPacket("sensor", Packet.basic(100)), "missing sender rejects value updates")
local preserved = savedPiece(missingJava, 20, "sensor")
check(preserved.definitionId == "Example.Sensor" and preserved.state.calibration.threshold == 14
    and preserved.ports.signal == "wire" and preserved.definitionUnavailable == nil,
    "missing source record preserves state and links without a persistent unavailable flag")
local reports = 0
for _, line in ipairs(testState.logged) do
    if string.find(line, "record preserved", 1, true) then reports = reports + 1 end
end
check(reports == 2, "missing definitions are reported once each on load")
local missingSave = save(missingJava)
local definitions = ZedComm.DeviceDefinitions
check(definitions.register({
    id = "Example.Sensor", role = "source", ports = { "signal" },
    match = function() return false end, sample = function() return 90 end,
}), "restored sender definition registers")
check(definitions.register({
    id = "Example.Display", role = "receiver", ports = { "signal" },
    match = function() return false end, receiverModule = ZedComm.SignalModules.ON_OFF,
    bindFixture = function() return { apply = function() return "applied" end } end,
}), "restored receiver definition registers")
local recovered, recoveredJava = start(missingSave)
local recoveredId = recovered.network:networkOf("sensor")
check(recovered.network:recompute(recoveredId) == nil and recovered.network:sinksOf(recoveredId)[1] == "display",
    "reinstalling definitions restores the existing source and receiver links")
check(savedPiece(recoveredJava, 20, "sensor").state.calibration.threshold == 14,
    "reinstalling the definition recovers durable state")
check(recovered:setDeviceState("sensor", nil) and savedPiece(recoveredJava, 20, "sensor").state == nil,
    "explicit nil clears durable state")

testState.finish()
