local testState = dofile("tests/support/cursor_harness.lua")()
if not testState.GAME then
    print = testState.realPrint
    print("SKIP tests/placement_cursor_test.lua: requires PZ_LUA cursor classes")
    return
end
local check = testState.check
local fire = testState.fire
local placement = testState.placement
local inventory = testState.inventory
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local lay = testState.lay
local join = testState.join
local menu = testState.menu
local optionsAt = testState.optionsAt
local click = testState.click
local arrive = testState.arrive
local finishWalk = testState.finishWalk

local origin, east, corner = floorTile(55, 50), floorTile(56, 50), floorTile(56, 51)
local endTile, distant = floorTile(57, 51), floorTile(58, 51)
local cancelTile = floorTile(56, 52)
local ok, sourceId = runPlacement(origin, { kind = "place", item = give("ZedComm.PressurePlate") })
assert(ok, sourceId)
local placed, displayId = runPlacement(endTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
assert(placed, displayId)
local old = IsoObject.new(east, "zedcomm_devices_01_1")
old:getModData().zedcomm = { id = "cursor-existing-wire", kind = "cable", placedItem = "ZedComm.SignalWire" }
east:AddTileObject(old)
fire("OnObjectAdded", old)
for _ = 1, 3 do give("ZedComm.SignalWire") end

local floorColor = { getR = function() return 0 end, getG = function() return 1 end,
    getB = function() return 0 end }

assert(optionsAt(origin)["Select pressure plate free end"])()
testState.cursor = assert(getCell():getDrag(0))
click(distant)
check(testState.preview[1] == 58 and testState.preview[2] == 51 and not testState.cursor.canBeBuild
    and testState.registry.network.pieces[sourceId].ports.signal == false,
    "the native cursor previews a remote tile as unavailable")
click(east)
check(testState.choice and testState.choice.options["Connect to wire 1 / Loose wire"] and testState.choice.options["Lay wire here"],
    "an active endpoint end can join a compatible cable or lay a new one")
testState.choice.options["Lay wire here"]()
local priorAction, walking = testState.queued, testState.queuedWalk
click(east)
check(priorAction == testState.queued and walking == testState.queuedWalk and walking.location == east
    and arrive():isValid() and testState.queued:complete(), "one click queues one native walk followed by one linked wire")
local first = testState.registry.network.pieces[sourceId].ports.signal
check(first ~= "cursor-existing-wire" and testState.registry.network:networkOf(first)
    ~= testState.registry.network:networkOf("cursor-existing-wire"), "clicking a shared tile lays a separate linked wire")

player.tile = east
click(corner)
local cleared = testState.queuedWalk
testState.queued, testState.queuedWalk = nil, nil
click(corner)
check(testState.queuedWalk and testState.queuedWalk ~= cleared and arrive():isValid() and testState.queued:complete(),
    "clearing the native action queue allows the next click to retry")
local second
for id, port in pairs(testState.registry.network.pieces[first].links) do
    if port == true then second = id end
end
check(second ~= nil and getCell():getDrag(0) == testState.cursor, "placing a bend advances the anchor and keeps the cursor")

player.tile = corner
click(cancelTile)
local cancelled, cancelledWalk = testState.queued, testState.queuedWalk
local connect = optionsAt(endTile)["Connect wire to numeric display"]
finishWalk()
check(getCell():getDrag(0) == nil and cancelledWalk.additionalTest()
    and testState.queued == cancelled and connect ~= nil,
    "right-click cancels the walk without queuing placement and keeps the end available to join")
connect()
check(testState.queued:isValid() and testState.queued:complete()
    and testState.registry.network.pieces[displayId].ports.signal == second, "the explicit join uses the last placed wire")

assert(testState.registry:unlink(second, displayId))
assert(optionsAt(corner)["Select wire free end"])()
testState.cursor = assert(getCell():getDrag(0))
click(cancelTile)
local abandoned = testState.queuedWalk
testState.queuedWalk = nil
player.tile = distant
fire("OnTick")
check(getCell():getDrag(0) == nil and abandoned.additionalTest(),
    "walking out of reach cancels the cursor and its uncommitted placement")

local function openInventory(item)
    local context = menu()
    fire("OnFillInventoryObjectContextMenu", 0, context, { item })
    assert(context.options["Place with ZedComm cursor"])()
    testState.cursor = assert(getCell():getDrag(0))
    testState.queued, testState.queuedWalk, testState.choice = nil, nil, nil
end

local remote = floorTile(64, 52)
local plateItem = give("ZedComm.PressurePlate")
local otherPlate = give("ZedComm.PressurePlate")
openInventory(plateItem)
click(remote)
check(testState.queuedWalk and testState.queuedWalk.location == remote and not testState.queued,
    "inventory endpoint queues a walk to the clicked floor before placement")
check(arrive():isValid() and testState.queued:complete() and not inventory:contains(plateItem)
    and inventory:contains(otherPlate) and getCell():getDrag(0) == nil,
    "arrival places exactly the selected endpoint and closes its cursor")
local plateOnRemote = placement.piecesAt(testState.registry, remote)[1]
assert(plateOnRemote and plateOnRemote.piece.definitionId == "ZedComm.PressureSensor")

openInventory(otherPlate)
click(remote)
check(not testState.queued and not testState.queuedWalk and inventory:contains(otherPlate), "the cursor rejects a second endpoint on a tile")
local secondDeviceTile = floorTile(64, 53)
click(secondDeviceTile)
getCell():setDrag(nil, 0)
local cancelledPlacement = testState.queuedWalk
finishWalk()
check(cancelledPlacement.additionalTest() and not testState.queued and inventory:contains(otherPlate),
    "cancelled inventory placement retains the exact item")

openInventory(otherPlate)
click(secondDeviceTile)
local removedItem = testState.queuedWalk
inventory:Remove(otherPlate)
arrive()
check(removedItem and not testState.queued and #secondDeviceTile.objects == 0,
    "arrival revalidates the exact inventory item before queuing placement")

local looseTile = floorTile(65, 52)
local looseItem = give("ZedComm.SignalWire")
openInventory(looseItem)
player.tile = origin
click(looseTile)
check(testState.queuedWalk and testState.queuedWalk.location == looseTile and arrive():complete()
    and not inventory:contains(looseItem) and getCell():getDrag(0) == nil,
    "loose wire walks to and places on a remote clear tile")
local loose = placement.piecesAt(testState.registry, looseTile)[1]
check(loose and #testState.registry.network:partners(loose.id) == 0,
    "loose placement does not join an adjacent free device")

local pickedWire = give("ZedComm.SignalWire")
openInventory(pickedWire)
click(remote)
check(testState.choice and testState.choice.options["Place wire loose"] and testState.choice.options["Connect to pressure plate"]
    and not testState.queued and not testState.queuedWalk, "clicking a device free end offers both explicit choices")
testState.choice.options["Connect to pressure plate"]()
check(arrive():complete() and plateOnRemote.piece.ports.signal
    and not inventory:contains(pickedWire) and getCell():getDrag(0) == testState.cursor,
    "place and connect uses the selected item and starts a linked run")

local extraWire = give("ZedComm.SignalWire")
openInventory(extraWire)
click(looseTile)
check(testState.choice and testState.choice.options["Place wire loose"] and testState.choice.options["Connect to wire 1 / Loose wire from an adjacent tile"],
    "clicking an existing cable offers loose placement and an adjacent extension")
testState.choice.options["Place wire loose"]()
assert(arrive():complete())
local shared = placement.piecesAt(testState.registry, looseTile)
table.sort(shared, function(a, b) return a.id < b.id end)
check(#shared == 2 and testState.registry.network:networkOf(shared[1].id)
    ~= testState.registry.network:networkOf(shared[2].id), "choosing loose on an occupied tile keeps both runs independent")

local linkedItem = give("ZedComm.SignalWire")
local extensionTile = floorTile(66, 52)
local invalidExtension = floorTile(67, 52)
player.tile = origin
openInventory(linkedItem)
click(looseTile)
assert(testState.choice.options["Connect to wire 2 / Loose wire from an adjacent tile"])()
click(invalidExtension)
check(not testState.queued and not testState.queuedWalk and inventory:contains(linkedItem),
    "choosing a free cable end refuses a target beyond the neighboring tile")
click(extensionTile)
local walk = testState.queuedWalk
fire("OnTick")
check(walk and walk.location == extensionTile and getCell():getDrag(0) == testState.cursor,
    "a native walk to a valid extension can approach a selected cable from far away")
assert(arrive():complete())
local extension = placement.piecesAt(testState.registry, extensionTile)[1]
check(extension and extension.piece.links[shared[2].id] == true
    and not extension.piece.links[shared[1].id] and not inventory:contains(linkedItem),
    "the first placed wire attaches only to the chosen cable on a shared tile")
getCell():setDrag(nil, 0)

testState.finish()
