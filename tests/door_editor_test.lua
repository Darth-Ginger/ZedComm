local test = dofile("tests/support/editor_harness.lua")()
local makeDoor = dofile("tests/support/door_fixture.lua")(function(tile)
    local object = IsoObject.new(tile, "zedcomm_devices_01_467")
    tile.objects[#tile.objects + 1] = object
    return object
end)
test.player.getPerkLevel = function() return 3 end
local check, Circuit = test.check, ZedComm.InternalCircuit
local tile = test.floorTile(200, 200)
local otherFace = test.floorTile(200, 199)
tile.blocked, otherFace.blocked = otherFace, tile
local door = makeDoor(tile, "IsoThumpable")
test.give("Base.Screwdriver")
test.give(Circuit.ADVANCED_ADAPTER_ITEM); test.give(Circuit.ADVANCED_ADAPTER_ITEM)
local options = test.optionsAt(otherFace)
assert(options["Install two Advanced Adapters"])()
check(test.queued and test.queued.maxTime == 1 and test.queued:isValid(), "door install uses the shared timed action")
assert(test.queued:complete())
local id = door:getModData().zedcomm.id
local function piece() return test.registry.network.pieces[id] end
test.player.isTimedActionInstant = function() return false end
local command = { kind = "remove-door-adapters" }
check(test.queued:new(test.player, command).maxTime == 120, "door adapter work has a non-instant duration")
test.player.isTimedActionInstant = function() return true end
local root = test.menuAt(otherFace)
check(root.children.Door and root.children.Door.options["Open Door Board"], "door controls live in the fixture submenu")
assert(test.optionsAt(otherFace)["Open Door Board"])()
local panel = test.panel
assert(panel:refresh())
check(panel.reachable, "closed door board can be edited from the opposite face")
check(panel.gridSize == 6 and panel.gridRows == 3 and panel.gridHeight == 180, "editor respects rectangular dimensions")
check(not panel:insideGrid(100, 245) and panel:insideGrid(100, 243), "hit testing ends at the third row")
check(panel.parts.lock.label == "Lock IN" and panel.parts.openAction.action
    and panel.parts.lock.width == 60 and panel.parts.open.width == 120, "fixed jacks and actuators occupy rotated two-cell parts")
test.give("ZedComm.WaitModule"); test.give("ZedComm.NotModule"); test.give("ZedComm.AndModule")
test.give("ZedComm.InputExtension"); test.give("ZedComm.SplitterModule")
panel:refresh()
local kinds = {}
for _, entry in ipairs(panel.paletteEntries) do if entry.kind then kinds[entry.kind] = true end end
check(kinds.wait and kinds["and"] and not kinds.inputExtension and not kinds.splitter,
    "door palette includes logic and omits additional physical jacks")
test.dragCarried("wait")
panel:onMouseUp(106, 124)
check(piece().state.circuit.modules["wait-1"] ~= nil, "existing drag placement installs Wait into shared board")
test.dragCarried("not")
panel:onMouseUp(166, 124)
test.dragCarried("and")
panel:onMouseUp(226, 124)
panel:linkTerminal("lock", "out"); panel:linkTerminal("wait-1", "in")
panel:linkTerminal("wait-1", "out"); panel:linkTerminal("not-2", "in")
panel:linkTerminal("not-2", "out"); panel:linkTerminal("and-3", "b")
panel:linkTerminal("open", "out"); panel:linkTerminal("and-3", "a")
panel:linkTerminal("and-3", "out"); panel:linkTerminal("openAction", "in")
check(#piece().state.circuit.links == 6, "internal fan-out and separate actuator links fit without a Splitter")
test.fire("OnTick")
panel:render()
check(panel.parts.lockAction.action and panel.parts.openAction.action, "rendering preserves local actuator identity")
local labels = test.menuAt(otherFace).children.Door.children["Label door jack"]
assert(labels.options["Lock IN"])()
test.input = "Secure"; test.confirm()
check(piece().state.portLabels.lock == "Secure", "physical door jacks use reusable labels")
panel:close()
test.inventory.full = true
check(not test.target(tile, id, "remove-door-adapters") and piece(), "failed module recovery keeps complete door installation")
test.inventory.full = false
check(test.target(tile, id, "remove-door-adapters"), "door removal recovers installed logic through normal action")
test.give(Circuit.BASIC_ADAPTER_ITEM); test.give(Circuit.BASIC_ADAPTER_ITEM)
local ok
ok, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(ok, id)
assert(test.optionsAt(tile)["Open Door Board"])()
assert(test.panel:refresh())
check(test.panel.readOnly and #test.panel.paletteEntries == 0, "Basic board shows fixed paths without free programming")
test.panel:linkTerminal("lock", "out"); test.panel:linkTerminal("openAction", "in")
check(#piece().state.circuit.links == 2, "Basic board cannot rewire independent actuator paths")
test.panel:render()
test.finish()
