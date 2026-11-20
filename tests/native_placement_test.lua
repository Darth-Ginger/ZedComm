local testState = dofile("tests/support/cursor_harness.lua")()
if not testState.GAME then
    print = testState.realPrint
    print("SKIP tests/native_placement_test.lua: requires PZ_LUA cursor classes")
    return
end
local LUA = testState.LUA
local PZ = testState.PZ
local check = testState.check
local fire = testState.fire
local start = testState.start
local placement = testState.placement
local inventory = testState.inventory
local carried = testState.carried
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local lay = testState.lay
local join = testState.join
local click = testState.click
local arrive = testState.arrive
local key = testState.key

for _ = 1, 3 do give("ZedComm.SignalWire") end

dofile(LUA .. "client/ZedComm/NativePlacement.lua")
local originalText, originalRadial, originalKeybind = getText, getPlayerRadialMenu, KeybindId
local originalFlagType = IsoFlagType
IsoFlagType = { WindowN = "WindowN" }
getText = function(key) return key end
getPlayerRadialMenu = function() return nil end
KeybindId = { ROTATE_BUILDING = 1 }
local gameCore = getCore
getCore = function()
    local core = gameCore()
    core.isKey = function() return false end
    return core
end
player.getPrimaryHandItem = function() return nil end
player.getSecondaryHandItem = function() return nil end
player.getCharacterActions = function() return { isEmpty = function() return true end } end
player.isSittingOnFurniture = function() return false end
player.faceLocation = function() end
inventory.getItemById = function(_, id)
    for _, item in ipairs(carried) do if item:getID() == id then return item end end
end

local itemId = 0
local function addId(item)
    if item.getID then return end
    itemId = itemId + 1
    local id = itemId
    function item.getID() return id end
end
local realAddItem = inventory.AddItem
inventory.AddItem = function(self, item)
    addId(item)
    return realAddItem(self, item)
end
for _, item in ipairs(carried) do addId(item) end

local spriteProperties = { has = function() return false end }
ISMoveableSpriteProps = {
    invalidColor = { r = 1, g = 0, b = 0 },
    new = function(sprite)
        return {
            sprite = sprite, spriteProps = spriteProperties,
            spriteName = type(sprite) == "string" and sprite or sprite:getName(),
            isMoveable = sprite == "vanilla-furniture",
            hasFaces = function() return false end,
            getYOffsetCursor = function() return 0 end,
            canPlaceMoveable = function() return true end,
        }
    end,
    addLineToInfoTable = function(lines, name)
        lines[#lines + 1] = name
        return lines
    end,
}
dofile(PZ .. "/server/BuildingObjects/ISMoveableCursor.lua")
local vanillaClicks = 0
ISMoveableCursor.tryBuild = function() vanillaClicks = vanillaClicks + 1 end
local gameRender = ISMoveableCursor.render
ISMoveableCursor.render = function() end
ISMoveableCursor.setMoveableMode = function(self, mode) ISMoveableCursor.mode[self.player] = mode end
fire("OnGameStart")
fire("OnGameStart")

local vanilla = give("Base.TestMoveable")
vanilla.class = "Moveable"
function vanilla.getWorldSprite() return "vanilla-furniture" end

local native = setmetatable({ player = 0, character = player, objectIndex = 1 }, ISMoveableCursor)
ISMoveableCursor.__index = ISMoveableCursor
native:init()
native.setInfoPanel = function() end
native.rotateMouse = function() end
native:setMoveableMode("place")
getCell():setDrag(native, 0)
testState.cursor = native

local function selectNative(tile, matches)
    for _ = 1, 25 do
        native:isValid(tile)
        local entry = native.objectListCache[native.objectIndex]
        if entry and matches(entry) then return entry end
        native:rotateKey(0, true)
    end
    error("Native cycle did not offer the expected item")
end
local function selectType(tile, fullType)
    return selectNative(tile, function(entry) return entry.object:getFullType() == fullType end)
end
local nativePlateTile, nativeDisplayTile = floorTile(60, 53), floorTile(61, 55)
local relocatedPlateTile, nextWireTile = floorTile(60, 54), floorTile(60, 55)
local clearWireTile, skippedWireTile = floorTile(58, 54), floorTile(58, 56)
player.tile = origin
give("ZedComm.PressurePlate")
give("ZedComm.NumericDisplay")
for _ = 1, 4 do give("ZedComm.SignalWire") end
local cabinetItem = give("ZedComm.SmallCabinet")
local indexes = {}
for i, entry in ipairs(native:getInventoryObjectList()) do
    indexes[entry.object:getFullType()] = i
end
check(indexes["Base.TestMoveable"] < indexes["ZedComm.PressurePlate"]
    and indexes["ZedComm.PressurePlate"] < indexes["ZedComm.NumericDisplay"]
    and indexes["ZedComm.NumericDisplay"] < indexes["ZedComm.SmallCabinet"]
    and indexes["ZedComm.SmallCabinet"] < indexes["ZedComm.SignalWire"],
    "native placement keeps vanilla entries and groups ZedComm candidates by item tag")
inventory:Remove(cabinetItem)

check(selectType(nativePlateTile, "Base.TestMoveable").object == vanilla and native.canCreate,
    "native cycling retains vanilla Moveables")
native:tryBuild(nativePlateTile:getX(), nativePlateTile:getY(), 0)
check(vanillaClicks == 1, "unrelated Moveables delegate to vanilla placement")

local plateCandidate = selectType(nativePlateTile, "ZedComm.PressurePlate")
click(nativePlateTile)
check(native.objectSprite and native.objectSprite:getName() == "zedcomm_devices_01_20"
    and testState.queuedWalk and testState.queuedWalk.location == nativePlateTile and arrive():complete()
    and not inventory:contains(plateCandidate.object) and getCell():getDrag(0) == native,
    "native Place previews and places the selected pressure plate without leaving the tool")
local nativePlate = placement.piecesAt(testState.registry, nativePlateTile)[1]
assert(testState.registry:setDeviceState(nativePlate.id, { label = "native test" }))

local displayCandidate = selectType(nativeDisplayTile, "ZedComm.NumericDisplay")
click(nativeDisplayTile)
check(arrive():complete() and not inventory:contains(displayCandidate.object)
    and getCell():getDrag(0) == native, "the same native tool cycles to and places the display")
local nativeDisplay = placement.piecesAt(testState.registry, nativeDisplayTile)[1]

local switchTile = floorTile(63, 55)
switchTile.northWall, switchTile.westWall = {}, {}
local switchItem = give("ZedComm.NetworkSwitch")
selectType(switchTile, "ZedComm.NetworkSwitch")
local oldMouseX, oldMouseY, oldSound = screenToIsoX, screenToIsoY, getSoundManager
screenToIsoX = function() return 62.5 end
screenToIsoY = function() return 55.5 end
getSoundManager = function() return { playUISound = function() end } end
ISMoveableCursor.rotateMouse(native, 62, 55)
native:isValid(switchTile)
check(native.objectSprite:getName() == "zedcomm_devices_01_469",
    "native mouse drag faces the switch toward the selected corner wall")
screenToIsoX = function() return 64.5 end
ISMoveableCursor.rotateMouse(native, 64, 55)
native:isValid(switchTile)
check(native.objectSprite:getName() == "zedcomm_devices_01_469",
    "dragging toward an open edge keeps the selected wall")
screenToIsoX, screenToIsoY, getSoundManager = oldMouseX, oldMouseY, oldSound
click(switchTile)
check(arrive():complete() and not inventory:contains(switchItem)
    and placement.piecesAt(testState.registry, switchTile)[1].piece.state.mount == "west",
    "the vanilla moveable cursor commits the wall chosen by mouse drag")

local laid, previousWire = lay(nativePlateTile, give("ZedComm.SignalWire"), nativePlate.id, "signal")
assert(laid, previousWire)
native:setMoveableMode("pickup")
native:clearCache()
local selectedPlate = selectNative(nativePlateTile, function(entry)
    return entry.zedcommPickup and entry.zedcommPickup.id == nativePlate.id
end)
click(nativePlateTile)
check(selectedPlate.object == nativePlate.object and arrive():complete()
    and not testState.registry.network.pieces[nativePlate.id] and testState.registry.network.pieces[previousWire],
    "native pickup uses the exact registered endpoint and leaves its connected wire")
local recovered = carried[#carried]
check(recovered:getModData().zedcommPlacement.state.label == "native test",
    "native pickup preserves endpoint identity and settings on the returned item")

native:setMoveableMode("place")
native:clearCache()
selectNative(relocatedPlateTile, function(entry) return entry.object == recovered end)
click(relocatedPlateTile)
assert(arrive():complete())
local restored = placement.piecesAt(testState.registry, relocatedPlateTile)[1]
check(restored.id == nativePlate.id and restored.piece.ports.signal == false
    and restored.piece.state.label == "native test", "native placement restores old settings with a free port")

local stockCount = 0
for _, entry in ipairs(native:getInventoryObjectList()) do
    if entry.zedcommKey == "ZedComm.SignalWire" then stockCount = stockCount + 1 end
end
check(stockCount == 1, "native cycling lists a stack of loose wire as one candidate")

local wireCandidate = selectType(relocatedPlateTile, "ZedComm.SignalWire")
testState.choice, testState.queued, testState.queuedWalk = nil, nil, nil
click(relocatedPlateTile)
check(testState.choice and testState.choice.options["Place wire loose"] and testState.choice.options["Connect to pressure plate"]
    and not testState.queued and not testState.queuedWalk, "native wire placement prompts on a device free port")
testState.choice.options["Connect to pressure plate"]()
assert(arrive():complete())
local nativeWire = restored.piece.ports.signal
check(nativeWire and not inventory:contains(wireCandidate.object) and getCell():getDrag(0) == native,
    "native connect starts continuous laying from the newly placed wire")
local crossing = give("ZedComm.SignalWire")
local loose, crossingId = runPlacement(nextWireTile, { kind = "place", item = crossing })
assert(loose, crossingId)
player.tile = relocatedPlateTile
testState.queued, testState.queuedWalk, testState.choice = nil, nil, nil
click(nextWireTile)
check(testState.choice and testState.choice.options["Connect to wire 1 / Loose wire"] and testState.choice.options["Lay wire here"]
    and not testState.queued and not testState.queuedWalk, "an active native run can join a cable end or lay another wire")
testState.choice.options["Lay wire here"]()
assert(arrive():complete())
local connected
for _, entry in ipairs(placement.piecesAt(testState.registry, nextWireTile)) do
    if entry.id ~= crossingId then connected = entry end
end
check(connected and connected.piece.links[nativeWire] == true
    and #testState.registry.network:partners(crossingId) == 0, "the crossing stays independent of the selected run")

testState.invalidOutline = nil
click(floorTile(62, 55))
check(testState.invalidOutline and testState.invalidOutline.x == 63 and testState.invalidOutline.y == 56
    and testState.invalidOutline.r == 1 and testState.invalidOutline.a == 1 and testState.invalidOutline.width == 3,
    "the native cursor draws a bold red outline on an invalid wire tile")

testState.choice, testState.queued, testState.queuedWalk = nil, nil, nil
click(nativeDisplayTile)
check(testState.choice and testState.choice.options["Connect to numeric display"] and testState.choice.options["Lay wire here"]
    and not testState.queued and not testState.queuedWalk, "left-clicking a compatible endpoint offers join and lay choices")
testState.choice.visible = false

local savedWires = {}
for _, item in ipairs(carried) do
    if item:getFullType() == "ZedComm.SignalWire" then savedWires[#savedWires + 1] = item end
end
for _, item in ipairs(savedWires) do inventory:Remove(item) end
native:clearCache()
testState.choice = nil
click(nativeDisplayTile)
check(testState.choice and testState.choice.options["Connect to numeric display"] and not testState.choice.options["Lay wire here"],
    "the last placed wire can still be joined through the native cursor with no spare wire")
testState.choice.options["Connect to numeric display"]()
check(testState.queuedWalk and arrive():complete() and nativeDisplay.piece.ports.signal == connected.id
    and getCell():getDrag(0) == native, "left-click join uses the exact last segment and keeps the Place tool open")
for _, item in ipairs(savedWires) do inventory:AddItem(item) end
player.tile = nextWireTile
getCell():setDrag(native, 0)
native:clearCache()
native:rotateKey(0, true)
selectType(clearWireTile, "ZedComm.SignalWire")
testState.queued, testState.queuedWalk = nil, nil
click(clearWireTile)
check(testState.queuedWalk and arrive():complete(), "the native Place tool can start another loose wire after a completed run")
local standalone = placement.piecesAt(testState.registry, clearWireTile)[1]
testState.queued, testState.queuedWalk = nil, nil
click(skippedWireTile)
check(standalone and #testState.registry.network:partners(standalone.id) == 0 and not testState.queued and not testState.queuedWalk,
    "a loose first native segment becomes the anchor and prevents skipped tiles")
selectType(skippedWireTile, "Base.TestMoveable")
selectType(skippedWireTile, "ZedComm.SignalWire")
click(skippedWireTile)
check(testState.queuedWalk and testState.queuedWalk.location == skippedWireTile and arrive():complete(),
    "cycling to a different item releases the selected wire end")

give("ZedComm.SignalWire")
give("ZedComm.SignalWire")
selectType(clearWireTile, "Base.TestMoveable")
selectType(clearWireTile, "ZedComm.SignalWire")
testState.choice, testState.queued, testState.queuedWalk = nil, nil, nil
click(clearWireTile)
check(testState.choice and testState.choice.options["Place wire loose"] and testState.choice.options["Connect to wire 1 / Loose wire from an adjacent tile"]
    and not testState.queued and not testState.queuedWalk, "the native cursor prompts before placing on an existing free cable")
testState.choice.options["Place wire loose"]()
assert(arrive():complete())
local parallel = placement.piecesAt(testState.registry, clearWireTile)
table.sort(parallel, function(a, b) return a.id < b.id end)
check(#parallel == 2 and testState.registry.network:networkOf(parallel[1].id)
    ~= testState.registry.network:networkOf(parallel[2].id), "native loose placement keeps the two cables independent")

selectType(clearWireTile, "Base.TestMoveable")
selectType(clearWireTile, "ZedComm.SignalWire")
testState.choice, testState.queued, testState.queuedWalk = nil, nil, nil
click(clearWireTile)
assert(testState.choice.options["Connect to wire 2 / Loose wire from an adjacent tile"])()
local adjacent = floorTile(59, 54)
click(adjacent)
assert(arrive():complete())
local added = placement.piecesAt(testState.registry, adjacent)[1]
check(added and added.piece.links[parallel[2].id] == true and not added.piece.links[parallel[1].id],
    "native connect chooses the exact cable and lays the new segment on its neighboring tile")

native:setMoveableMode("pickup")
native:clearCache()
local selectedWire = selectNative(clearWireTile, function(entry)
    return entry.zedcommPickup and entry.zedcommPickup.id == parallel[2].id
end)
local info = selectedWire.moveProps:getInfoPanelDescription()
check(info[1] == "Wire 2 of 2" and info[2] == testState.registry:getRunName(parallel[2].id)
    and parallel[2].object:isOutlineHighlight(0) and not parallel[1].object:isOutlineHighlight(0),
    "native pickup cycles to the numbered wire and outlines exactly that segment")
local inventoryCount = #carried
click(clearWireTile)
check(arrive():complete() and #carried == inventoryCount + 1
    and carried[#carried]:getFullType() == "ZedComm.SignalWire"
    and not testState.registry.network.pieces[parallel[2].id]
    and testState.registry.network.pieces[parallel[1].id]
    and #testState.registry.network:partners(added.id) == 0,
    "native pickup returns one wire and severs only the selected link")
native:isValid(clearWireTile)
check(parallel[1].object:isOutlineHighlight(0) and not parallel[2].object:isOutlineHighlight(0),
    "the pickup outline follows the remaining wire")
getCell():setDrag(nil, 0)
check(not parallel[1].object:isOutlineHighlight(0), "leaving native Pickup restores the wire's outline")

do
    local startTile, lastTile = floorTile(66, 58), floorTile(67, 58)
    local targetTile, continuation = floorTile(68, 58), floorTile(69, 58)
    local ok, targetId = runPlacement(targetTile, { kind = "place", item = give("ZedComm.SignalWire") })
    assert(ok, targetId)
    assert(lay(continuation, give("ZedComm.SignalWire"), targetId, false))
    assert(testState.registry:renameRun(targetId, "Bench cable"))
    local placed, looseId = runPlacement(targetTile, { kind = "place", item = give("ZedComm.SignalWire") })
    assert(placed, looseId)

    player.tile = startTile
    native:setMoveableMode("place")
    native:clearCache()
    getCell():setDrag(native, 0)
    selectType(startTile, "ZedComm.SignalWire")
    click(startTile)
    assert(arrive():complete())
    click(lastTile)
    assert(arrive():complete())
    local active = placement.piecesAt(testState.registry, lastTile)[1]
    local runLabel = testState.registry:getRunName(active.id)
    local previewWire = selectType(lastTile, "ZedComm.SignalWire")
    check(runLabel and previewWire.moveProps:getInfoPanelDescription()[2] == runLabel,
        "native Place displays the active run's name")
    local rest = {}
    for _, item in ipairs(carried) do
        if item:getFullType() == "ZedComm.SignalWire" then rest[#rest + 1] = item end
    end
    for _, item in ipairs(rest) do inventory:Remove(item) end
    native:clearCache()

    testState.choice, testState.queued, testState.queuedWalk = nil, nil, nil
    click(targetTile)
    local number = targetId < looseId and 1 or 2
    local label = "Connect to wire " .. number .. " / " .. testState.registry:getRunName(targetId)
    check(testState.choice and testState.choice.options[label] and not testState.choice.options["Lay wire here"],
        "active placement offers the named cable end even with no spare wire")
    local option = testState.choice.entries[label]
    local targetObject = placement.resolve(testState.registry, targetId).object
    local looseObject = placement.resolve(testState.registry, looseId).object
    option.onHighlight(option, testState.choice, true, unpack(option.onHighlightParams))
    check(targetObject:isOutlineHighlight(0) and not looseObject:isOutlineHighlight(0),
        "hovering the join choice outlines only the named cable")
    option.onHighlight(option, testState.choice, false, unpack(option.onHighlightParams))

    local units = #carried
    testState.choice.options[label]()
    check(arrive():complete() and #carried == units and active.piece.links[targetId]
        and not active.piece.links[looseId] and testState.registry:getRunName(active.id) == testState.registry:getRunName(targetId)
        and getCell():getDrag(0) == native, "joining the exact existing cable uses no stock and finishes the active run")
    for _, item in ipairs(rest) do inventory:AddItem(item) end
    getCell():setDrag(nil, 0)
end

for i, plateSpec in ipairs({ { "ZedComm.OccupancyPlate", 419 }, { "ZedComm.WeightPlate", 425 } }) do
    local tile = floorTile(65 + i, 60)
    local itemType, frame = plateSpec[1], "zedcomm_devices_01_" .. plateSpec[2]
    local plateItem = give(itemType)
    native:setMoveableMode("place")
    native:clearCache()
    getCell():setDrag(native, 0)
    selectType(tile, itemType)
    click(tile)
    check(native.objectSprite and native.objectSprite:getName() == frame
        and arrive():complete() and not inventory:contains(plateItem),
        "native Place offers " .. itemType .. " with its own floor sprite")

    local plate = placement.piecesAt(testState.registry, tile)[1]
    native:setMoveableMode("pickup")
    native:clearCache()
    selectNative(tile, function(entry) return entry.zedcommPickup and entry.zedcommPickup.id == plate.id end)
    click(tile)
    check(arrive():complete() and carried[#carried]:getFullType() == itemType,
        "native Pickup returns " .. itemType)
    getCell():setDrag(nil, 0)
end

do
    local cabinetTile, wireTile = floorTile(72, 60), floorTile(73, 60)
    local placed, cabinetId = runPlacement(cabinetTile, { kind = "place", item = give("ZedComm.SmallCabinet") })
    assert(placed, cabinetId)
    local connected, wireId = lay(wireTile, give("ZedComm.SignalWire"), cabinetId, "input")
    assert(connected, wireId)

    native:setMoveableMode("pickup")
    native:clearCache()
    getCell():setDrag(native, 0)
    local lead = selectNative(wireTile, function(entry) return entry.zedcommPickup and entry.zedcommPickup.id == wireId end)
    assert(testState.registry:setCabinetPadlock(cabinetId, 42))
    check(not ZedComm.NativePlacementActions.canPickUp(native, lead.zedcommPickup, wireTile),
        "native Pickup rechecks a selected cabinet lead after the cabinet is locked")
    native:clearCache()
    native.currentSquare = wireTile
    local offered = false
    for _, entry in ipairs(native:getObjectList()) do
        if entry.zedcommPickup and entry.zedcommPickup.id == wireId then offered = true end
    end
    check(not offered, "native Pickup omits wire directly attached to a padlocked cabinet")
    assert(testState.registry:setCabinetPadlock(cabinetId, nil))
    native:clearCache()
    selectNative(wireTile, function(entry) return entry.zedcommPickup and entry.zedcommPickup.id == wireId end)
    getCell():setDrag(nil, 0)
end

do
    local mockProps = ISMoveableSpriteProps
    IsoGridSquare = { ignoreBlockingSprites = { add = function() end } }
    dofile(PZ .. "/shared/Moveables/ISMoveableSpriteProps.lua")
    mockProps.getTopTable = ISMoveableSpriteProps.getTopTable
    mockProps.getTotalTableHeight = ISMoveableSpriteProps.getTotalTableHeight
    ISMoveableSpriteProps = mockProps

    local counter, approach, origin = floorTile(93, 60), floorTile(92, 60), floorTile(91, 60)
    counter.class = "IsoGridSquare"
    local alternate = floorTile(93, 61)
    function origin:has() return false end
    function approach:canStand() return true end
    function alternate:canStand() return true end
    local speed = 1
    getGameSpeed = function() return speed end
    function player:getVehicle() return self.vehicle end
    ISPathFindAction = {
        pathToNearest = function(_, _, locations)
            return {
                locations = locations,
                location = alternate,
                setOnComplete = function(self, callback) self.onCompleteFunc = callback end,
            }
        end,
    }
    function counter:isSolidTrans() return true end
    function counter:has(flag) return flag == "IsTableTop" and self.occupied end
    local furniture = testState.worldObject(counter)
    local surface = {
        has = function(_, name) return name == "IsTable" or name == "Surface" end,
        get = function() return "30" end,
    }
    local furnitureSprite = {
        getName = function() return "test-counter" end,
        getProperties = function() return surface end,
    }
    function furniture:getSprite() return furnitureSprite end
    function furniture:getRenderYOffset() return 4 end

    local cabinetItem = give("ZedComm.TabletopCabinet")
    local advanced = give("ZedComm.AdvancedTabletopCabinet")
    native:setMoveableMode("place")
    native:clearCache()
    getCell():setDrag(native, 0)
    player.tile = origin
    check(selectType(origin, advanced:getFullType()).object == advanced and not native.canCreate,
        "native selection offers the Advanced Tabletop but rejects bare floor")
    local candidate = selectType(counter, cabinetItem:getFullType())
    local sprite = getSprite("zedcomm_cabinets_01_2")
    candidate.moveProps.canRotateDirection = function() return false end
    candidate.moveProps.getFaceDirectionFromSpriteName = function() end
    local previewOffset
    sprite.RenderGhostTileColor = function(_, _, _, _, _, offset) previewOffset = offset end
    Core = { getTileScale = function() return 2 end }
    renderIsoCircle = function() end
    gameRender(native, counter:getX(), counter:getY(), counter:getZ(), counter)
    check(native.canCreate and native.objectSprite == sprite and native.yOffset == 34 and previewOffset == 68,
        "native Place draws the cabinet at the installed surface height and tile scale")
    counter.occupied = true
    native:isValid(counter)
    check(not native.canCreate, "the native preview rejects an occupied countertop")
    counter.occupied = false
    testState.queuedWalk, testState.queued = nil, nil
    click(counter)
    local walking = testState.queuedWalk
    local goals = {}
    for i = 1, #(walking and walking.locations or {}), 3 do
        goals[walking.locations[i] .. "," .. walking.locations[i + 1]] = true
    end
    check(walking and walking:isValid() and #walking.locations == 6 and goals["92.5,60.5"] and goals["93.5,61.5"],
        "native Place offers both adjacent floor tiles to the pathfinder")
    if walking then
        speed = 3
        check(not walking:isValid(), "surface walking keeps the native speed limit")
        speed = 1
        player.vehicle = {}
        check(not walking:isValid(), "surface walking cannot start from a vehicle")
        player.vehicle = nil
    end
    if walking and walking.location == alternate then
        local action = assert(arrive())
        counter.occupied = true
        check(not action:isValid() and not action:complete() and inventory:contains(cabinetItem),
            "the timed action rejects a countertop occupied during approach")
        counter.occupied = false
    else
        testState.queuedWalk = nil
    end

    player.tile = approach
    testState.queuedWalk, testState.queued = nil, nil
    click(counter)
    local action = testState.queued
    check(not testState.queuedWalk and action and action:complete() and not inventory:contains(cabinetItem),
        "native Place completes from beside the countertop")
    local entry = placement.piecesAt(testState.registry, counter)[1]
    check(entry and entry.object:getRenderYOffset() == 34,
        "final native placement uses the same height as its preview")
    if entry then
        native:setMoveableMode("pickup")
        native:clearCache()
        selectNative(counter, function(selected) return selected.zedcommPickup and selected.zedcommPickup.id == entry.id end)
        testState.queuedWalk, testState.queued = nil, nil
        click(counter)
        check(not testState.queuedWalk and testState.queued and testState.queued:complete()
            and inventory:getFirstType(cabinetItem:getFullType()), "native Pickup also works from beside the countertop")
    end
    getCell():setDrag(nil, 0)
end

inventory.AddItem = realAddItem
getText, getPlayerRadialMenu, KeybindId = originalText, originalRadial, originalKeybind
IsoFlagType = originalFlagType

testState.finish()
