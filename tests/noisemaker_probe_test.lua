local probe = dofile("tools/prototypes/noisemaker.lua")
local tile = { getX = function() return 3 end, getY = function() return 4 end, getZ = function() return 0 end }
local loaded, observer = true, nil
function getCell() return { getGridSquare = function() return loaded and tile end } end
function getGameTime() return { getWorldAgeHours = function() return 8 end } end
function instanceof(obj, class) return obj.class == class end
Events = { OnThrowableExplode = {
    Add = function(handler) observer = handler end,
    Remove = function(handler) assert(observer == handler) observer = nil end,
} }
local item = { kind = "Base.NoiseTrap", getFullType = function(self) return self.kind end }
local trap = { class = "IsoTrap", getItem = function() return item end,
    index = 0, getObjectIndex = function(self) return self.index end,
    getSquare = function() return tile end, triggerExplosion = function(self) observer(self, tile) end }
local checks = 0
local function check(condition) assert(condition) checks = checks + 1 end
item.kind = "Base.NoiseTrapRemote"
check(probe.attach(trap) == nil)
item.kind = "Base.NoiseTrap"
local session = assert(probe.attach(trap))
check(not session:sample(255, false) and session.starts == 0)
check(session:sample(255, true) and session.starts == 1)
check(not session:sample(0, true) and not session:sample(nil, true))
check(session:sample(255, true) and session.starts == 2)
loaded = false
check(not session:sample(255, true) and observer == nil)
loaded = true
check(not session:sample(255, true))
session = assert(probe.attach(trap))
trap.index = -1
check(not session:sample(255, true) and observer == nil)
print(checks .. " checks, 0 failed")
