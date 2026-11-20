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
    and not Circuit.compile({ modules = { overlap = { kind = "not", column = 10, row = 7, rotation = 0 } }, links = {} },
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
local cableOK, cable = test.lay(floor(201, 125), test.give("ZedComm.SignalWire"), tabletop, "output")
check(cableOK and piece(tabletop).ports.output == cable, "tabletop jack can connect from adjacent floor")

assert(test.registry:renameCabinetPort(large, "input-2", "Second feed"))
local adapter = test.give("ZedComm.AdvancedAdapter")
check(target(largeTile, large, "upgrade-cabinet", { item = adapter })
    and entry(large).spec.itemType == "ZedComm.AdvancedLargeCabinet"
    and piece(large).state.portLabels["input-2"] == "Second feed", "adapter upgrade retains cabinet size and jack names")
assert(test.registry:setCabinetPadlock(large, 42))
test.registry, test.java = test.start(test.save(test.java))
check(piece(large).state.padlockKeyId == 42 and not target(largeTile, large, "pickup")
    and piece(wall).state.mount == "west" and piece(tabletop).ports.output == cable,
    "size, locks, mounts and tabletop network links survive reload")
assert(test.registry:setCabinetPadlock(large, nil))
assert(target(largeTile, large, "pickup"))
local carried = assert(test.inventory:getFirstType("ZedComm.AdvancedLargeCabinet"))
local replaced, replacement = test.runPlacement(largeTile, { kind = "place", item = carried })
check(replaced and replacement == large and piece(large).state.portLabels["input-2"] == "Second feed",
    "pickup returns the correct upgraded variant and preserves configuration")
test.finish()
