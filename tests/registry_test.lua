-- Tests for the server registry (server/ZedComm/Registry.lua), run outside
-- the game with a Lua 5.1 interpreter.
--
-- The registry derives from the game's own Lua wrapper classes, so the test
-- loads them from a local copy of the game's media/lua (never committed to
-- this repo) and stubs only the Java side beneath them: the global object
-- system, squares, world objects and Events. Without that copy it skips.
--
-- Usage: lua5.1 tests/registry_test.lua   (from the repo root)
--   PZ_LUA=/path/to/ProjectZomboid/media/lua   (required)

local LUA = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/"
local PZ = os.getenv("PZ_LUA") or "/path/to/ProjectZomboid/media/lua"

local probe = io.open(PZ .. "/server/Map/SGlobalObjectSystem.lua", "r")
if not probe then
    print("registry tests skipped: no game Lua at " .. PZ .. " (set PZ_LUA)")
    return
end
probe:close()

package.path = LUA .. "shared/?.lua;" .. LUA .. "server/?.lua;"
    .. PZ .. "/shared/?.lua;" .. PZ .. "/server/?.lua;" .. package.path

local realPrint = print -- the registry's log lines are captured below
local failures, checks = 0, 0
local function check(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        realPrint("FAIL: " .. what)
    end
end

---------------------------------------------------------------------------
-- Java stubs
---------------------------------------------------------------------------

local function list(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
    }
end

-- Squares and world objects.
local squares = {}
local loaded = {} -- key -> true when the square is "loaded"
local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function square(x, y, z)
    local k = key(x, y, z)
    if not squares[k] then
        local objects = {}
        local sq = { objects = objects }
        function sq.getX() return x end
        function sq.getY() return y end
        function sq.getZ() return z end
        function sq.getObjects() return list(objects) end
        squares[k] = sq
        loaded[k] = true
    end
    return squares[k]
end

local function worldObject(sq, tag)
    local data = { zedcomm = tag }
    local o = {}
    function o.hasModData() return true end
    function o.getModData() return data end
    function o.getSquare() return sq end
    sq.objects[#sq.objects + 1] = o
    return o
end

local function takeOff(sq, o)
    for i = #sq.objects, 1, -1 do
        if sq.objects[i] == o then table.remove(sq.objects, i) end
    end
end

function getCell()
    return {
        getGridSquare = function(_, x, y, z)
            local k = key(x, y, z)
            return loaded[k] and squares[k] or nil
        end,
    }
end

-- The Java global object system: one record per x,y,z.
local function javaSystem(saved)
    local sys = { mod = {}, objects = {}, order = {} }
    local function newGlobal(x, y, z, data)
        local g = { data = data or {} }
        function g.getModData() return g.data end
        function g.getX() return x end
        function g.getY() return y end
        function g.getZ() return z end
        sys.objects[key(x, y, z)] = g
        sys.order[#sys.order + 1] = g
        return g
    end
    function sys.getModData() return sys.mod end
    function sys.setModDataKeys(_, keys) sys.modKeys = keys end
    function sys.setObjectModDataKeys(_, keys) sys.objectKeys = keys end
    function sys.getObjectCount() return #sys.order end
    function sys.getObjectByIndex(_, i) return sys.order[i + 1] end
    function sys.newObject(_, x, y, z) return newGlobal(x, y, z) end
    function sys.getObjectAt(_, x, y, z) return sys.objects[key(x, y, z)] end
    function sys.removeObject(_, g)
        sys.objects[key(g.getX(), g.getY(), g.getZ())] = nil
        for i = #sys.order, 1, -1 do if sys.order[i] == g then table.remove(sys.order, i) end end
    end
    function sys.getObjectsInChunk(_, wx, wy)
        local out = {}
        for _, g in ipairs(sys.order) do
            if math.floor(g.getX() / 8) == wx and math.floor(g.getY() / 8) == wy then out[#out + 1] = g end
        end
        return list(out)
    end
    function sys.finishedWithList() end
    for _, rec in ipairs(saved or {}) do newGlobal(rec.x, rec.y, rec.z, rec.data) end
    return sys
end

-- "Save": keep only the declared object keys, deep-copied, as the game would.
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end
local function save(sys)
    local out = {}
    for _, g in ipairs(sys.order) do
        local data = {}
        for _, k in ipairs(sys.objectKeys or {}) do data[k] = deepCopy(g.data[k]) end
        out[#out + 1] = { x = g.getX(), y = g.getY(), z = g.getZ(), data = data }
    end
    return out
end

local nextJava = nil
SGlobalObjects = {
    registerSystem = function() return nextJava end,
    getSystemCount = function() return 0 end,
}

local handlers = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local e = { Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end }
        rawset(t, name, e)
        return e
    end,
})
local function fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end

isClient = function() return false end
isServer = function() return false end
getDebug = function() return false end
local logged = {}
print = function(msg) logged[#logged + 1] = tostring(msg) end

---------------------------------------------------------------------------
-- Load the mod as the server would
---------------------------------------------------------------------------

ZedComm = nil
require("ZedComm/Simulation")
require("ZedComm/Registry")

local function start(saved)
    nextJava = javaSystem(saved)
    SZedCommSystem.instance = nil
    fire("OnSGlobalObjectSystemInit")
    return SZedCommSystem.instance, nextJava
end

local function tileIds(sys, x, y, z)
    local g = sys:getObjectAt(x, y, z)
    if not g then return nil end
    local ids = {}
    for id in pairs(g.data.pieces or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

-- Layout: sensor S and cable c1 share square (0,0); c2 at (1,0); display D at (1,1).
local reg, java = start()
check(reg ~= nil and reg.network ~= nil, "the system starts and builds an empty network")
check(java.objectKeys and java.objectKeys[1] == "pieces", "only the pieces table is saved per square")

local sq00, sq10, sq11 = square(0, 0, 0), square(1, 0, 0), square(1, 1, 0)
local oS = worldObject(sq00, { id = "S", kind = "endpoint", role = "source" })
local oC1 = worldObject(sq00, { id = "c1", kind = "cable" })
local oC2 = worldObject(sq10, { id = "c2", kind = "cable" })
local oD = worldObject(sq11, { id = "D", kind = "endpoint", role = "sink" })
local oC9 = worldObject(sq00, { id = "c9", kind = "cable" }) -- spare, never linked
for _, o in ipairs({ oS, oC1, oC2, oD, oC9 }) do fire("OnObjectAdded", o) end

check(tileIds(java, 0, 0, 0) == "S,c1,c9", "three pieces on one square share one record")
fire("OnObjectAdded", oC1)
check(tileIds(java, 0, 0, 0) == "S,c1,c9", "adding a known object again registers nothing twice")
local clash = worldObject(sq10, { id = "S", kind = "cable" })
fire("OnObjectAdded", clash)
takeOff(sq10, clash)
check(reg.network.pieces.S.kind == "endpoint", "a clashing id is refused, not overwritten")

check(reg:link("c1", "S"), "a cable terminates on the sensor on its own square")
check(reg:link("c1", "c2"), "adjacent cables link")
check(reg:link("c2", "D"), "the run terminates on the display")
check(reg:setValue("S", 255), "the sensor value can change")
local net = reg.network
check(net:networkOf("S") == net:networkOf("D"), "sensor and display share a network")

local recS = java:getObjectAt(0, 0, 0).data.pieces.S
local recC2 = java:getObjectAt(1, 0, 0).data.pieces.c2
check(recS.ports.signal == "c1" and recS.value == 255, "the sensor's record holds its link and value")
check(recC2.links.c1 == true and recC2.links.D == "signal", "a cable's record holds both its links")

-- Save and load: the network is rebuilt from the records alone.
local saved = save(java)
local reg2, java2 = start(saved)
local net2 = reg2.network
check(net2:networkOf("S") == net2:networkOf("D"), "connectivity is derived again after load")
check(net2:recompute(net2:networkOf("D")) == 255, "the sensor value survives save and load")
for _, o in ipairs({ oS, oC1, oC2, oD, oC9 }) do fire("OnObjectAdded", o) end
local count = 0
for _ in pairs(net2.pieces) do count = count + 1 end
check(count == 5 and java2:getObjectCount() == 3, "objects reloading after the records registers nothing twice")

-- Removing one of two pieces on a square leaves the other.
takeOff(sq00, oS)
fire("OnObjectAboutToBeRemoved", oS)
check(tileIds(java2, 0, 0, 0) == "c1,c9", "removing one piece keeps the others' records, linked or not")
check(java2:getObjectAt(0, 0, 0).data.pieces.c1.links.S == nil, "the partner's record forgets the link")
check(net2:recompute(net2:networkOf("D")) == nil, "the display is disconnected once the sensor is gone")

-- A record whose world object vanished is dropped when its chunk loads.
takeOff(sq11, oD)
fire("OnObjectAdded", oS) -- unrelated: sensor placed back on (0,0)
sq00.objects[#sq00.objects + 1] = oS
reg2:OnChunkLoaded(0, 0)
check(net2.pieces.D == nil, "a piece with no world object is dropped on chunk load")
check(java2:getObjectAt(1, 1, 0) == nil, "an emptied square loses its record")
check(java2:getObjectAt(1, 0, 0).data.pieces.c2.links.D == nil, "the cable's record forgets the vanished display")
check(net2.pieces.c1 and net2.pieces.c2, "the cable run is kept")

-- An unloaded square means unavailable, not destroyed.
loaded[key(1, 0, 0)] = nil
takeOff(sq10, oC2)
reg2:OnChunkLoaded(0, 0)
check(net2.pieces.c2 ~= nil, "a record on an unloaded square is kept")
loaded[key(1, 0, 0)] = true

-- A one-sided link in a damaged save is dropped and reported on load.
local damaged = save(java2)
for _, rec in ipairs(damaged) do
    if rec.data.pieces.c1 then rec.data.pieces.c1.links.c2 = nil end
end
logged = {}
local reg3, java3 = start(damaged)
local reported = false
for _, line in ipairs(logged) do
    if string.find(line, "one-sided", 1, true) then reported = true end
end
check(reported, "a one-sided link is reported on load")
check(java3:getObjectAt(1, 0, 0).data.pieces.c2.links.c1 == nil, "the dropped link is removed from the save")
check(reg3.network:networkOf("c1") ~= reg3.network:networkOf("c2"), "the dropped link does not connect")

print = realPrint
print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
