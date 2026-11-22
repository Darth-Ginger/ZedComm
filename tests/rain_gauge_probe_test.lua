local t = dofile("tests/support/menu_harness.lua")()
local intensity = 1
getClimateManager = function() return {} end
package.loaded["ZedComm/Devices/EnvironmentalSensors"] = true
ZedComm.EnvironmentalSensors = { rainIntensity = function() return intensity end }
FluidType = { TaintedWater = "tainted" }
local fluid = { amount = 0 }
function fluid:setCapacity(capacity) self.capacity = capacity end
function fluid:getAmount() return self.amount end
function fluid:getFreeCapacity() return self.capacity - self.amount end
function fluid:addFluid(kind, amount)
    assert(kind == FluidType.TaintedWater and amount > 0 and amount <= self:getFreeCapacity())
    self.amount = self.amount + amount
end
ComponentType = { FluidContainer = { CreateComponent = function() return fluid end } }
GameEntityFactory = { AddComponent = function(object, _, component)
    function object:getFluidContainer() return component end
end }
dofile("tools/probes/ZedCommRainGaugeProbe/42/media/lua/server/ZedCommRainGaugeProbe.lua")
dofile(t.LUA .. "client/ZedComm/DisplayReadout.lua")
t.registry, t.java = t.start()
local tile, wireTile, displayTile = t.floorTile(20, 30), t.floorTile(21, 30), t.floorTile(22, 30)
local source = ZedCommRainGaugeProbe.place(tile)
local placed, display = t.runPlacement(displayTile, { kind = "place", item = t.give("ZedComm.AdvancedDisplay") })
assert(placed)
local laid, wire = t.lay(wireTile, t.give("ZedComm.SignalWire"), display, "signal")
assert(laid and t.registry:link(wire, source, "signal"))
local function reading()
    local byte, lit, attached, packet = t.placedReading(display)
    assert(byte == nil and attached and packet.value.unit == "L")
    assert(lit == (packet.value.amount > 0))
    return packet.value.amount
end
t.check(reading() == 0, "an empty native component publishes zero liters without a byte")
for i = 1, 15 do t.fire("EveryOneMinute") end
t.check(math.abs(reading() - 0.25) < 1e-8, "fifteen loaded full-rain game minutes fill a quarter liter")
local object = t.placement.resolve(t.registry, display).object
t.check(object:getAttachedAnimSprite() ~= nil, "volume draws numeric glyphs without a byte")
fluid.amount = 0.1875
t.check(reading() == 0.1875, "the exact amount follows an external native transfer")
local said
function t.player:Say(text) said = text end
assert(t.optionsAt(displayTile)["Read full signal"])()
t.check(said == "Display: 0.1875 L", "Read full signal reports the exact volume in liters")
local sprites, frames = object:getAttachedAnimSprite(), {}
for i = 0, sprites:size() - 1 do
    local name = sprites:get(i):getParentSprite():getName()
    frames[#frames + 1] = name:match("^zedcomm_weight_face_01_(%d+)$")
end
t.check(table.concat(frames, ",") == "36,50,60,61", "the face rounds 0.1875 L to 0.2 with its indicator on")
intensity = 0
t.fire("EveryOneMinute")
t.check(reading() == 0.1875, "shelter or dry weather yields no fill")
intensity = 1
t.loaded[t.key(20, 30, 0)] = nil
for i = 1, 120 do t.fire("EveryOneMinute") end
t.loaded[t.key(20, 30, 0)] = true
t.fire("LoadGridsquare", tile)
t.check(reading() == 0.1875, "reloading the square retains content without catching up missed rain")
for i = 1, 120 do t.fire("EveryOneMinute") end
t.check(reading() == 1, "the native capacity bounds accumulation")
t.finish()
