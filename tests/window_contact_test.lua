local test = dofile("tests/support/editor_harness.lua")()
local check, fire = test.check, test.fire
local tile, outputTile = test.floorTile(420, 400), test.floorTile(421, 400)
local far = test.floorTile(420, 399)
tile.blocked, far.blocked = far, tile
local window = IsoObject.new(tile, "zedcomm_devices_01_467")
tile:AddTileObject(window)
window.class = "IsoWindow"
function window:isOpen() return self.open == true end
function window:isNorth() return true end
function window:isSmashed() return self.smashed == true end
function window:isDestroyed() return self.destroyed == true end
function window:isGlassRemoved() return self.glassRemoved == true end
Perks = { Electricity = 1 }
test.player.getPerkLevel = function() return 1 end
FBORenderChunk.DIRTY_OBJECT_MODIFY = 256
local originalSprite = getSprite
getSprite = function(name)
    if name:match("^zedcomm_window_contact_01_%d+$") then return { getName = function() return name end } end
    return originalSprite(name)
end

test.give("Base.Screwdriver")
local item = test.give("ZedComm.WindowContact")
local function install()
    assert(test.optionsAt(far, "Window")["Install window contact"])()
    assert(test.queued:isValid() and test.queued:complete())
    return assert(window:getModData().zedcommContact)
end
local id = install()
local function entry() return assert(test.placement.resolve(test.registry, id)) end
check(not test.inventory:contains(item) and not window:getModData().zedcomm
    and entry().piece.definitionId == "ZedComm.WindowContact",
    "fitting uses the window contact item and preserves native control")
check(not test.optionsAt(tile)["Install window contact"], "one contact can be fitted per window")

local display = test.placeTestItem(outputTile, "ZedComm.NumericDisplay")
local wire = test.runTestWire(tile, id, "signal", outputTile, display, "signal")
local function attachedSprite()
    local children = window:getAttachedAnimSprite()
    return children and children:size() > 0 and children:get(0):getParentSprite():getName()
end
check(test.placedReading(display) == 255, "closed intact window sends 255")
local closedArt = attachedSprite()
window.open = true
check(test.placedReading(display) == 0, "open intact window sends valid zero")
check(closedArt and closedArt:match("^zedcomm_window_contact_01_")
    and attachedSprite() and attachedSprite() ~= closedArt, "window contact has its own changing sash art")
window.open, window.smashed = false, true
check(test.placedReading(display) == nil and entry().piece.ports.signal == wire,
    "broken glass produces no signal while keeping the fitted contact")
test.registry, test.java = test.start(test.save(test.java))
check(test.placedReading(display) == nil and entry().piece.ports.signal == wire
    and ZedComm.DoorContact.host(entry().object) == window, "reload preserves binding and cable on a damaged window")
assert(test.optionsAt(tile, "Window Contact")["Remove window contact"])()
check(test.queued:isValid() and test.queued:complete() and not window:getModData().zedcommContact
    and test.inventory:getFirstType("ZedComm.WindowContact")
    and not test.registry.network.pieces[wire].links[id], "contact can be removed from a broken window")
check(not test.optionsAt(tile)["Install window contact"], "a broken window cannot take a new sensor")
window.smashed = false
id = install()
window.glassRemoved = true
local definition = ZedComm.DeviceDefinitions.get(entry().piece.definitionId)
check(definition.sample(entry().object) == nil, "removed glass also suppresses the signal")
fire("OnObjectAboutToBeRemoved", window)
test.takeOff(tile, window)
fire("OnTick")
check(not test.registry.network.pieces[id], "removing the host cleans up its contact")
test.finish()
