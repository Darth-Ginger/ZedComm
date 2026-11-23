local test = dofile("tests/support/menu_harness.lua")()
local placement, check = test.placement, test.check
local near, far = test.floorTile(49, 50), test.floorTile(50, 50)
local wall = IsoObject.new(far, "test_wall")
function wall:transmitModData() end
far:AddTileObject(wall)
near.blocked, far.blocked = far, near
far.westWall = wall
test.give("Base.HandDrill")
test.give("Base.Screwdriver")
local scrap = test.give("Base.ScrapMetal")

local function finish(tile, group, option)
    local invoke = test.optionsAt(tile, group)[option]
    assert(invoke, option)
    test.queued = nil
    invoke()
    return test.queued and test.queued:isValid() and test.queued:complete()
end

local function wireAt(tile)
    local ok, id = test.runPlacement(tile, { kind = "place", item = test.give("ZedComm.SignalWire") })
    assert(ok, id)
    return id
end

local function connect(anchor, remote, item)
    local entry = remote and placement.resolve(test.registry, remote)
    return test.runPlacement(near, { kind = "connect-through-wall", side = "east", wall = wall, anchorId = anchor,
        targetId = remote, remoteWire = entry and entry.object, item = item })
end

local first, second = wireAt(near), wireAt(far)
check(not test.join(far, first, false, second, false) and not connect(first, second),
    "solid wall blocks both ordinary joins and uninstalled passthroughs")
far.doorOrWindow = true
check(#placement.wallPassthroughs(near) == 0, "a blocked door or window does not qualify")
far.doorOrWindow = nil
local approach, start = test.floorTile(48, 50), test.floorTile(47, 50)
function approach:canStand() return true end
function far:canStand() return true end
function test.player:getVehicle() return nil end
function getGameSpeed() return 1 end
ISPathFindAction = {
    pathToNearest = function(_, _, locations)
        return {
            location = approach, locations = locations,
            setOnComplete = function(self, callback) self.arrive = callback end,
        }
    end,
}
local drill = test.optionsAt(near, "East wall passthrough")["Drill passthrough"]
test.player.tile = start
drill()
local walking = test.queuedWalk
check(walking and walking:isValid() and #walking.locations == 3 and walking.locations[1] == 48.5,
    "distant wall work walks to reachable floor on the selected side")
test.player.tile, test.queuedWalk = approach, nil
walking.arrive()
check(test.queued and test.queued:complete() and wall:getModData().zedcommWallPassthrough.west == "bare",
    "arriving at the wall drills the fitting")
check(finish(far, "West wall passthrough (bare, 0/5)", "Fit metal cover")
    and not test.inventory:contains(scrap), "the opposite face can fit a cover using one scrap")
check(not placement.canReach(test.player, near) and far:isBlockedTo(near),
    "the covered fitting preserves ordinary reach and wall collision")

test.optionsAt(near)["Select wire free end"]()
check(finish(near, "East wall passthrough (metal, 0/5)", "Connect to wire 1"),
    "the selected local wire can join an existing wire through the wall menu")

local fed = wireAt(near)
local item = test.give("ZedComm.SignalWire")
local cursor = { character = test.player, player = 0, clearCache = function() end }
local actions = ZedComm.NativePlacementActions
actions.openWire = function() return cursor end
test.optionsAt(near, "Wire 2 of 2")["Select free end"]()
test.queued = nil
local choice = test.menu()
ISContextMenu.get = function() return choice end
function getMouseX() return 0 end
function getMouseY() return 0 end
check(actions.canPlace(cursor, item, far), "native Place recognizes the passthrough on the far tile")
actions.place(cursor, item, far)
assert(choice.options["Feed wire through"])()
check(test.queued and test.queued:complete() and not test.inventory:contains(item) and test.player.tile == near,
    "native Place feeds a far-side segment while the survivor stays on their side")

local network = test.registry.network
local runs = {}
for i = 3, 5 do
    local a, b = wireAt(near), wireAt(far)
    assert(connect(a, b))
    runs[i] = { a, b }
end
local sixth, sixthRemote = wireAt(near), wireAt(far)
check(placement.wallCrossings(test.registry, near, far) == 5 and not connect(sixth, sixthRemote),
    "the wall edge accepts five independent runs and refuses a sixth")
local seen = {}
for _, entry in ipairs(placement.piecesAt(test.registry, near)) do
    local id = network:networkOf(entry.id)
    check(not seen[id], "each shared-tile wire retains a separate run")
    seen[id] = true
end
local sprites, seamSprites = ZedComm.WireShape.layout(network), {}
for _, entry in ipairs(placement.piecesAt(test.registry, near)) do
    if #network:partners(entry.id) > 0 then seamSprites[sprites[entry.id]] = true end
end
local lanes = 0
for _ in pairs(seamSprites) do lanes = lanes + 1 end
check(lanes == 5, "the five crossings use distinct wire lanes")
check(network:networkOf(first) == network:networkOf(second) and network:networkOf(fed) ~= network:networkOf(first),
    "two different menu routes produce intact, separate runs")
check(not test.runPlacement(near, { kind = "change-wall-passthrough", side = "east", wall = wall, expected = "metal" }),
    "sealing refuses a wired passage")

local savedMarker = wall:getModData().zedcommWallPassthrough.west
local save = test.save(test.java)
far:transmitRemoveItemFromSquare(wall)
wall = IsoObject.new(far, "test_wall")
function wall:transmitModData() end
wall:getModData().zedcommWallPassthrough = { west = savedMarker }
far:AddTileObject(wall)
far.westWall = wall
test.registry, test.java = test.start(save)
network = test.registry.network
check(placement.wallPassthroughs(far)[1].cover == "metal"
    and placement.wallCrossings(test.registry, near, far) == 5, "reload restores the wall fitting and all five links")
check(test.target(near, runs[3][1], "pickup") and placement.wallCrossings(test.registry, near, far) == 4
    and network:networkOf(runs[4][1]) == network:networkOf(runs[4][2]),
    "picking up one wire frees only its crossing")
check(connect(sixth, sixthRemote), "the freed slot can take another run")

far:transmitRemoveItemFromSquare(wall)
near.blocked, far.blocked, far.westWall = nil, nil, nil
check(#placement.wallPassthroughs(near) == 0 and network:networkOf(first) == network:networkOf(second),
    "removing a wall removes the fitting and leaves now-unobstructed wires connected")
local north = test.floorTile(50, 49)
local northWall = IsoObject.new(far, "test_north_wall")
function northWall:transmitModData() end
far:AddTileObject(northWall)
far.blocked, north.blocked, far.northWall = north, far, northWall
test.give("Base.PlasticTray")
check(finish(far, "North wall passthrough", "Drill passthrough")
    and finish(north, "South wall passthrough (bare, 0/5)", "Fit plastic cover"),
    "the north and south faces share the same plastic-covered fitting")
check(finish(north, "South wall passthrough (plastic, 0/5)", "Seal passthrough")
    and northWall:getModData().zedcommWallPassthrough == nil and north:isBlockedTo(far),
    "sealing an empty fitting leaves the wall solid")
test.finish()
