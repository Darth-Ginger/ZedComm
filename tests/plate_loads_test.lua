local testState = dofile("tests/support/menu_harness.lua")()
local LUA = testState.LUA
local check = testState.check
local square = testState.square
local takeOff = testState.takeOff
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
local optionsAt = testState.optionsAt
local floorFixture = testState.floorFixture
local droppedItem = testState.droppedItem
local spriteOf = testState.spriteOf

dofile(testState.LUA .. "client/ZedComm/WireVisuals.lua")

-- The basic plate treats floor furniture and vehicle footprint as presence.
do
    testState.registry, testState.java = start()
    local plateTile, displayTile, neighbor = floorTile(105, 125), floorTile(106, 125), floorTile(105, 126)
    local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(placed, plateId)
    local displayPlaced, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(displayPlaced, displayId)
    local laid, wireId = lay(plateTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))
    assert(runtime.setPressureOutput(testState.registry, plateId, 155))

    floorFixture(plateTile, { solidfloor = true }, false)
    floorFixture(plateTile, { solid = true }, false)
    floorFixture(plateTile, {}, false)
    floorFixture(plateTile, { IsMoveAble = true, solid = true, MoveType = "WallObject" }, true)
    floorFixture(plateTile, { IsMoveAble = true, IsTableTop = true }, true)
    floorFixture(plateTile, { IsMoveAble = true }, true, 12)
    floorFixture(plateTile, { IsMoveAble = true, solid = true }, true, 0, "IsoWorldInventoryObject")
    floorFixture(neighbor, { IsMoveAble = true, solidtrans = true }, true)
    neighbor.overlappingVehicle = {}
    check(placedReading(displayId) == 0,
        "floor, decorative and elevated or wall props, and neighboring loads leave the basic plate clear")
    neighbor.looseItems = { droppedItem(5) }
    check(placedReading(displayId) == 0, "an item on a neighboring square leaves the basic plate clear")
    plateTile.looseItems = { droppedItem(0.1) }
    check(placedReading(displayId) == 155, "a single light floor item holds the configured presence byte")
    plateTile.looseItems = {}
    plateTile.staticActors = { { class = "IsoDeadBody" } }
    check(placedReading(displayId) == 155, "a corpse alone holds the basic plate")
    plateTile.staticActors, plateTile.actors = {}, { { class = "IsoAnimal" } }
    check(placedReading(displayId) == 155, "a live animal alone holds the basic plate")
    plateTile.actors = {}

    local crate = floorFixture(plateTile, {}, true)
    check(placedReading(displayId) == 155, "a floor container holds the configured byte above the same-tile cable")
    testState.registry, testState.java = start(save(testState.java))
    check(placedReading(displayId) == 155, "a loaded crate still drives the saved circuit after reload")
    local table = floorFixture(plateTile, { IsMoveAble = true, solidtrans = true }, false)
    takeOff(plateTile, crate)
    check(placedReading(displayId) == 155, "solid moveable furniture alone holds the same configured byte")
    plateTile.overlappingVehicle = neighbor.overlappingVehicle
    takeOff(plateTile, table)
    check(placedReading(displayId) == 155, "an overlapping vehicle alone holds the same configured byte")
    plateTile.overlappingVehicle = nil
    check(placedReading(displayId) == 0, "removing the last load clears the signal")
end

-- Occupancy stays a count from placement through signal delivery and reload.
do
    testState.registry, testState.java = start()
    local plateTile, wireTile, displayTile = floorTile(110, 125), floorTile(111, 125), floorTile(112, 125)
    local function placeDevice(tile, itemType)
        local ok, id = runPlacement(tile, { kind = "place", item = give(itemType) })
        assert(ok, id)
        return id
    end
    local plateId = placeDevice(plateTile, "ZedComm.OccupancyPlate")
    local displayId = placeDevice(displayTile, "ZedComm.NumericDisplay")
    local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))
    check(placedReading(displayId) == 0 and spriteOf(plateId) == "zedcomm_devices_01_421",
        "the wired occupancy plate reports zero and the lead faces the connected wire")

    local playerActor, zombie = { class = "IsoPlayer" }, { class = "IsoZombie" }
    local animal, vehicle = { class = "IsoAnimal" }, { class = "BaseVehicle" }
    local states = {
        { { playerActor }, 1 },
        { { playerActor, zombie, animal, vehicle }, 2 },
        { { zombie, animal }, 1 },
        { { animal, vehicle }, 0 },
    }
    for _, state in ipairs(states) do
        plateTile.actors = state[1]
        check(placedReading(displayId) == state[2], "occupancy display follows actor count " .. state[2])
    end
    plateTile.actors = {}
    for i = 1, 260 do plateTile.actors[i] = zombie end
    check(placedReading(displayId) == 255, "the sampled actor count saturates at 255")
    check(not runtime.setPressureOutput(testState.registry, plateId, "155")
        and not optionsAt(plateTile)["Set pressure plate output (1)"],
        "the basic plate's fixed-output control is unavailable on a counting plate")

    plateTile.actors = { playerActor, zombie }
    testState.registry, testState.java = start(save(testState.java))
    check(placedReading(displayId) == 2 and spriteOf(plateId) == "zedcomm_devices_01_421",
        "reload restores the occupancy endpoint, link and lead, then samples the actors")
    assert(target(plateTile, plateId, "pickup"))
    local recovered = carried[#carried]
    local reading, _, attached = placedReading(displayId)
    check(recovered:getFullType() == "ZedComm.OccupancyPlate" and attached and reading == nil,
        "pickup returns the counting plate and leaves the attached display with no signal")
    local restored, sameId = runPlacement(plateTile, { kind = "place", item = recovered })
    check(restored and sameId == plateId and join(plateTile, wireId, false, plateId, "signal")
        and placedReading(displayId) == 2, "replacing and reconnecting resumes the live count")
end

-- A weight source distinguishes on-foot occupants and a vehicle on the same circuit.
do
    testState.registry, testState.java = start()
    local plateTile, wireTile, displayTile = floorTile(120, 125), floorTile(121, 125), floorTile(122, 125)
    local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(placed, plateId)
    local displayPlaced, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(displayPlaced, displayId)
    local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))

    local vehicle = { class = "BaseVehicle", getMass = function() return 1200 end }
    local pedestrian = { class = "IsoPlayer" }
    function pedestrian:getVehicle() return self.vehicle end
    function pedestrian:getNutrition() return { getWeight = function() return 80 end } end
    local zombie, animal = { class = "IsoZombie" }, { class = "IsoAnimal" }
    function animal:getVehicle() return nil end
    function animal:getData() return { getWeight = function() return 45 end } end
    check(placedReading(displayId) == 0 and spriteOf(plateId) == "zedcomm_devices_01_427",
        "the weight plate sends zero empty and aims its lead at the linked tile")

    plateTile.actors = { pedestrian, animal }
    check(placedReading(displayId) == 13, "weight plate combines on-foot player and animal mass")
    plateTile.actors = { pedestrian, zombie }
    check(placedReading(displayId) == 16, "weight plate adds the zombie estimate before quantizing")
    plateTile.actors = {}
    floorFixture(wireTile, { IsMoveAble = true, PickUpWeight = "200" }, true)
    local unweighed = floorFixture(plateTile, { IsMoveAble = true }, true)
    local wallShelf = floorFixture(plateTile, { IsMoveAble = true, PickUpWeight = "200", MoveType = "WallObject" }, true)
    wallShelf.containers[1].weight = 20
    check(placedReading(displayId) == 0, "weight ignores furniture and contents off the plate's floor")
    unweighed.containers[1].weight = 20
    check(placedReading(displayId) == 2, "known contents contribute when the furniture has no pickup weight")
    takeOff(plateTile, unweighed)

    local crate = floorFixture(plateTile, { IsMoveAble = true, PickUpWeight = "75" }, true)
    check(placedReading(displayId) == 1, "the crate's pickup weight produces a nonzero reading")
    crate.containers[1].weight = 12
    crate.containers[2] = { getContentsWeight = function() return 8 end }
    check(placedReading(displayId) == 3, "weight plate adds the empty crate and both compartments before rounding")
    crate.containers[1].weight = 0
    crate.containers[2] = nil
    check(placedReading(displayId) == 1, "emptying the crate restores the fixture-only reading")
    plateTile.actors = { pedestrian }
    check(placedReading(displayId) == 9, "furniture and actor weight combine before rounding")
    plateTile.actors = {}
    takeOff(plateTile, crate)
    local shelf = floorFixture(plateTile, { IsMoveAble = true, solidtrans = true, PickUpWeight = "200" }, false)
    check(placedReading(displayId) == 2, "solid floor furniture can contribute weight without a container")
    takeOff(plateTile, shelf)
    local lightProp = floorFixture(plateTile, { IsMoveAble = true, PickUpWeight = "45" }, false)
    check(placedReading(displayId) == 1, "a lightweight nonblocking floor prop contributes its weight")
    takeOff(plateTile, lightProp)
    local bag = droppedItem(40) -- engine unequipped weight includes the bag and its contents
    plateTile.looseItems = { droppedItem(20), bag }
    check(placedReading(displayId) == 6, "stacked floor items add their weights including a loaded bag")
    plateTile.actors = { pedestrian }
    check(placedReading(displayId) == 14, "loose items and actor weight sum before rounding")
    plateTile.actors = {}
    local loadedCrate = floorFixture(plateTile, { PickUpWeight = "75" }, true)
    loadedCrate.containers[1].weight = 10
    check(placedReading(displayId) == 8, "loose items also add to furniture and its contents")
    takeOff(plateTile, loadedCrate)
    plateTile.looseItems = { bag }
    check(placedReading(displayId) == 4, "picking up part of the pile reduces the sampled weight")
    plateTile.looseItems = {}
    local body = { class = "IsoDeadBody", getWeight = function() return 0 end,
        isAnimal = function() return false end, getInventoryWeight = function() return 5 end }
    plateTile.staticActors = { body }
    check(placedReading(displayId) == 8, "a stationary corpse adds its estimated body mass plus inventory")
    plateTile.staticActors = {}
    wireTile.overlappingVehicle = vehicle
    check(placedReading(displayId) == 0, "an overlapping vehicle on an adjacent tile leaves the plate clear")
    plateTile.overlappingVehicle = vehicle
    check(placedReading(displayId) == 120, "a parked vehicle holds a distinct nonzero reading without occupants")
    plateTile.actors = { pedestrian }
    pedestrian.vehicle = vehicle
    check(placedReading(displayId) == 120, "the player inside the car contributes no separate mass")
    pedestrian.vehicle = nil
    check(placedReading(displayId) == 128, "an on-foot actor adds to a vehicle's contribution")
    plateTile.actors = {}

    testState.registry, testState.java = start(save(testState.java))
    check(placedReading(displayId) == 120 and spriteOf(plateId) == "zedcomm_devices_01_427",
        "reload preserves the links and resamples the parked vehicle")
    plateTile.overlappingVehicle = nil
    check(placedReading(displayId) == 0, "the signal clears when the vehicle leaves")
    assert(target(plateTile, plateId, "pickup"))
    local recovered = carried[#carried]
    local value, _, attached = placedReading(displayId)
    check(recovered:getFullType() == "ZedComm.WeightPlate" and attached and value == nil,
        "pickup leaves an attached display without a source")
    local restored, idAgain = runPlacement(plateTile, { kind = "place", item = recovered })
    plateTile.actors = { zombie }
    check(restored and idAgain == plateId and join(plateTile, wireId, false, plateId, "signal")
        and placedReading(displayId) == 8, "replacement and reconnect resume estimated weight")
end

testState.finish()
