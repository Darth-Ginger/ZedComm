local test = dofile("tests/support/editor_harness.lua")()
local Circuit, Packet = ZedComm.InternalCircuit, test.Packet
local place, floor, target, check = test.placeTestItem, test.floorTile, test.target, test.check
local originalSprite, originalObject = getSprite, IsoObject.new

getSprite = function(name)
    if name and name:match("^zedcomm_cabinets_01_") then return { getName = function() return name end } end
    return originalSprite(name)
end

IsoObject.new = function(square, sprite, name)
    local object = originalObject(square, sprite, name)
    function object:setRenderYOffset(offset) self.offset = offset end
    return object
end

local function piece(id) return test.registry.network.pieces[id] end
local function entry(id) return test.placement.resolve(test.registry, id) end
local largeTile, xlTile, wallTile, tableTile = floor(170, 125), floor(180, 125), floor(190, 125), floor(200, 125)
local large = place(largeTile, "ZedComm.LargeCabinet")
local xl = place(xlTile, "ZedComm.AdvancedXLCabinet")
local ls, lr = Circuit.dimensions(piece(large).board.profile)
local xs, xr = Circuit.dimensions(piece(xl).board.profile)
check(ls == 8 and lr == 8 and xs == 10 and xr == 10, "large and XL dimensions come from their cabinet profiles")
check(piece(large).ports["input-2"] == false and piece(large).ports["output-2"] == false
    and piece(large).ports["input-3"] == nil and piece(xl).ports["input-3"] == false
    and piece(xl).ports["output-3"] == false, "size-specific fixed jacks register as independent ports")

local rotatedTile = floor(180, 130)
local drops, rolls, nextRoll = {}, { 4, 24, 0, 64, 0, 0, 74, 0 }, 1
function rotatedTile:AddWorldInventoryItem(itemType)
    drops[#drops + 1] = itemType
end
ZombRand = function(limit)
    local roll = assert(rolls[nextRoll], "unexpected salvage roll")
    assert(roll < limit)
    nextRoll = nextRoll + 1
    return roll
end
local item = test.give("ZedComm.AdvancedSmallCabinet")
rotatedTile.actors = { test.player }
check(not test.runPlacement(rotatedTile, { kind = "place", item = item }) and test.inventory:contains(item),
    "floor cabinet placement waits for an occupied tile to clear")
rotatedTile.actors = nil
local placed, rotated = test.runPlacement(rotatedTile, { kind = "place", item = item, facing = 4 })
check(placed and piece(rotated).state.facing == 4 and entry(rotated).object.sprite == "zedcomm_cabinet_faces_01_3",
    "placed floor cabinet retains the selected model facing")
local cabinet = entry(rotated).object
check(cabinet.special and cabinet.blockAll and not cabinet.passThrough and cabinet.thumpable
    and cabinet.health == 500 and rotatedTile.recalculated,
    "floor cabinet registers as a blocking destructible object")
cabinet:setHealth(320)
assert(target(rotatedTile, rotated, "pickup"))
check(nextRoll == 1 and #drops == 0, "picking up a cabinet skips salvage rolls")
local recovered = test.inventory:getFirstType("ZedComm.AdvancedSmallCabinet")
local returned, same = test.runPlacement(rotatedTile, { kind = "place", item = recovered })
check(returned and same == rotated and piece(same).state.facing == 4,
    "pickup and replacement keep the floor cabinet facing")
check(entry(same).object:getHealth() == 320, "pickup and replacement preserve cabinet damage")

local wireTile = floor(181, 130)
local wired, wire = test.lay(wireTile, test.give("ZedComm.SignalWire"), same, "output")
assert(wired and piece(same).ports.output == wire)
local destroyed = entry(same).object
test.fire("OnDestroyIsoThumpable", destroyed)
rotatedTile:transmitRemoveItemFromSquare(destroyed)
check(piece(same) == nil and piece(wire) and piece(wire).links[same] == nil,
    "destroying a cabinet removes its board and frees the attached wire")
check(nextRoll == 9 and table.concat(drops, ",") ==
    "ZedComm.AdvancedAdapter,Base.SheetMetal,Base.ElectronicsScrap,Base.ElectricWire,Base.ElectricWire",
    "destruction rolls salvage once and uses the cabinet's adapter tier")

drops, rolls, nextRoll = {}, { 4, 25, 64, 0, 1, 75 }, 1
local basic = place(rotatedTile, "ZedComm.SmallCabinet")
rotatedTile:transmitRemoveItemFromSquare(entry(basic).object)
check(nextRoll == 7 and table.concat(drops, ",") == "ZedComm.BasicAdapter,Base.ScrapMetal",
    "direct demolition can drop the Basic Adapter and metal scrap")

drops, rolls, nextRoll = {}, { 5, 25, 65, 75 }, 1
local cabinetWithoutSalvage = place(rotatedTile, "ZedComm.SmallCabinet")
rotatedTile:transmitRemoveItemFromSquare(entry(cabinetWithoutSalvage).object)
check(nextRoll == 5 and #drops == 0, "salvage can fail all four rolls")

drops, rolls, nextRoll = {}, { 5, 24, 1, 64, 1, 0, 1, 74, 1 }, 1
local smashedLarge = place(rotatedTile, "ZedComm.LargeCabinet")
rotatedTile:transmitRemoveItemFromSquare(entry(smashedLarge).object)
check(nextRoll == 10 and #drops == 7 and drops[2] == "Base.SheetMetal"
    and drops[3] == "Base.ElectronicsScrap" and drops[4] == "Base.ScrapMetal"
    and drops[5] == "Base.ElectricWire" and drops[7] == "Base.ElectricWire",
    "large cabinets can drop two sheets, mixed scrap, and three electrical wires")

drops, rolls, nextRoll = {}, { 4, 24, 2, 64, 3, 1, 1, 1, 1, 74, 2 }, 1
local smashedXL = place(rotatedTile, "ZedComm.XLCabinet")
rotatedTile:transmitRemoveItemFromSquare(entry(smashedXL).object)
check(nextRoll == 12 and #drops == 12 and drops[1] == "ZedComm.BasicAdapter"
    and drops[4] == "Base.SheetMetal" and drops[8] == "Base.ScrapMetal"
    and drops[9] == "Base.ElectricWire" and drops[12] == "Base.ElectricWire",
    "XL cabinets can drop an adapter, three sheets, four scrap pieces and four electrical wires together")

local occupiedFloor = floor(180, 131)
function occupiedFloor:has(flag) return flag == "IsTable" end
check(not test.placement.canPlace(occupiedFloor, "ZedComm.LargeCabinet")
    and test.placement.canPlace(occupiedFloor, "ZedComm.SignalWire"),
    "floor cabinets reject furniture tiles while wire remains available")

local originalCore = getCore
getCore = function()
    local core = originalCore()
    core.getScreenWidth = function() return 1024 end
    core.getScreenHeight = function() return 600 end
    return core
end
assert(test.optionsAt(xlTile)["Open XL Cabinet"])()
local panel = assert(test.panel)
assert(panel:refresh())
panel:render()
check(panel.gridSize == 10 and panel.gridRows == 10 and panel.parts["output-3"].moveable == false,
    "XL shares the editor and its additional jacks are fixed")
check(panel.gridHeight + 111 <= 600 and panel.gridWidth + 218 <= 1024,
    "XL scales the editor grid to fit a smaller screen")
panel:close()
getCore = originalCore

local fixed = Circuit.fixedParts(piece(xl).board.profile)
check(fixed["output-3"].column == 10 and fixed["output-3"].row == 7
    and not Circuit.validate({ modules = { overlap = { kind = "not", column = 10, row = 7, rotation = 0 } }, links = {} },
        piece(xl).board.profile, "advanced"), "fixed jack footprints are reserved")
local layout = { modules = {
    extension = { kind = "outputExtension", column = 10, row = 9, rotation = 180 },
    cache = { kind = "cache", column = 3, row = 7, rotation = 0, always = true },
}, links = {
    { from = "input-3", output = "out", to = "cache", input = "data" },
    { from = "cache", output = "out", to = "output-3", input = "in" },
} }
local evaluate = assert(Circuit.compilePackets(layout, piece(xl).board.profile, "advanced"))
local reading = evaluate({ ["input-3"] = Packet.basic(37) })
check(Packet.basicValue(reading["output-3"]) == 37, "additional fixed jacks route a real packet")
layout.outputModes = { ["output-3"] = "advanced" }
evaluate = assert(Circuit.compilePackets(layout, piece(xl).board.profile, "advanced"))
reading = evaluate({ ["input-3"] = Packet.weight(375, 37) })
check(reading["output-3"].value.amount == 375, "XL Advanced can forward the full packet through an additional jack")

local wallItem = test.give("ZedComm.WallCabinet")
check(not test.runPlacement(wallTile, { kind = "place", item = wallItem }) and test.inventory:contains(wallItem),
    "wall cabinet requires an eligible wall")
wallTile.northWall, wallTile.westWall = {}, {}
local mounted, wall = test.runPlacement(wallTile, { kind = "place", item = wallItem, mount = "west" })
check(mounted and entry(wall).object.sprite == "zedcomm_cabinets_01_4" and piece(wall).state.mount == "west"
    and piece(wall).ports["output-2"] == false, "wall cabinet uses selected facing and the Large board")

local wallObject = entry(wall).object
check(wallObject.special and wallObject.thumpable and wallObject.passThrough and not wallObject.blockAll,
    "a wall cabinet is destructible and leaves collision to the wall")

local tableItem = test.give("ZedComm.TabletopCabinet")
ISMoveableSpriteProps = { getTotalTableHeight = function(_, square) return square.surfaceHeight or 0 end }
function tableTile:has(flag) return flag == "IsTableTop" and self.occupiedTop end
check(not test.runPlacement(tableTile, { kind = "place", item = tableItem }), "tabletop cabinet requires a surface")
tableTile.surfaceHeight = 30
tableTile.occupiedTop = true
check(not test.runPlacement(tableTile, { kind = "place", item = tableItem }), "tabletop cabinet rejects an occupied surface")
tableTile.occupiedTop = false
function tableTile:isSolidTrans() return true end
local placed, tabletop = test.runPlacement(tableTile, { kind = "place", item = tableItem })
check(placed and entry(tabletop).object.offset == 30 and piece(tabletop).ports["input-2"] == nil,
    "tabletop cabinet uses the furniture offset and Small board even on a solid furniture tile")
local tableObject = entry(tabletop).object
check(tableObject.special and tableObject.thumpable and tableObject.passThrough and not tableObject.blockAll,
    "a tabletop cabinet is destructible and leaves collision to its support")
local cableOK, cable = test.lay(floor(201, 125), test.give("ZedComm.SignalWire"), tabletop, "output")
check(cableOK and piece(tabletop).ports.output == cable, "tabletop jack can connect from adjacent floor")

assert(test.registry:renameCabinetPort(large, "input-2", "Second feed"))
local adapter = test.give("ZedComm.AdvancedAdapter")
check(target(largeTile, large, "upgrade-cabinet", { item = adapter })
    and entry(large).spec.itemType == "ZedComm.AdvancedLargeCabinet"
    and piece(large).state.portLabels["input-2"] == "Second feed", "adapter upgrade retains cabinet size and jack names")
assert(test.registry:setPadlock(large, 42))
test.registry, test.java = test.start(test.save(test.java))
check(piece(large).state.padlockKeyId == 42 and not target(largeTile, large, "pickup")
    and piece(wall).state.mount == "west" and piece(tabletop).ports.output == cable,
    "size, locks, mounts and tabletop network links survive reload")
assert(test.registry:setPadlock(large, nil))
assert(target(largeTile, large, "pickup"))
local carried = assert(test.inventory:getFirstType("ZedComm.AdvancedLargeCabinet"))
local replaced, replacement = test.runPlacement(largeTile, { kind = "place", item = carried })
check(replaced and replacement == large and piece(large).state.portLabels["input-2"] == "Second feed",
    "pickup returns the correct upgraded variant and preserves configuration")
wallTile.AddWorldInventoryItem = rotatedTile.AddWorldInventoryItem
tableTile.AddWorldInventoryItem = rotatedTile.AddWorldInventoryItem
drops, rolls, nextRoll = {}, { 4, 24, 1, 64, 1, 0, 1, 74, 1 }, 1
wallTile:transmitRemoveItemFromSquare(wallObject)
check(nextRoll == 10 and #drops == 8 and drops[1] == "ZedComm.BasicAdapter" and drops[8] == "Base.ElectricWire",
    "wall cabinets use Large salvage limits")
drops, rolls, nextRoll = {}, { 4, 24, 0, 64, 0, 0, 74, 0 }, 1
tableTile:transmitRemoveItemFromSquare(tableObject)
check(nextRoll == 9 and #drops == 5 and drops[2] == "Base.SheetMetal" and drops[5] == "Base.ElectricWire"
    and piece(cable) and piece(cable).links[tabletop] == nil, "tabletop cabinets use Small salvage limits and free their wire")
test.finish()
