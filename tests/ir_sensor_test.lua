local t = dofile("tests/support/menu_harness.lua")()
t.registry, t.java = t.start()
local ir = ZedComm.IRSensor
local function actor(class, dead, vehicle)
    return { class = class, isDead = function() return dead end, getVehicle = function() return vehicle end }
end
local zombie, player = actor("IsoZombie"), actor("IsoPlayer")
local animal, driver = actor("IsoAnimal"), actor("IsoPlayer", false, {})
local origin, near, far = t.floorTile(120, 120), t.floorTile(121, 120), t.floorTile(122, 120)
local blocked, door = false, false
for _, tile in ipairs({ origin, near, far }) do
    function tile:getCell() return getCell() end
    function tile:isWallTo(other) return self == origin and other == near and blocked end
    function tile:isDoorTo(other) return self == origin and other == near and door end
    function tile:isDoorBlockedTo(other) return self:isDoorTo(other) and blocked end
end
local placed, id = t.runPlacement(origin, { kind = "place", item = t.give(ir.ID) })
assert(placed, id)
local displayOK, display = t.runPlacement(far, { kind = "place", item = t.give("ZedComm.NumericDisplay") })
assert(displayOK, display)
local wired, wire = t.lay(near, t.give("ZedComm.SignalWire"), id, "signal")
assert(wired, wire)
assert(t.join(far, wire, false, display, "signal"))

local fixture = t.placement.resolve(t.registry, id).object
local function read(mode, target, radius, byte)
    return ir.sample(fixture, nil, { mode = mode, target = target, radius = radius, byte = byte })
end
t.check(t.placedReading(display) == 0, "a clear wired IR source sends a valid zero")
local otherFloor = t.square(120, 120, 1)
otherFloor.actors = { player }
t.check(read("count") == 0, "actors on another floor do not count")
far.actors = { zombie, animal, driver, actor("IsoZombie", true), actor("IsoDeadBody") }
t.check(read("fixed") == 255 and read("fixed", nil, nil, 17) == 17, "default and custom fixed output")
t.check(read("count") == 1 and read("count", "player") == 0, "living on-foot actor filter")
near.actors = { player }
t.check(read("count", "both") == 2 and read("count", "zombie") == 1, "target and combined counts")
near.actors = {}
t.check(read("nearest", nil, 2) == 1 and read("nearest", nil, 1) == 0, "inclusive boundary and radius exclusion")
near.actors = { player }
t.check(read("nearest", nil, 2) == 128, "nearest of multiple targets scales by distance")
origin.actors = { zombie }
t.check(read("nearest", nil, 2) == 255, "sensor tile reports maximum proximity")
origin.actors = {}
blocked = true
t.check(read("fixed") == 0, "intervening wall hides all targets")
door = true
t.check(read("fixed") == 0, "closed door blocks detection")
blocked = false
t.check(read("fixed") == 255, "opened door permits detection")
near.actors = {}
t.loaded["121,120,0"] = nil
t.check(read("fixed") == 0, "an unloaded intermediate square blocks the ray")
t.loaded["121,120,0"] = true
for i = 1, 260 do near.actors[i] = player end
t.check(read("count") == 255, "count saturates")
t.check(ir.validate("byte", 0) == 0 and not ir.validate("radius", 0)
    and not ir.validate("radius", 11) and not ir.validate("byte", 1.5), "numerical configuration bounds")
local options = t.optionsAt(origin)
t.check(options["Detect actors (both)"] and options["Detection radius (5)"] and options["Output mode (fixed)"]
    and options["Fixed output (255)"], "all four settings are accessible from the fixture")
package.loaded["ISUI/ISTextBox"] = true
local modal
ISTextBox = { new = function(_, x, y, w, h, title, initial, owner, confirm)
    modal = { initialise = function() end, addToUIManager = function() end,
        entry = { getText = function() return "19" end }, confirm = confirm }
    return modal
end }
options["Fixed output (255)"]()
modal.confirm(nil, { internal = "OK" })
t.check(t.placedReading(display) == 19, "settings applied through the UI update wired output")
t.registry, t.java = t.start(t.save(t.java))
t.check(t.placedReading(display) == 19, "reload keeps settings and samples immediately")
assert(t.target(origin, id, "pickup"))
local recovered = t.carried[#t.carried]
t.check(recovered:getFullType() == ir.ID and t.placedReading(display) == nil, "pickup clears the wired receiver")
local restored, again = t.runPlacement(origin, { kind = "place", item = recovered })
t.check(restored and again == id and t.join(origin, wire, false, id, "signal") and t.placedReading(display) == 19,
    "replacement restores the recovered sensor settings")
t.finish()
