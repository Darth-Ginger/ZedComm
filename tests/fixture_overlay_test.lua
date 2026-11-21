local test = dofile("tests/support/editor_harness.lua")()
local player, check = test.player, test.check
local tile, opposite, obscured = test.floorTile(70, 70), test.floorTile(70, 69), test.floorTile(71, 70)
local makeDoor = dofile("tests/support/door_fixture.lua")(function(square)
    local object = IsoObject.new(square, "test_door")
    square:AddTileObject(object)
    return object
end)
local door = makeDoor(tile)
test.give("Base.Screwdriver")
test.give("ZedComm.BasicAdapter")
test.give("ZedComm.BasicAdapter")
local fitted, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(fitted, id)
local source = test.placeTestItem(obscured, "ZedComm.DebugByteSource")
test.registry:renameFixture(source, "Open Source")
test.registry:setFixtureOption(source, "showFixtureName", true)
player.tile = tile
door.open = true
require "ZedComm/DebugCircuits"

function screenToIsoX() return 71.5 end
function screenToIsoY() return 70.5 end
local function menuFromDoor()
    local menu = test.menu()
    menu.x, menu.y = 100, 100
    test.fire("OnFillWorldObjectContextMenu", 0, menu, { door }, false)
    return menu.children.ZedComm
end

local menu = menuFromDoor()
local sourceMenu = menu and menu.children["Source (Open Source)"]
check(sourceMenu and sourceMenu.options["Set test byte"] and menu.children.Door,
    "an open door picked in front of a reachable source exposes both fixture menus")
tile.blocked = obscured
menu = menuFromDoor()
check(menu and not menu.children["Source (Open Source)"], "a hidden fixture outside normal reach stays unavailable")
tile.blocked = nil

function player:getX() return self.tile:getX() end
function player:getY() return self.tile:getY() end
function player:getZ() return self.tile:getZ() end
function tile:isCouldSee() return false end
function opposite:isCouldSee() return true end
function obscured:isCouldSee() return true end
Core = { getTileScale = function() return 2 end }
local zoom = 1
getCore = function() return { getZoom = function() return zoom end } end
getText = function(key) return key end
UIFont = { Small = "Small" }
local controls = {}
PZAPI = { ModOptions = { create = function()
    return { addTickBox = function(_, key)
        controls[key] = true
        return { getValue = function() return controls[key] end }
    end }
end } }
package.loaded["PZAPI/ModOptions"] = true

local icons, labels = {}, {}
getTexture = function(path)
    return { path = path, getWidth = function() return 16 end, getHeight = function() return 16 end }
end
UIManager = { DrawTexture = function(icon, x, y)
    icons[#icons + 1] = { path = icon.path, x = x, y = y }
end }
getTextManager = function()
    return { DrawStringCentre = function(_, _, x, y, text, red)
        if red == 1 then labels[text] = { x = x, y = y } end
    end }
end
isoToScreenX = function(_, x) return x * 20 end
isoToScreenY = function(_, _, y, z) return y * 20 - z * 192 end

require "ZedComm/FixtureLabels"
test.fire("OnPostUIDraw")
check(#icons == 0 and not labels["Open Source"], "fixture overlays do not draw after the game UI")
test.fire("OnPreUIDraw")
check(#icons == 2 and icons[1].path:find("MaglockUnlocked", 1, true)
    and icons[2].path:find("DoorOpen", 1, true) and icons[1].x == 1393 and icons[1].y == 1320,
    "the unlocked and open icons sit on the visible doorway even when its owning tile is occluded")
check(labels["Open Source"] and labels["Open Source"].x == 1430 and labels["Open Source"].y == 1371,
    "the test source name sits just above its floor sprite")

door.open, door.locked = false, true
zoom = 2
icons = {}
test.fire("OnPreUIDraw")
check(#icons == 2 and icons[1].path:find("MaglockLocked", 1, true)
    and icons[2].path:find("DoorClosed", 1, true) and icons[1].y == 1352,
    "closed and locked change independently and the anchor follows world zoom")
icons, labels = {}, {}
controls.doorMarkers = false
test.fire("OnPreUIDraw")
check(#icons == 0 and labels["Open Source"], "the global door icon switch leaves enabled fixture names visible")
test.finish()
