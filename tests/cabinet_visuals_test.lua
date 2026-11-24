local test = dofile("tests/support/placement_harness.lua")()
local fire, check = test.fire, test.check
local cabinetTile = test.floorTile(80, 80)
local northTile = test.floorTile(80, 79)
local eastTile = test.floorTile(81, 80)
cabinetTile.northWall, eastTile.westWall = {}, {}
dofile(test.LUA .. "client/ZedComm/WireVisuals.lua")

local function leads(tile)
    local found, count = {}, 0
    for _, object in ipairs((tile or cabinetTile).objects) do
        local direction = object:getModData().zedcommCabinetLead
        if direction then
            found[direction], count = object, count + 1
        end
    end
    return found, count
end

local placed, cabinet = test.runPlacement(cabinetTile,
    { kind = "place", item = test.give("ZedComm.AdvancedWallCabinet"), mount = "east" })
assert(placed, cabinet)
fire("OnTick")
check(test.spriteOf(cabinet) == "zedcomm_cabinets_01_6" and select(2, leads()) == 0,
    "an unlinked cabinet uses the saved wall face and has no leads")

local laid, northCable = test.lay(northTile, test.give("ZedComm.SignalWire"), cabinet, "output")
assert(laid, northCable)
local laid, sameTileCable = test.lay(cabinetTile, test.give("ZedComm.SignalWire"), cabinet, "input")
assert(laid, sameTileCable)
local laid, secondNorthCable = test.lay(northTile, test.give("ZedComm.SignalWire"), cabinet, "output-2")
assert(laid, secondNorthCable)
fire("OnTick")
local joined, count = leads()
check(test.spriteOf(cabinet) == "zedcomm_cabinets_01_10" and count == 2
    and joined[8] and joined[8].sprite == "zedcomm_switch_floor_01_19"
    and joined[0] and joined[0].sprite == "zedcomm_switch_floor_01_15"
    and joined[8]:getSprite():getProperties():has(IsoFlagType.FloorOverlay),
    "the chosen wall face has a drop and one grounded overlay per linked direction")

local duplicate = IsoObject.new(cabinetTile, joined[8].sprite)
duplicate:getModData().zedcommCabinetLead = 8
cabinetTile:AddTileObject(duplicate)
fire("LoadGridsquare", cabinetTile)
check(select(2, leads()) == 2 and leads()[8] == joined[8],
    "streaming reuses existing helpers and clears duplicates")

test.registry, test.java = test.start(test.save(test.java))
fire("LoadGridsquare", cabinetTile)
fire("OnTick")
check(select(2, leads()) == 2 and leads()[0] == joined[0] and leads()[8] == joined[8],
    "reload rederives the same grounded leads without duplicating a saved helper")

assert(test.target(northTile, northCable, "pickup"))
fire("OnTick")
check(select(2, leads()) == 2 and leads()[8] == joined[8],
    "a shared directional overlay remains until its last link goes away")
assert(test.target(northTile, secondNorthCable, "pickup"))
fire("OnTick")
check(select(2, leads()) == 1 and leads()[0] == joined[0],
    "picking up the last cable in a direction clears its overlay")

assert(test.target(cabinetTile, cabinet, "pickup"))
fire("OnTick")
check(select(2, leads()) == 0 and test.registry.network:record(sameTileCable),
    "picking up the cabinet clears its leads and leaves the cable")
local item = assert(test.inventory:getFirstType("ZedComm.AdvancedWallCabinet"))
local placedAgain, sameCabinet = test.runPlacement(cabinetTile, { kind = "place", item = item })
assert(placedAgain, sameCabinet)
assert(test.registry:link(sameTileCable, sameCabinet, "input"))
fire("OnTick")
check(sameCabinet == cabinet and test.spriteOf(sameCabinet) == "zedcomm_cabinets_01_10"
    and select(2, leads()) == 1, "replacement restores the saved face when rewired")

cabinetTile:transmitRemoveItemFromSquare(test.placement.resolve(test.registry, cabinet).object)
fire("OnTick")
check(select(2, leads()) == 0 and not test.registry.network:record(cabinet),
    "world removal clears the grounded helper with no cabinet remaining")
local tableSquare, tableCableSquare = test.floorTile(89, 80), test.floorTile(90, 80)
ISMoveableSpriteProps = { getTotalTableHeight = function(_, square) return square == tableSquare and 30 or 0 end }
local ok, bench = test.runPlacement(tableSquare, { kind = "place", item = test.give("ZedComm.TabletopCabinet") })
assert(ok, bench)
local laid, benchWire = test.lay(tableCableSquare, test.give("ZedComm.SignalWire"), bench, "input")
assert(laid, benchWire)
fire("OnTick")
local raised = leads(tableSquare)[1]
check(raised and raised.sprite == "zedcomm_tabletop_leads_01_146" and raised.noPicking,
    "tabletop lead matches the actual height and the connected tile edge")
assert(test.target(tableCableSquare, benchWire, "pickup"))
fire("OnTick")
check(select(2, leads(tableSquare)) == 0, "disconnecting the tabletop clears the raised lead")

local floorSquare, floorCableSquare = test.floorTile(95, 80), test.floorTile(95, 81)
local ok, floorCabinet = test.runPlacement(floorSquare, { kind = "place", item = test.give("ZedComm.SmallCabinet") })
assert(ok, floorCabinet)
assert(test.lay(floorCableSquare, test.give("ZedComm.SignalWire"), floorCabinet, "input"))
fire("OnTick")
local floorLead = leads(floorSquare)[2]
check(floorLead and floorLead.sprite == "zedcomm_devices_01_5"
    and floorLead:getSprite():getProperties():has(IsoFlagType.FloorOverlay),
    "a floor cabinet extends the cable up to the mesh under the footprint")
test.finish()
