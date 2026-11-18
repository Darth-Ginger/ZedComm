local testState = dofile("tests/support/placement_harness.lua")()
local check = testState.check
local square = testState.square
local save = testState.save
local start = testState.start
local loaded = testState.loaded
local placement = testState.placement
local runtime = testState.runtime
local inventory = testState.inventory
local carried = testState.carried
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local placedReading = testState.placedReading
local lay = testState.lay
local join = testState.join

local p0, w0, w1, d0 = floorTile(40, 40), floorTile(41, 40), floorTile(41, 41), floorTile(42, 41)
local far = floorTile(46, 40)

local otherPlate = give("ZedComm.PressurePlate")
local plate = give("ZedComm.PressurePlate")
plate.data.zedcommPlacement = { id = "test-pressure-id", state = { configured = 11 } }
local displayItem = give("ZedComm.NumericDisplay")
local wireA, wireB = give("ZedComm.SignalWire"), give("ZedComm.SignalWire")
local ok, plateId = runPlacement(p0, { kind = "place", item = plate })
check(ok and plateId == "test-pressure-id" and not inventory:contains(plate)
    and inventory:contains(otherPlate), "placement consumes the exact selected item and keeps its identity")
check(testState.registry.network:record(plateId).state.configured == 11, "placement restores carried configuration")
check(placement.resolve(testState.registry, plateId).object.sprite == "zedcomm_devices_01_20",
    "placed pressure plate uses its packaged sprite")
local placed, displayId = runPlacement(d0, { kind = "place", item = displayItem })
check(placed and placement.resolve(testState.registry, displayId).object.sprite == "zedcomm_devices_01_431",
    "placed display uses its packaged sprite")
check(not runPlacement(p0, { kind = "place", item = otherPlate }) and inventory:contains(otherPlate),
    "occupied endpoint tile rejects a second device without consuming it")
check(not runPlacement(far, { kind = "place", item = otherPlate }, p0) and #far.objects == 0,
    "out-of-reach placement leaves the tile unchanged")
check(not runPlacement(far, { kind = "lay", item = wireA, anchorId = plateId, anchorPort = "signal" })
    and inventory:contains(wireA), "wire cannot skip a tile")
p0.blocked = w0
check(not runPlacement(w0, { kind = "lay", item = wireA, anchorId = plateId, anchorPort = "signal" })
    and inventory:contains(wireA), "wire cannot cross a blocked edge")
p0.blocked = nil

local registryLink = testState.registry.link
testState.registry.link = function() return false, "injected link refusal" end
check(not lay(w0, wireA, plateId, "signal") and inventory:contains(wireA)
    and #w0.objects == 0 and testState.registry.network.pieces[plateId].ports.signal == false,
    "refused link rolls back the new tile and leaves inventory unchanged")
testState.registry.link = registryLink

local laid, firstWire = lay(w0, wireA, plateId, "signal")
check(laid and not inventory:contains(wireA) and testState.registry.network.pieces[plateId].ports.signal == firstWire,
    "first wire consumes one unit and explicitly connects to the plate")
local bent, secondWire = lay(w1, wireB, firstWire, false)
check(bent and not inventory:contains(wireB)
    and placement.resolve(testState.registry, secondWire).object.sprite == "zedcomm_devices_01_1",
    "bending the route consumes one more unit and uses the packaged wire sprite")
check(#placement.freePorts(placement.resolve(testState.registry, secondWire)) == 1,
    "a partial run leaves one selectable free end")
check(testState.registry.network.pieces[displayId].ports.signal == false,
    "a wire beside the display stays disconnected until explicitly joined")
check(join(d0, secondWire, false, displayId, "signal"), "finishing the run connects the destination")
check(placedReading(displayId) == 0, "player-built circuit carries valid zero")
p0.actors = { { class = "IsoPlayer" } }
check(placedReading(displayId) == 1, "player-built circuit carries the default of 1 when occupied")
for _, invalid in ipairs({ "", "oops", "-1", "0", "256", "7.5" }) do
    check(not runtime.setPressureOutput(testState.registry, plateId, invalid), "reject invalid occupied output " .. invalid)
end
check(placedReading(displayId) == 1, "invalid output leaves the occupied signal unchanged")
check(runtime.setPressureOutput(testState.registry, plateId, "255") and placedReading(displayId) == 255,
    "changing to the maximum updates the circuit while the plate is held")
p0.actors = {}
check(placedReading(displayId) == 0, "a configured plate still sends zero when empty")
p0.actors = { { class = "IsoPlayer" } }

inventory.full = true
check(not target(w0, firstWire, "pickup") and testState.registry.network.pieces[firstWire],
    "full inventory prevents pickup and leaves wiring intact")
inventory.full = false
w0.refuseRemoval = true
local beforePickup = #carried
check(not target(w0, firstWire, "pickup") and #carried == beforePickup
    and testState.registry.network.pieces[firstWire], "failed world removal rolls back the recovered item")
w0.refuseRemoval = false
check(target(w0, firstWire, "pickup"), "pickup recovers a wire unit")
local recoveredWire = carried[#carried]
check(recoveredWire:getFullType() == "ZedComm.SignalWire" and #w0.objects == 0
    and testState.registry.network.pieces[secondWire], "cut removes only the selected segment")
local value, _, connected = placedReading(displayId)
check(value == nil and connected, "cut leaves the display attached with no signal")
local repaired, replacement = lay(w0, recoveredWire, plateId, "signal")
check(repaired and join(w1, replacement, false, secondWire, false) and placedReading(displayId) == 255,
    "replacing the cut segment and joining the free ends repairs the run")

assert(testState.registry:setDeviceState(plateId, { label = "North plate" }))
check(runtime.setPressureOutput(testState.registry, plateId, "27")
    and testState.registry.network:record(plateId).state.label == "North plate",
    "setting the occupied output preserves other device state")
check(target(p0, plateId, "pickup"), "device pickup succeeds with a cable attached")
local recoveredPlate = carried[#carried]
check(recoveredPlate.data.zedcommPlacement.id == plateId
    and recoveredPlate.data.zedcommPlacement.state.occupiedOutput == 27
    and recoveredPlate.data.zedcommPlacement.links == nil
    and #placement.freePorts(placement.resolve(testState.registry, replacement)) == 1,
    "pickup retains identity and durable state but leaves the cable with a free end")
local replaced, idAgain = runPlacement(p0, { kind = "place", item = recoveredPlate })
check(replaced and idAgain == plateId and testState.registry.network:record(idAgain).state.occupiedOutput == 27
    and testState.registry.network.pieces[idAgain].ports.signal == false,
    "replacing restores the same configured device with a disconnected port")
check(join(p0, replacement, false, plateId, "signal") and placedReading(displayId) == 27,
    "device can reconnect to the original wire after replacement")

local worldSave = save(testState.java)
local previousNetwork = testState.registry.network
testState.registry, testState.java = start(worldSave)
check(testState.registry.network:record(plateId).state.occupiedOutput == 27 and placedReading(displayId) == 27,
    "player-built rig and state survive reload")
check(not placement.perform(player, { kind = "place", network = previousNetwork, square = far, item = otherPlate })
    and inventory:contains(otherPlate), "queued action cannot mutate a different loaded registry")

testState.finish()
