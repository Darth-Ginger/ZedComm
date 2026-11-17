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

-- Regression: the game failed when the standard Lua next global was nil.
next = nil

local LUA = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/"
local PZ = os.getenv("PZ_LUA") or "/path/to/ProjectZomboid/media/lua"

local probe = io.open(PZ .. "/server/Map/SGlobalObjectSystem.lua", "r")
if not probe then
    print("registry tests skipped: no game Lua at " .. PZ .. " (set PZ_LUA)")
    return
end
probe:close()

package.path = LUA .. "shared/?.lua;" .. LUA .. "server/?.lua;" .. LUA .. "client/?.lua;"
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
IsoFlagType = { solid = "solid", solidtrans = "solidtrans", solidfloor = "solidfloor", WallOverlay = "WallOverlay" }
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
        function sq.getWorldObjects() return list(sq.looseItems or {}) end
        function sq.getStaticMovingObjects() return list(sq.staticActors or {}) end
        function sq.getWall(_, north)
            if north then return sq.northWall end
            return sq.westWall
        end
        function sq.getWallType()
            local south = squares[key(x, y + 1, z)]
            local east = squares[key(x + 1, y, z)]
            return (sq.northWall and 1 or 0) + (south and south.northWall and 2 or 0)
                + (sq.westWall and 4 or 0) + (east and east.westWall and 8 or 0)
        end
        function sq.getVehicleContainer() return sq.overlappingVehicle end
    function sq.isCouldSee() return true end
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
    function o.getProperties() return nil end
    function o.getName() return tag and tag.id or "ZedComm device" end
    sq.objects[#sq.objects + 1] = o
    return o
end

local function takeOff(sq, o)
    for i = #sq.objects, 1, -1 do
        if sq.objects[i] == o then table.remove(sq.objects, i) end
    end
end

local drags = {}
function getCell()
    return {
        getDrag = function(_, index) return drags[index] end,
        setDrag = function(_, drag, index)
            if triggerEvent then triggerEvent("SetDragItem", drag, index) end
            local old = drags[index]
            if old == drag then return end
            local deactivate = old and rawget(old, "deactivate")
            if deactivate then deactivate(old) end
            drags[index] = drag
        end,
        getGridSquare = function(_, x, y, z)
            local k = key(x, y, z)
            return loaded[k] and squares[k] or nil
        end,
    }
end

-- The Java global object system: one record per x,y,z.
local function javaSystem(saved)
    local sys = { mod = saved and saved.modData or {}, objects = {}, order = {} }
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

-- "Save": keep only the declared system and object keys, deep-copied as the game would.
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end
local function save(sys)
    local out = { modData = {} }
    for _, k in ipairs(sys.modKeys or {}) do out.modData[k] = deepCopy(sys.mod[k]) end
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
local Packet = ZedComm.SignalModules.Packet

local function start(saved)
    nextJava = javaSystem(deepCopy(saved))
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
local oS = worldObject(sq00, { id = "S", kind = "endpoint", definitionId = "ZedComm.DebugByteSource" })
local oC1 = worldObject(sq00, { id = "c1", kind = "cable" })
local oC2 = worldObject(sq10, { id = "c2", kind = "cable" })
local oD = worldObject(sq11, { id = "D", kind = "endpoint", definitionId = "ZedComm.NumericDisplay" })
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
check(reg.network:setPacket("S", Packet.basic(255)), "the sensor value can change")
local net = reg.network
check(net:networkOf("S") == net:networkOf("D"), "sensor and display share a network")

local recS = java:getObjectAt(0, 0, 0).data.pieces.S
local recC2 = java:getObjectAt(1, 0, 0).data.pieces.c2
check(recS.ports.signal == "c1" and recS.value == nil and recS.packet == nil, "the sensor record holds its link without a live packet")
check(recC2.links.c1 == true and recC2.links.D == "signal", "a cable's record holds both its links")

-- Save and load: the network is rebuilt from the records alone.
local saved = save(java)
local reg2, java2 = start(saved)
local net2 = reg2.network
check(net2:networkOf("S") == net2:networkOf("D"), "connectivity is derived again after load")
check(net2:recompute(net2:networkOf("D")) == nil, "reload waits for the source to publish")
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

-- Defined endpoints are saved through the same record path.
local defined, definedJava = start()
local sensorSquare, displaySquare = square(20, 20, 0), square(21, 20, 0)
local seed = { calibration = { threshold = 10 }, enabled = false }
local sensor = worldObject(sensorSquare, {
    id = "sensor", kind = "endpoint", definitionId = "ZedComm.PressureSensor", state = seed,
})
local cable = worldObject(sensorSquare, { id = "wire", kind = "cable" })
local display = worldObject(displaySquare, {
    id = "display", kind = "endpoint", definitionId = "ZedComm.NumericDisplay",
})
for _, object in ipairs({ sensor, cable, display }) do fire("OnObjectAdded", object) end
local function savedPiece(system, x, id)
    return system:getObjectAt(x, 20, 0).data.pieces[id]
end
local sensorRecord = savedPiece(definedJava, 20, "sensor")
local displayRecord = savedPiece(definedJava, 21, "display")
check(sensorRecord.definitionId == "ZedComm.PressureSensor" and sensorRecord.role == "source",
    "source definition supplies the saved identity and role")
check(displayRecord.definitionId == "ZedComm.NumericDisplay" and displayRecord.role == "sink",
    "receiver definition maps to the model sink role")
check(sensorRecord.ports.signal == false and displayRecord.ports.signal == false,
    "both endpoints start with the registered signal port")
seed.calibration.threshold = 99
check(defined.network:record("sensor").state.calibration.threshold == 10,
    "seed state is copied into the model")
local changed = { calibration = { threshold = 14 }, enabled = false, [1] = "armed" }
check(defined:setDeviceState("sensor", changed), "state update goes through the registry")
changed.calibration.threshold = 99
local exported = defined.network:record("sensor")
exported.state.calibration.threshold = 99
check(savedPiece(definedJava, 20, "sensor").state.calibration.threshold == 14
    and defined.network:record("sensor").state.calibration.threshold == 14,
    "saved state and returned records do not alias callers")
local cyclic = {}
cyclic.self = cyclic
check(not defined:setDeviceState("sensor", cyclic), "cyclic state is rejected")
check(not defined:setDeviceState("sensor", { callback = function() end }), "callback state is rejected")
check(not defined:setDeviceState("sensor", { value = math.huge }), "nonfinite state is rejected")
check(not defined:setDeviceState("sensor", { [true] = 1 }), "unsupported state keys are rejected")
check(savedPiece(definedJava, 20, "sensor").state.calibration.threshold == 14,
    "failed updates leave the saved state unchanged")
check(defined:link("wire", "sensor") and defined:link("wire", "display"),
    "old-format cable links to defined endpoints")
check(defined.network:setPacket("sensor", Packet.basic(90)), "defined source can publish a byte")

local definedSave = save(definedJava)
local loadedRegistry, loadedJava = start(definedSave)
for _, object in ipairs({ sensor, cable, display, sensor }) do fire("OnObjectAdded", object) end
local loadedRecord = savedPiece(loadedJava, 20, "sensor")
check(loadedRecord.definitionId == "ZedComm.PressureSensor"
    and loadedRecord.state.calibration.threshold == 14
    and loadedRecord.state.enabled == false and loadedRecord.state[1] == "armed",
    "identity and nested durable state round-trip and override old tag seed")
check(tileIds(loadedJava, 20, 20, 0) == "sensor,wire" and loadedJava:getObjectCount() == 2,
    "replayed object hooks do not duplicate pieces")
check(loadedRegistry.network:networkOf("sensor") == loadedRegistry.network:networkOf("display")
    and loadedRegistry.network:recompute(loadedRegistry.network:networkOf("display")) == nil,
    "cable links round-trip and packets await live sampling")

-- Simulate two definitions being absent during a load/save cycle.
for _, tile in ipairs(definedSave) do
    local pieces = tile.data.pieces
    if pieces.sensor then pieces.sensor.definitionId = "Example.Sensor" end
    if pieces.display then pieces.display.definitionId = "Example.Display" end
end
logged = {}
local missing, missingJava = start(definedSave)
local missingId = missing.network:networkOf("sensor")
check(missingId == missing.network:networkOf("display"), "missing definitions keep saved topology")
check(missing.network:recompute(missingId) == nil, "missing sender cannot replay a stale byte")
check(#missing.network:sinksOf(missingId) == 0, "missing receiver is excluded from delivery")
check(not missing.network:setPacket("sensor", Packet.basic(100)), "missing sender rejects value updates")
local preserved = savedPiece(missingJava, 20, "sensor")
check(preserved.definitionId == "Example.Sensor" and preserved.state.calibration.threshold == 14
    and preserved.ports.signal == "wire" and preserved.definitionUnavailable == nil,
    "missing source record preserves state and links without a persistent unavailable flag")
local reports = 0
for _, line in ipairs(logged) do
    if string.find(line, "record preserved", 1, true) then reports = reports + 1 end
end
check(reports == 2, "missing definitions are reported once each on load")
local missingSave = save(missingJava)
local definitions = ZedComm.DeviceDefinitions
check(definitions.register({
    id = "Example.Sensor", role = "source", ports = { "signal" },
    match = function() return false end, sample = function() return 90 end,
}), "restored sender definition registers")
check(definitions.register({
    id = "Example.Display", role = "receiver", ports = { "signal" },
    match = function() return false end, receiverModule = ZedComm.SignalModules.ON_OFF,
    bindFixture = function() return { apply = function() return "applied" end } end,
}), "restored receiver definition registers")
local recovered, recoveredJava = start(missingSave)
local recoveredId = recovered.network:networkOf("sensor")
check(recovered.network:recompute(recoveredId) == nil and recovered.network:sinksOf(recoveredId)[1] == "display",
    "reinstalling definitions restores the existing source and receiver links")
check(savedPiece(recoveredJava, 20, "sensor").state.calibration.threshold == 14,
    "reinstalling the definition recovers durable state")
check(recovered:setDeviceState("sensor", nil) and savedPiece(recoveredJava, 20, "sensor").state == nil,
    "explicit nil clears durable state")

-- Run the actual tick handler with the native device definitions and world stubs.
local runtimeRegistry, runtimeJava = start()
local actors = {}
function sensorSquare.getMovingObjects() return list(actors) end
instanceof = function(object, class)
    return object.class == class or (class == "IsoPlayer" and object.class == "IsoAnimal")
end
for _, object in ipairs({ sensor, cable, display }) do fire("OnObjectAdded", object) end
assert(runtimeRegistry:link("wire", "sensor"))
assert(runtimeRegistry:link("wire", "display"))
require "ZedComm/SimulationRunner"
local runtime = ZedComm.DeviceRuntime
local simulation = ZedComm.Simulation
local function expectReading(value, lit, present, message)
    fire("OnTick")
    local got, on, connected = runtime.getDisplay(display)
    check(got == value and on == lit and connected == present, message)
end

check(#handlers.OnTick == 1, "runtime uses the single simulation tick handler")
expectReading(0, false, true, "empty sensor delivers valid zero on the first tick")
actors = { { class = "BaseVehicle" } }
expectReading(0, false, true, "an unrelated moving object does not activate the sensor")
actors = { { class = "IsoPlayer" } }
expectReading(1, true, true, "player activates the display in the same tick")
local processed = simulation.processed
expectReading(1, true, true, "held input keeps the display on")
check(simulation.processed == processed, "held input schedules no duplicate recompute")
actors = {}
expectReading(0, false, true, "leaving the square updates the display to zero")
actors = { { class = "IsoZombie" } }
expectReading(1, true, true, "zombie activates the display")

assert(runtimeRegistry:unlink("wire", "sensor"))
expectReading(nil, false, true, "cutting source leaves display attached with no signal")
assert(runtimeRegistry:link("wire", "sensor"))
expectReading(1, true, true, "reconnecting restores the same held value")
assert(runtimeRegistry:unlink("wire", "display"))
expectReading(nil, false, false, "detached display has no runtime reading")
assert(runtimeRegistry:link("wire", "display"))
expectReading(1, true, true, "reattached display reads the current source")

loaded[key(20, 20, 0)] = nil
expectReading(nil, false, true, "unloaded source fails off without replaying its saved byte")
loaded[key(20, 20, 0)] = true
expectReading(1, true, true, "source returning with the same byte restores the signal")
loaded[key(21, 20, 0)] = nil
expectReading(nil, false, false, "unloaded receiver loses its transient reading")
loaded[key(21, 20, 0)] = true
expectReading(1, true, true, "loaded receiver reconciles even with a quiet source")

local runtimeSave = save(runtimeJava)
runtimeRegistry, runtimeJava = start(runtimeSave)
actors = {}
expectReading(0, false, true, "reload samples live occupancy before delivering the saved high byte")
processed = simulation.processed
expectReading(0, false, true, "reload maintains a stable reading")
check(simulation.processed == processed and #handlers.OnTick == 1,
    "reloaded registry does not add subscriptions or repeatedly dirty the circuit")

-- A broken extension callback is isolated and drives no signal.
local broken = {
    id = "Example.BrokenSource", role = "source", ports = { "signal" },
    match = function() return false end,
    sample = function() error("test callback failure") end,
}
assert(definitions.register(broken))
local brokenSensor = worldObject(sensorSquare, {
    id = "broken", kind = "endpoint", definitionId = broken.id, value = 255,
})
fire("OnObjectAdded", brokenSensor)
assert(runtimeRegistry:unlink("wire", "sensor"))
assert(runtimeRegistry:link("wire", "broken"))
expectReading(nil, false, true, "sample exception fails off without breaking the game tick")

-- Exercise inventory-backed placement against the same registry and tick.
require "ZedComm/PlayerPlacement"
local placement = ZedComm.PlayerPlacement
local worldTime = 1000
getTimestampMs = function() return worldTime end
local registeredSprites = {}
getSprite = function(name)
    local index = tonumber(string.match(name, "^zedcomm_devices_01_(%d+)$"))
    local displayIndex = tonumber(string.match(name, "^zedcomm_display_01_(%d+)$"))
    local switchIndex = tonumber(string.match(name, "^zedcomm_switch_01_(%d+)$"))
    if (index and index <= 474) or (displayIndex and displayIndex < 257) or (switchIndex and switchIndex < 40) then
        if not registeredSprites[name] then
            registeredSprites[name] = { getName = function() return name end }
        end
        return registeredSprites[name]
    end
end
triggerEvent = fire
ColorInfo = {
    new = function() return { setABGR = function(self, packed) self.packed = packed end } end,
}
IsoObject = {
    new = function(tile, sprite)
        local object = worldObject(tile, nil)
        takeOff(tile, object)
        object.sprite = sprite
        function object.getSprite()
            local current = object.spriteInstance
            if current and current:getName() == object.sprite then return current end
            return getSprite(object.sprite)
        end
        function object.setSprite(_, sprite)
            object.sprite, object.spriteInstance = sprite:getName(), sprite
        end
        function object.getAttachedAnimSprite() return nil end
        object.outlineColors = {}
        object.outlined = {}
        function object.getOutlineHighlightCol(_, index) return object.outlineColors[index] or -1 end
        function object.setOutlineHighlightCol(_, index, r, g, b, a)
            if type(r) == "table" then
                object.outlineColors[index] = assert(r.packed)
            else
                object.outlineColors[index] = math.floor(r * 255) + math.floor(g * 255) * 256
                    + math.floor(b * 255) * 65536 + math.floor(a * 255) * 16777216
            end
        end
        function object.isOutlineHighlight(_, index) return object.outlined[index] == true end
        function object.setOutlineHighlight(_, index, enabled) object.outlined[index] = enabled end
        return object
    end,
}

local function floorTile(x, y)
    local tile = square(x, y, 0)
    function tile.TreatAsSolidFloor() return true end
    function tile.isSolid() return false end
    function tile.isSolidTrans() return false end
    function tile.isBlockedTo(_, other) return tile.blocked == other end
    function tile.getMovingObjects() return list(tile.actors or {}) end
    function tile.AddTileObject(_, object) tile.objects[#tile.objects + 1] = object end
    function tile.transmitRemoveItemFromSquare(_, object)
        if tile.refuseRemoval then return end
        fire("OnObjectAboutToBeRemoved", object)
        takeOff(tile, object)
    end
    return tile
end

local carried = {}
local inventory = {}
function inventory.getItems() return list(carried) end
function inventory.getFirstType(_, fullType)
    for _, item in ipairs(carried) do
        if item:getFullType() == fullType then return item end
    end
end
function inventory.contains(_, item) return item.container == inventory end
function inventory.hasRoomFor() return not inventory.full end
function inventory.AddItem(_, item)
    carried[#carried + 1] = item
    item.container = inventory
    return item
end
function inventory.Remove(_, item)
    for i = #carried, 1, -1 do
        if carried[i] == item then
            table.remove(carried, i)
            item.container = nil
            return
        end
    end
end
instanceItem = function(itemType)
    local item = { data = {} }
    function item.getFullType() return itemType end
    function item.getName() return itemType end
    function item.getContainer() return item.container end
    function item.getModData() return item.data end
    function item:getCurrentUsesFloat() return self.charge or 1 end
    function item:setUsedDelta(charge) self.charge = charge end
    return item
end
local player = { tile = nil }
function player.getInventory() return inventory end
function player.getPlayerNum() return 0 end
function player.isBuildButtonDown() return false end
function player.isBuildButtonReleased() return player.buildReleased == true end
function player.getCurrentSquare() return player.tile end
function player.isTimedActionInstant() return true end
function player.Say() end
getSpecificPlayer = function() return player end
local function give(itemType) return inventory:AddItem(instanceItem(itemType)) end
local p0, w0, w1, d0 = floorTile(40, 40), floorTile(41, 40), floorTile(41, 41), floorTile(42, 41)
local far = floorTile(46, 40)
local playerRegistry, playerJava = start()

local function runPlacement(tile, command, from)
    command.square, command.network = tile, playerRegistry.network
    player.tile = from or tile
    return placement.perform(player, command)
end
local function target(tile, id, kind, fields)
    local entry = assert(placement.resolve(playerRegistry, id))
    local command = fields or {}
    command.kind, command.targetId, command.object = kind, id, entry.object
    return runPlacement(tile, command)
end
local function placedReading(id)
    fire("OnTick")
    return runtime.getDisplay(placement.resolve(playerRegistry, id).object)
end

local otherPlate = give("ZedComm.PressurePlate")
local plate = give("ZedComm.PressurePlate")
plate.data.zedcommPlacement = { id = "test-pressure-id", state = { configured = 11 } }
local displayItem = give("ZedComm.NumericDisplay")
local wireA, wireB = give("ZedComm.SignalWire"), give("ZedComm.SignalWire")
local ok, plateId = runPlacement(p0, { kind = "place", item = plate })
check(ok and plateId == "test-pressure-id" and not inventory:contains(plate)
    and inventory:contains(otherPlate), "placement consumes the exact selected item and keeps its identity")
check(playerRegistry.network:record(plateId).state.configured == 11, "placement restores carried configuration")
check(placement.resolve(playerRegistry, plateId).object.sprite == "zedcomm_devices_01_20",
    "placed pressure plate uses its packaged sprite")
local placed, displayId = runPlacement(d0, { kind = "place", item = displayItem })
check(placed and placement.resolve(playerRegistry, displayId).object.sprite == "zedcomm_devices_01_431",
    "placed display uses its packaged sprite")
check(not runPlacement(p0, { kind = "place", item = otherPlate }) and inventory:contains(otherPlate),
    "occupied endpoint tile rejects a second device without consuming it")
check(not runPlacement(far, { kind = "place", item = otherPlate }, p0) and #far.objects == 0,
    "out-of-reach placement leaves the tile unchanged")
check(not runPlacement(far, { kind = "lay", item = wireA, anchorId = plateId, anchorPort = "signal" })
    and inventory:contains(wireA), "wire cannot skip a tile")
p0.blocked = w0
check(not runPlacement(w0, { kind = "lay", item = wireA, anchorId = plateId, anchorPort = "signal" })
    and inventory:contains(wireA), "wire cannot cross a blocked edge")
p0.blocked = nil

local function lay(tile, item, id, port)
    return runPlacement(tile, { kind = "lay", item = item, anchorId = id, anchorPort = port })
end
local function join(tile, first, firstPort, second, secondPort)
    return target(tile, second, "join", { anchorId = first, anchorPort = firstPort, port = secondPort })
end
local registryLink = playerRegistry.link
playerRegistry.link = function() return false, "injected link refusal" end
check(not lay(w0, wireA, plateId, "signal") and inventory:contains(wireA)
    and #w0.objects == 0 and playerRegistry.network.pieces[plateId].ports.signal == false,
    "refused link rolls back the new tile and leaves inventory unchanged")
playerRegistry.link = registryLink

local laid, firstWire = lay(w0, wireA, plateId, "signal")
check(laid and not inventory:contains(wireA) and playerRegistry.network.pieces[plateId].ports.signal == firstWire,
    "first wire consumes one unit and explicitly connects to the plate")
local bent, secondWire = lay(w1, wireB, firstWire, false)
check(bent and not inventory:contains(wireB)
    and placement.resolve(playerRegistry, secondWire).object.sprite == "zedcomm_devices_01_1",
    "bending the route consumes one more unit and uses the packaged wire sprite")
check(#placement.freePorts(placement.resolve(playerRegistry, secondWire)) == 1,
    "a partial run leaves one selectable free end")
check(playerRegistry.network.pieces[displayId].ports.signal == false,
    "a wire beside the display stays disconnected until explicitly joined")
check(join(d0, secondWire, false, displayId, "signal"), "finishing the run connects the destination")
check(placedReading(displayId) == 0, "player-built circuit carries valid zero")
p0.actors = { { class = "IsoPlayer" } }
check(placedReading(displayId) == 1, "player-built circuit carries the default of 1 when occupied")
for _, invalid in ipairs({ "", "oops", "-1", "0", "256", "7.5" }) do
    check(not runtime.setPressureOutput(playerRegistry, plateId, invalid), "reject invalid occupied output " .. invalid)
end
check(placedReading(displayId) == 1, "invalid output leaves the occupied signal unchanged")
check(runtime.setPressureOutput(playerRegistry, plateId, "255") and placedReading(displayId) == 255,
    "changing to the maximum updates the circuit while the plate is held")
p0.actors = {}
check(placedReading(displayId) == 0, "a configured plate still sends zero when empty")
p0.actors = { { class = "IsoPlayer" } }

inventory.full = true
check(not target(w0, firstWire, "pickup") and playerRegistry.network.pieces[firstWire],
    "full inventory prevents pickup and leaves wiring intact")
inventory.full = false
w0.refuseRemoval = true
local beforePickup = #carried
check(not target(w0, firstWire, "pickup") and #carried == beforePickup
    and playerRegistry.network.pieces[firstWire], "failed world removal rolls back the recovered item")
w0.refuseRemoval = false
check(target(w0, firstWire, "pickup"), "pickup recovers a wire unit")
local recoveredWire = carried[#carried]
check(recoveredWire:getFullType() == "ZedComm.SignalWire" and #w0.objects == 0
    and playerRegistry.network.pieces[secondWire], "cut removes only the selected segment")
local value, _, connected = placedReading(displayId)
check(value == nil and connected, "cut leaves the display attached with no signal")
local repaired, replacement = lay(w0, recoveredWire, plateId, "signal")
check(repaired and join(w1, replacement, false, secondWire, false) and placedReading(displayId) == 255,
    "replacing the cut segment and joining the free ends repairs the run")

assert(playerRegistry:setDeviceState(plateId, { label = "North plate" }))
check(runtime.setPressureOutput(playerRegistry, plateId, "27")
    and playerRegistry.network:record(plateId).state.label == "North plate",
    "setting the occupied output preserves other device state")
check(target(p0, plateId, "pickup"), "device pickup succeeds with a cable attached")
local recoveredPlate = carried[#carried]
check(recoveredPlate.data.zedcommPlacement.id == plateId
    and recoveredPlate.data.zedcommPlacement.state.occupiedOutput == 27
    and recoveredPlate.data.zedcommPlacement.links == nil
    and #placement.freePorts(placement.resolve(playerRegistry, replacement)) == 1,
    "pickup retains identity and durable state but leaves the cable with a free end")
local replaced, idAgain = runPlacement(p0, { kind = "place", item = recoveredPlate })
check(replaced and idAgain == plateId and playerRegistry.network:record(idAgain).state.occupiedOutput == 27
    and playerRegistry.network.pieces[idAgain].ports.signal == false,
    "replacing restores the same configured device with a disconnected port")
check(join(p0, replacement, false, plateId, "signal") and placedReading(displayId) == 27,
    "device can reconnect to the original wire after replacement")

local worldSave = save(playerJava)
local previousNetwork = playerRegistry.network
playerRegistry, playerJava = start(worldSave)
check(playerRegistry.network:record(plateId).state.occupiedOutput == 27 and placedReading(displayId) == 27,
    "player-built rig and state survive reload")
check(not placement.perform(player, { kind = "place", network = previousNetwork, square = far, item = otherPlate })
    and inventory:contains(otherPlate), "queued action cannot mutate a different loaded registry")

-- Verify the context menu calls the real timed-action and placement entry points.
local queued, queuedWalk
package.loaded["TimedActions/ISInventoryTransferUtil"] = true
package.loaded["TimedActions/ISBaseTimedAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
ISBaseTimedAction = {}
function ISBaseTimedAction:derive()
    local class = {}
    class.__index = class
    return class
end
function ISBaseTimedAction.new(class, character)
    return setmetatable({ character = character }, class)
end
local testQueue = { indexOf = function(_, action)
    if action == queuedWalk then return 1 end
    return action == queued and 2 or -1
end }
ISTimedActionQueue = {
    add = function(action)
        if action.location then queuedWalk = action else queued = action end
    end,
    getTimedActionQueue = function() return testQueue end,
}
local function menu()
    return {
        player = 0,
        options = {},
        children = {},
        entries = {},
        isVisible = function(self) return self.visible ~= false end,
        addOption = function(self, label, object, callback, ...)
            local params = { ... }
            if callback then self.options[label] = function() return callback(object, unpack(params)) end end
            local entry = { label = label }
            self.entries[label] = entry
            return entry
        end,
        addSubMenu = function(self, option, submenu)
            self.children[option.label] = submenu
        end,
    }
end
ISContextMenu = { getNew = menu }
dofile(LUA .. "client/ZedComm/PlacementMenu.lua")
local function menuAt(tile)
    player.tile = tile
    getCell():setDrag(nil, 0)
    local contextMenu = menu()
    fire("OnFillWorldObjectContextMenu", 0, contextMenu, { { getSquare = function() return tile end } }, false)
    return contextMenu.children.ZedComm or menu()
end
local function optionsAt(tile)
    return menuAt(tile).options
end
local opts = optionsAt(far)
assert(opts["Place pressure plate"])()
check(queued and queued:isValid() and queued:complete() and not inventory:contains(otherPlate),
    "normal context menu completes timed placement from an exact inventory item")
local spare = give("ZedComm.SignalWire")
local nextTile = floorTile(47, 40)
opts = optionsAt(far)
assert(opts["Select pressure plate free end"])()
opts = optionsAt(nextTile)
check(ISBuildingObject == nil and opts["Lay wire here"] and not getCell():getDrag(0),
    "the ZedComm menu works before the native cursor class loads")
assert(opts["Lay wire here"])()
assert(opts["Pause wire run"])()
check(not queued:isValid() and not queued:complete() and inventory:contains(spare)
    and #nextTile.objects == 0, "pausing the run cancels a queued wire placement")

-- The game loads the server building scripts after the client menu.
require "BuildingObjects/ISBuildingObject"
dofile(PZ .. "/client/TimedActions/WalkToTimedAction.lua")

-- Exercise the cursor via the installed game's tile-building event.
do
    local origin, east, corner = floorTile(55, 50), floorTile(56, 50), floorTile(56, 51)
    local endTile, distant = floorTile(57, 51), floorTile(58, 51)
    local cancelTile = floorTile(56, 52)
    local ok, sourceId = runPlacement(origin, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(ok, sourceId)
    local placed, displayId = runPlacement(endTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(placed, displayId)
    local old = IsoObject.new(east, "zedcomm_devices_01_1")
    old:getModData().zedcomm = { id = "cursor-existing-wire", kind = "cable", placedItem = "ZedComm.SignalWire" }
    east:AddTileObject(old)
    fire("OnObjectAdded", old)
    for _ = 1, 3 do give("ZedComm.SignalWire") end

    local floorColor = { getR = function() return 0 end, getG = function() return 1 end,
        getB = function() return 0 end }
    local originalGetCore, originalJoypad, originalSprite = getCore, JoypadState, IsoSprite
    local preview, invalidOutline
    local originalRenderRect = renderIsoRect
    renderIsoRect = function(x, y, z, radius, r, g, b, a, width)
        preview = { x - 1, y - 1 }
        invalidOutline = { x = x, y = y, z = z, radius = radius, r = r, g = g, b = b, a = a, width = width }
    end
    JoypadState = { players = {} }
    IsoSprite = { new = function()
        return { LoadSingleTexture = function() end, RenderGhostTileColor = function(_, x, y) preview = { x, y } end }
    end }
    getCore = function() return {
        getGoodHighlitedColor = function() return floorColor end,
        getBadHighlitedColor = function() return floorColor end,
    } end

    assert(optionsAt(origin)["Select pressure plate free end"])()
    local cursor = assert(getCell():getDrag(0))
    local function click(tile)
        local x, y, z = tile:getX(), tile:getY(), tile:getZ()
        fire("OnDoTileBuilding2", cursor, true, x, y, z, tile)
        player.buildReleased = true
        fire("OnDoTileBuilding2", cursor, false, x, y, z, tile)
        player.buildReleased = false
    end

    local function finishWalk()
        local walking = queuedWalk
        queuedWalk = nil
        if walking then walking.onCompleteFunc() end
    end

    local function arrive()
        if queuedWalk then player.tile = queuedWalk.location end
        finishWalk()
        return queued
    end

    local choice
    ISInventoryPane = { getActualItems = function(items) return items end }
    ISContextMenu.get = function() choice = menu(); return choice end
    getMouseX, getMouseY = function() return 0 end, function() return 0 end

    click(distant)
    check(preview[1] == 58 and preview[2] == 51 and not cursor.canBeBuild
        and playerRegistry.network.pieces[sourceId].ports.signal == false,
        "the native cursor previews a remote tile as unavailable")
    click(east)
    check(choice and choice.options["Connect to wire 1 / Loose wire"] and choice.options["Lay wire here"],
        "an active endpoint end can join a compatible cable or lay a new one")
    choice.options["Lay wire here"]()
    local priorAction, walking = queued, queuedWalk
    click(east)
    check(priorAction == queued and walking == queuedWalk and walking.location == east
        and arrive():isValid() and queued:complete(), "one click queues one native walk followed by one linked wire")
    local first = playerRegistry.network.pieces[sourceId].ports.signal
    check(first ~= "cursor-existing-wire" and playerRegistry.network:networkOf(first)
        ~= playerRegistry.network:networkOf("cursor-existing-wire"), "clicking a shared tile lays a separate linked wire")

    player.tile = east
    click(corner)
    local cleared = queuedWalk
    queued, queuedWalk = nil, nil
    click(corner)
    check(queuedWalk and queuedWalk ~= cleared and arrive():isValid() and queued:complete(),
        "clearing the native action queue allows the next click to retry")
    local second
    for id, port in pairs(playerRegistry.network.pieces[first].links) do
        if port == true then second = id end
    end
    check(second ~= nil and getCell():getDrag(0) == cursor, "placing a bend advances the anchor and keeps the cursor")

    player.tile = corner
    click(cancelTile)
    local cancelled, cancelledWalk = queued, queuedWalk
    local connect = optionsAt(endTile)["Connect wire to numeric display"]
    finishWalk()
    check(getCell():getDrag(0) == nil and cancelledWalk.additionalTest()
        and queued == cancelled and connect ~= nil,
        "right-click cancels the walk without queuing placement and keeps the end available to join")
    connect()
    check(queued:isValid() and queued:complete()
        and playerRegistry.network.pieces[displayId].ports.signal == second, "the explicit join uses the last placed wire")

    assert(playerRegistry:unlink(second, displayId))
    assert(optionsAt(corner)["Select wire free end"])()
    cursor = assert(getCell():getDrag(0))
    click(cancelTile)
    local abandoned = queuedWalk
    queuedWalk = nil
    player.tile = distant
    fire("OnTick")
    check(getCell():getDrag(0) == nil and abandoned.additionalTest(),
        "walking out of reach cancels the cursor and its uncommitted placement")

    local function openInventory(item)
        local context = menu()
        fire("OnFillInventoryObjectContextMenu", 0, context, { item })
        assert(context.options["Place with ZedComm cursor"])()
        cursor = assert(getCell():getDrag(0))
        queued, queuedWalk, choice = nil, nil, nil
    end

    local remote = floorTile(64, 52)
    local plateItem = give("ZedComm.PressurePlate")
    local otherPlate = give("ZedComm.PressurePlate")
    openInventory(plateItem)
    click(remote)
    check(queuedWalk and queuedWalk.location == remote and not queued,
        "inventory endpoint queues a walk to the clicked floor before placement")
    check(arrive():isValid() and queued:complete() and not inventory:contains(plateItem)
        and inventory:contains(otherPlate) and getCell():getDrag(0) == nil,
        "arrival places exactly the selected endpoint and closes its cursor")
    local plateOnRemote = placement.piecesAt(playerRegistry, remote)[1]
    assert(plateOnRemote and plateOnRemote.piece.definitionId == "ZedComm.PressureSensor")

    openInventory(otherPlate)
    click(remote)
    check(not queued and not queuedWalk and inventory:contains(otherPlate), "the cursor rejects a second endpoint on a tile")
    local secondDeviceTile = floorTile(64, 53)
    click(secondDeviceTile)
    getCell():setDrag(nil, 0)
    local cancelledPlacement = queuedWalk
    finishWalk()
    check(cancelledPlacement.additionalTest() and not queued and inventory:contains(otherPlate),
        "cancelled inventory placement retains the exact item")

    openInventory(otherPlate)
    click(secondDeviceTile)
    local removedItem = queuedWalk
    inventory:Remove(otherPlate)
    arrive()
    check(removedItem and not queued and #secondDeviceTile.objects == 0,
        "arrival revalidates the exact inventory item before queuing placement")

    local looseTile = floorTile(65, 52)
    local looseItem = give("ZedComm.SignalWire")
    openInventory(looseItem)
    player.tile = origin
    click(looseTile)
    check(queuedWalk and queuedWalk.location == looseTile and arrive():complete()
        and not inventory:contains(looseItem) and getCell():getDrag(0) == nil,
        "loose wire walks to and places on a remote clear tile")
    local loose = placement.piecesAt(playerRegistry, looseTile)[1]
    check(loose and #playerRegistry.network:partners(loose.id) == 0,
        "loose placement does not join an adjacent free device")

    local pickedWire = give("ZedComm.SignalWire")
    openInventory(pickedWire)
    click(remote)
    check(choice and choice.options["Place wire loose"] and choice.options["Connect to pressure plate"]
        and not queued and not queuedWalk, "clicking a device free end offers both explicit choices")
    choice.options["Connect to pressure plate"]()
    check(arrive():complete() and plateOnRemote.piece.ports.signal
        and not inventory:contains(pickedWire) and getCell():getDrag(0) == cursor,
        "place and connect uses the selected item and starts a linked run")

    local extraWire = give("ZedComm.SignalWire")
    openInventory(extraWire)
    click(looseTile)
    check(choice and choice.options["Place wire loose"] and choice.options["Connect to wire 1 / Loose wire from an adjacent tile"],
        "clicking an existing cable offers loose placement and an adjacent extension")
    choice.options["Place wire loose"]()
    assert(arrive():complete())
    local shared = placement.piecesAt(playerRegistry, looseTile)
    table.sort(shared, function(a, b) return a.id < b.id end)
    check(#shared == 2 and playerRegistry.network:networkOf(shared[1].id)
        ~= playerRegistry.network:networkOf(shared[2].id), "choosing loose on an occupied tile keeps both runs independent")

    local linkedItem = give("ZedComm.SignalWire")
    local extensionTile = floorTile(66, 52)
    local invalidExtension = floorTile(67, 52)
    player.tile = origin
    openInventory(linkedItem)
    click(looseTile)
    assert(choice.options["Connect to wire 2 / Loose wire from an adjacent tile"])()
    click(invalidExtension)
    check(not queued and not queuedWalk and inventory:contains(linkedItem),
        "choosing a free cable end refuses a target beyond the neighboring tile")
    click(extensionTile)
    local walk = queuedWalk
    fire("OnTick")
    check(walk and walk.location == extensionTile and getCell():getDrag(0) == cursor,
        "a native walk to a valid extension can approach a selected cable from far away")
    assert(arrive():complete())
    local extension = placement.piecesAt(playerRegistry, extensionTile)[1]
    check(extension and extension.piece.links[shared[2].id] == true
        and not extension.piece.links[shared[1].id] and not inventory:contains(linkedItem),
        "the first placed wire attaches only to the chosen cable on a shared tile")
    getCell():setDrag(nil, 0)
    local function testNativeBridge()
        dofile(LUA .. "client/ZedComm/NativePlacement.lua")
        local originalText, originalRadial, originalKeybind = getText, getPlayerRadialMenu, KeybindId
        local originalFlagType = IsoFlagType
        IsoFlagType = { WindowN = "WindowN" }
        getText = function(key) return key end
        getPlayerRadialMenu = function() return nil end
        KeybindId = { ROTATE_BUILDING = 1 }
        local gameCore = getCore
        getCore = function()
            local core = gameCore()
            core.isKey = function() return false end
            return core
        end
        player.getPrimaryHandItem = function() return nil end
        player.getSecondaryHandItem = function() return nil end
        player.getCharacterActions = function() return { isEmpty = function() return true end } end
        player.isSittingOnFurniture = function() return false end
        player.faceLocation = function() end
        inventory.getItemById = function(_, id)
            for _, item in ipairs(carried) do if item:getID() == id then return item end end
        end

        local itemId = 0
        local function addId(item)
            if item.getID then return end
            itemId = itemId + 1
            local id = itemId
            function item.getID() return id end
        end
        local realAddItem = inventory.AddItem
        inventory.AddItem = function(self, item)
            addId(item)
            return realAddItem(self, item)
        end
        for _, item in ipairs(carried) do addId(item) end

        local spriteProperties = { has = function() return false end }
        ISMoveableSpriteProps = {
            invalidColor = { r = 1, g = 0, b = 0 },
            new = function(sprite)
                return {
                    sprite = sprite, spriteProps = spriteProperties,
                    spriteName = type(sprite) == "string" and sprite or sprite:getName(),
                    isMoveable = sprite == "vanilla-furniture",
                    hasFaces = function() return false end,
                    getYOffsetCursor = function() return 0 end,
                    canPlaceMoveable = function() return true end,
                }
            end,
            addLineToInfoTable = function(lines, name)
                lines[#lines + 1] = name
                return lines
            end,
        }
        dofile(PZ .. "/server/BuildingObjects/ISMoveableCursor.lua")
        local vanillaClicks = 0
        ISMoveableCursor.tryBuild = function() vanillaClicks = vanillaClicks + 1 end
        ISMoveableCursor.render = function() end
        ISMoveableCursor.setMoveableMode = function(self, mode) ISMoveableCursor.mode[self.player] = mode end
        fire("OnGameStart")
        fire("OnGameStart")

        local vanilla = give("Base.TestMoveable")
        vanilla.class = "Moveable"
        function vanilla.getWorldSprite() return "vanilla-furniture" end

        local native = setmetatable({ player = 0, character = player, objectIndex = 1 }, ISMoveableCursor)
        ISMoveableCursor.__index = ISMoveableCursor
        native:init()
        native.setInfoPanel = function() end
        native.rotateMouse = function() end
        native:setMoveableMode("place")
        getCell():setDrag(native, 0)
        cursor = native

        local function selectNative(tile, matches)
            for _ = 1, 25 do
                native:isValid(tile)
                local entry = native.objectListCache[native.objectIndex]
                if entry and matches(entry) then return entry end
                native:rotateKey(0, true)
            end
            error("Native cycle did not offer the expected item")
        end
        local function selectType(tile, fullType)
            return selectNative(tile, function(entry) return entry.object:getFullType() == fullType end)
        end
        local nativePlateTile, nativeDisplayTile = floorTile(60, 53), floorTile(61, 55)
        local relocatedPlateTile, nextWireTile = floorTile(60, 54), floorTile(60, 55)
        local clearWireTile, skippedWireTile = floorTile(58, 54), floorTile(58, 56)
        player.tile = origin
        give("ZedComm.PressurePlate")
        give("ZedComm.NumericDisplay")
        for _ = 1, 4 do give("ZedComm.SignalWire") end

        check(selectType(nativePlateTile, "Base.TestMoveable").object == vanilla and native.canCreate,
            "native cycling retains vanilla Moveables")
        native:tryBuild(nativePlateTile:getX(), nativePlateTile:getY(), 0)
        check(vanillaClicks == 1, "unrelated Moveables delegate to vanilla placement")

        local plateCandidate = selectType(nativePlateTile, "ZedComm.PressurePlate")
        click(nativePlateTile)
        check(native.objectSprite and native.objectSprite:getName() == "zedcomm_devices_01_20"
            and queuedWalk and queuedWalk.location == nativePlateTile and arrive():complete()
            and not inventory:contains(plateCandidate.object) and getCell():getDrag(0) == native,
            "native Place previews and places the selected pressure plate without leaving the tool")
        local nativePlate = placement.piecesAt(playerRegistry, nativePlateTile)[1]
        assert(playerRegistry:setDeviceState(nativePlate.id, { label = "native test" }))

        local displayCandidate = selectType(nativeDisplayTile, "ZedComm.NumericDisplay")
        click(nativeDisplayTile)
        check(arrive():complete() and not inventory:contains(displayCandidate.object)
            and getCell():getDrag(0) == native, "the same native tool cycles to and places the display")
        local nativeDisplay = placement.piecesAt(playerRegistry, nativeDisplayTile)[1]

        local laid, previousWire = lay(nativePlateTile, give("ZedComm.SignalWire"), nativePlate.id, "signal")
        assert(laid, previousWire)
        native:setMoveableMode("pickup")
        native:clearCache()
        local selectedPlate = selectNative(nativePlateTile, function(entry)
            return entry.zedcommPickup and entry.zedcommPickup.id == nativePlate.id
        end)
        click(nativePlateTile)
        check(selectedPlate.object == nativePlate.object and arrive():complete()
            and not playerRegistry.network.pieces[nativePlate.id] and playerRegistry.network.pieces[previousWire],
            "native pickup uses the exact registered endpoint and leaves its connected wire")
        local recovered = carried[#carried]
        check(recovered:getModData().zedcommPlacement.state.label == "native test",
            "native pickup preserves endpoint identity and settings on the returned item")

        native:setMoveableMode("place")
        native:clearCache()
        selectNative(relocatedPlateTile, function(entry) return entry.object == recovered end)
        click(relocatedPlateTile)
        assert(arrive():complete())
        local restored = placement.piecesAt(playerRegistry, relocatedPlateTile)[1]
        check(restored.id == nativePlate.id and restored.piece.ports.signal == false
            and restored.piece.state.label == "native test", "native placement restores old settings with a free port")

        local stockCount = 0
        for _, entry in ipairs(native:getInventoryObjectList()) do
            if entry.zedcommKey == "ZedComm.SignalWire" then stockCount = stockCount + 1 end
        end
        check(stockCount == 1, "native cycling lists a stack of loose wire as one candidate")

        local wireCandidate = selectType(relocatedPlateTile, "ZedComm.SignalWire")
        choice, queued, queuedWalk = nil, nil, nil
        click(relocatedPlateTile)
        check(choice and choice.options["Place wire loose"] and choice.options["Connect to pressure plate"]
            and not queued and not queuedWalk, "native wire placement prompts on a device free port")
        choice.options["Connect to pressure plate"]()
        assert(arrive():complete())
        local nativeWire = restored.piece.ports.signal
        check(nativeWire and not inventory:contains(wireCandidate.object) and getCell():getDrag(0) == native,
            "native connect starts continuous laying from the newly placed wire")
        local crossing = give("ZedComm.SignalWire")
        local loose, crossingId = runPlacement(nextWireTile, { kind = "place", item = crossing })
        assert(loose, crossingId)
        player.tile = relocatedPlateTile
        queued, queuedWalk, choice = nil, nil, nil
        click(nextWireTile)
        check(choice and choice.options["Connect to wire 1 / Loose wire"] and choice.options["Lay wire here"]
            and not queued and not queuedWalk, "an active native run can join a cable end or lay another wire")
        choice.options["Lay wire here"]()
        assert(arrive():complete())
        local connected
        for _, entry in ipairs(placement.piecesAt(playerRegistry, nextWireTile)) do
            if entry.id ~= crossingId then connected = entry end
        end
        check(connected and connected.piece.links[nativeWire] == true
            and #playerRegistry.network:partners(crossingId) == 0, "the crossing stays independent of the selected run")

        invalidOutline = nil
        click(floorTile(62, 55))
        check(invalidOutline and invalidOutline.x == 63 and invalidOutline.y == 56
            and invalidOutline.r == 1 and invalidOutline.a == 1 and invalidOutline.width == 3,
            "the native cursor draws a bold red outline on an invalid wire tile")

        choice, queued, queuedWalk = nil, nil, nil
        click(nativeDisplayTile)
        check(choice and choice.options["Connect to numeric display"] and choice.options["Lay wire here"]
            and not queued and not queuedWalk, "left-clicking a compatible endpoint offers join and lay choices")
        choice.visible = false

        local savedWires = {}
        for _, item in ipairs(carried) do
            if item:getFullType() == "ZedComm.SignalWire" then savedWires[#savedWires + 1] = item end
        end
        for _, item in ipairs(savedWires) do inventory:Remove(item) end
        native:clearCache()
        choice = nil
        click(nativeDisplayTile)
        check(choice and choice.options["Connect to numeric display"] and not choice.options["Lay wire here"],
            "the last placed wire can still be joined through the native cursor with no spare wire")
        choice.options["Connect to numeric display"]()
        check(queuedWalk and arrive():complete() and nativeDisplay.piece.ports.signal == connected.id
            and getCell():getDrag(0) == native, "left-click join uses the exact last segment and keeps the Place tool open")
        for _, item in ipairs(savedWires) do inventory:AddItem(item) end
        player.tile = nextWireTile
        getCell():setDrag(native, 0)
        native:clearCache()
        native:rotateKey(0, true)
        selectType(clearWireTile, "ZedComm.SignalWire")
        queued, queuedWalk = nil, nil
        click(clearWireTile)
        check(queuedWalk and arrive():complete(), "the native Place tool can start another loose wire after a completed run")
        local standalone = placement.piecesAt(playerRegistry, clearWireTile)[1]
        queued, queuedWalk = nil, nil
        click(skippedWireTile)
        check(standalone and #playerRegistry.network:partners(standalone.id) == 0 and not queued and not queuedWalk,
            "a loose first native segment becomes the anchor and prevents skipped tiles")
        selectType(skippedWireTile, "Base.TestMoveable")
        selectType(skippedWireTile, "ZedComm.SignalWire")
        click(skippedWireTile)
        check(queuedWalk and queuedWalk.location == skippedWireTile and arrive():complete(),
            "cycling to a different item releases the selected wire end")

        give("ZedComm.SignalWire")
        give("ZedComm.SignalWire")
        selectType(clearWireTile, "Base.TestMoveable")
        selectType(clearWireTile, "ZedComm.SignalWire")
        choice, queued, queuedWalk = nil, nil, nil
        click(clearWireTile)
        check(choice and choice.options["Place wire loose"] and choice.options["Connect to wire 1 / Loose wire from an adjacent tile"]
            and not queued and not queuedWalk, "the native cursor prompts before placing on an existing free cable")
        choice.options["Place wire loose"]()
        assert(arrive():complete())
        local parallel = placement.piecesAt(playerRegistry, clearWireTile)
        table.sort(parallel, function(a, b) return a.id < b.id end)
        check(#parallel == 2 and playerRegistry.network:networkOf(parallel[1].id)
            ~= playerRegistry.network:networkOf(parallel[2].id), "native loose placement keeps the two cables independent")

        selectType(clearWireTile, "Base.TestMoveable")
        selectType(clearWireTile, "ZedComm.SignalWire")
        choice, queued, queuedWalk = nil, nil, nil
        click(clearWireTile)
        assert(choice.options["Connect to wire 2 / Loose wire from an adjacent tile"])()
        local adjacent = floorTile(59, 54)
        click(adjacent)
        assert(arrive():complete())
        local added = placement.piecesAt(playerRegistry, adjacent)[1]
        check(added and added.piece.links[parallel[2].id] == true and not added.piece.links[parallel[1].id],
            "native connect chooses the exact cable and lays the new segment on its neighboring tile")

        native:setMoveableMode("pickup")
        native:clearCache()
        local selectedWire = selectNative(clearWireTile, function(entry)
            return entry.zedcommPickup and entry.zedcommPickup.id == parallel[2].id
        end)
        local info = selectedWire.moveProps:getInfoPanelDescription()
        check(info[1] == "Wire 2 of 2" and info[2] == playerRegistry:getRunName(parallel[2].id)
            and parallel[2].object:isOutlineHighlight(0) and not parallel[1].object:isOutlineHighlight(0),
            "native pickup cycles to the numbered wire and outlines exactly that segment")
        local inventoryCount = #carried
        click(clearWireTile)
        check(arrive():complete() and #carried == inventoryCount + 1
            and carried[#carried]:getFullType() == "ZedComm.SignalWire"
            and not playerRegistry.network.pieces[parallel[2].id]
            and playerRegistry.network.pieces[parallel[1].id]
            and #playerRegistry.network:partners(added.id) == 0,
            "native pickup returns one wire and severs only the selected link")
        native:isValid(clearWireTile)
        check(parallel[1].object:isOutlineHighlight(0) and not parallel[2].object:isOutlineHighlight(0),
            "the pickup outline follows the remaining wire")
        getCell():setDrag(nil, 0)
        check(not parallel[1].object:isOutlineHighlight(0), "leaving native Pickup restores the wire's outline")

        do
            local startTile, lastTile = floorTile(66, 58), floorTile(67, 58)
            local targetTile, continuation = floorTile(68, 58), floorTile(69, 58)
            local ok, targetId = runPlacement(targetTile, { kind = "place", item = give("ZedComm.SignalWire") })
            assert(ok, targetId)
            assert(lay(continuation, give("ZedComm.SignalWire"), targetId, false))
            assert(playerRegistry:renameRun(targetId, "Bench cable"))
            local placed, looseId = runPlacement(targetTile, { kind = "place", item = give("ZedComm.SignalWire") })
            assert(placed, looseId)

            player.tile = startTile
            native:setMoveableMode("place")
            native:clearCache()
            getCell():setDrag(native, 0)
            selectType(startTile, "ZedComm.SignalWire")
            click(startTile)
            assert(arrive():complete())
            click(lastTile)
            assert(arrive():complete())
            local active = placement.piecesAt(playerRegistry, lastTile)[1]
            local runLabel = playerRegistry:getRunName(active.id)
            local previewWire = selectType(lastTile, "ZedComm.SignalWire")
            check(runLabel and previewWire.moveProps:getInfoPanelDescription()[2] == runLabel,
                "native Place displays the active run's name")
            local rest = {}
            for _, item in ipairs(carried) do
                if item:getFullType() == "ZedComm.SignalWire" then rest[#rest + 1] = item end
            end
            for _, item in ipairs(rest) do inventory:Remove(item) end
            native:clearCache()

            choice, queued, queuedWalk = nil, nil, nil
            click(targetTile)
            local number = targetId < looseId and 1 or 2
            local label = "Connect to wire " .. number .. " / " .. playerRegistry:getRunName(targetId)
            check(choice and choice.options[label] and not choice.options["Lay wire here"],
                "active placement offers the named cable end even with no spare wire")
            local option = choice.entries[label]
            local targetObject = placement.resolve(playerRegistry, targetId).object
            local looseObject = placement.resolve(playerRegistry, looseId).object
            option.onHighlight(option, choice, true, unpack(option.onHighlightParams))
            check(targetObject:isOutlineHighlight(0) and not looseObject:isOutlineHighlight(0),
                "hovering the join choice outlines only the named cable")
            option.onHighlight(option, choice, false, unpack(option.onHighlightParams))

            local units = #carried
            choice.options[label]()
            check(arrive():complete() and #carried == units and active.piece.links[targetId]
                and not active.piece.links[looseId] and playerRegistry:getRunName(active.id) == playerRegistry:getRunName(targetId)
                and getCell():getDrag(0) == native, "joining the exact existing cable uses no stock and finishes the active run")
            for _, item in ipairs(rest) do inventory:AddItem(item) end
            getCell():setDrag(nil, 0)
        end

        for i, plateSpec in ipairs({ { "ZedComm.OccupancyPlate", 419 }, { "ZedComm.WeightPlate", 425 } }) do
            local tile = floorTile(65 + i, 60)
            local itemType, frame = plateSpec[1], "zedcomm_devices_01_" .. plateSpec[2]
            local plateItem = give(itemType)
            native:setMoveableMode("place")
            native:clearCache()
            getCell():setDrag(native, 0)
            selectType(tile, itemType)
            click(tile)
            check(native.objectSprite and native.objectSprite:getName() == frame
                and arrive():complete() and not inventory:contains(plateItem),
                "native Place offers " .. itemType .. " with its own floor sprite")

            local plate = placement.piecesAt(playerRegistry, tile)[1]
            native:setMoveableMode("pickup")
            native:clearCache()
            selectNative(tile, function(entry) return entry.zedcommPickup and entry.zedcommPickup.id == plate.id end)
            click(tile)
            check(arrive():complete() and carried[#carried]:getFullType() == itemType,
                "native Pickup returns " .. itemType)
            getCell():setDrag(nil, 0)
        end

        inventory.AddItem = realAddItem
        getText, getPlayerRadialMenu, KeybindId = originalText, originalRadial, originalKeybind
        IsoFlagType = originalFlagType
    end
    testNativeBridge()

    getCore, JoypadState, IsoSprite = originalGetCore, originalJoypad, originalSprite
    renderIsoRect = originalRenderRect
end

-- Update wires and plate terminals using the real topology and square-load callbacks.
dofile(LUA .. "client/ZedComm/WireVisuals.lua")
local function spriteOf(id)
    return placement.resolve(playerRegistry, id).object.sprite
end
fire("OnTick")
check(spriteOf(replacement) == "zedcomm_devices_01_9"
    and spriteOf(secondWire) == "zedcomm_devices_01_11", "both bends use their actual orthogonal connections")
check(spriteOf(plateId) == "zedcomm_devices_01_22", "existing plate shows the lead to its +X cable")
local replacedWireObject = placement.resolve(playerRegistry, replacement).object
replacedWireObject.sprite = "zedcomm_devices_01_1"
fire("LoadGridsquare", w0)
check(spriteOf(replacement) == "zedcomm_devices_01_9", "a streamed-in wire gets the current variant")
assert(playerRegistry:unlink(secondWire, displayId))
fire("OnTick")
check(spriteOf(secondWire) == "zedcomm_devices_01_10", "disconnect exposes a capped free end")
assert(playerRegistry:link(secondWire, displayId))
fire("OnTick")
check(spriteOf(secondWire) == "zedcomm_devices_01_11", "reconnect restores the bend sprite")
local unlinkedTile = floorTile(42, 40)
local unlinked = worldObject(unlinkedTile, {
    id = "unlinked-neighbor", kind = "cable", placedItem = "ZedComm.SignalWire",
})
function unlinked.getSprite() return nil end
function unlinked.setSprite(_, sprite) unlinked.sprite = sprite:getName() end
fire("OnObjectAdded", unlinked)
fire("OnTick")
check(unlinked.sprite == "zedcomm_devices_01_3" and spriteOf(secondWire) == "zedcomm_devices_01_11",
    "adjacent unlinked wires stay visually separate")
playerRegistry, playerJava = start(save(playerJava))
replacedWireObject.sprite = "zedcomm_devices_01_1"
placement.resolve(playerRegistry, plateId).object.sprite = "zedcomm_devices_01_0"
fire("OnTick")
check(spriteOf(replacement) == "zedcomm_devices_01_9", "wire shapes are rederived after reload")
check(spriteOf(plateId) == "zedcomm_devices_01_22", "plate direction is rederived from the saved link")

do
    local tile = floorTile(50, 50)
    local ok, id = runPlacement(tile, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(ok, id)
    local decoy = worldObject(floorTile(51, 50), { id = "plate-visual-decoy", kind = "cable" })
    fire("OnObjectAdded", decoy)
    local plateObject = placement.resolve(playerRegistry, id).object
    plateObject.spriteInstance = { getName = function() return "zedcomm_devices_01_20" end }
    fire("OnTick")
    check(plateObject:getSprite() == getSprite("zedcomm_devices_01_20"),
        "an unlinked neighbor leaves an empty socket using the registered floor sprite")

    for _, route in ipairs({ { 50, 51, 23 }, { 49, 50, 24 }, { 50, 49, 25 }, { 50, 50, 21 } }) do
        local wireTile = floorTile(route[1], route[2])
        local laid, cableId = lay(wireTile, give("ZedComm.SignalWire"), id, "signal")
        assert(laid, cableId)
        fire("OnTick")
        check(spriteOf(id) == "zedcomm_devices_01_" .. route[3], "plate follows the cable for frame " .. route[3])
        assert(target(wireTile, cableId, "pickup"))
    end
    fire("OnTick")
    check(spriteOf(id) == "zedcomm_devices_01_20", "picking up the linked cable restores the empty socket")
end

-- Parallel routes share lane positions across tile edges and around bends.
do
    local left, middle, right, south = floorTile(47, 62), floorTile(48, 62), floorTile(49, 62), floorTile(49, 63)
    local function parallelCable(tile, id)
        local object = IsoObject.new(tile, "zedcomm_devices_01_1")
        object:getModData().zedcomm = { id = id, kind = "cable", placedItem = "ZedComm.SignalWire" }
        tile:AddTileObject(object)
        fire("OnObjectAdded", object)
        return object
    end
    for _, lane in ipairs({ "parallel-b", "parallel-a" }) do
        parallelCable(left, lane .. "-left")
        parallelCable(middle, lane .. "-middle")
        parallelCable(right, lane .. "-right")
        parallelCable(south, lane .. "-south")
        assert(playerRegistry:link(lane .. "-left", lane .. "-middle"))
        assert(playerRegistry:link(lane .. "-middle", lane .. "-right"))
        assert(playerRegistry:link(lane .. "-right", lane .. "-south"))
    end
    fire("OnTick")
    local function frame(id, index)
        return spriteOf(id) == "zedcomm_devices_01_" .. index
    end
    check(frame("parallel-a-left", 190) and frame("parallel-a-middle", 257)
        and frame("parallel-b-left", 192) and frame("parallel-b-middle", 292),
        "parallel straight routes keep distinct matching lanes at the seam")
    check(frame("parallel-a-right", 355) and frame("parallel-a-south", 207)
        and frame("parallel-b-right", 334) and frame("parallel-b-south", 205),
        "parallel elbows preserve each lane across the turn and out the next seam")
    playerRegistry, playerJava = start(save(playerJava))
    fire("OnTick")
    check(frame("parallel-a-middle", 257) and frame("parallel-a-right", 355)
        and frame("parallel-b-middle", 292) and frame("parallel-b-right", 334),
        "parallel visual lanes are stable across reload despite reverse placement order")
    assert(target(middle, "parallel-a-middle", "pickup"))
    fire("OnTick")
    check(spriteOf("parallel-b-middle") == "zedcomm_devices_01_8"
        and #playerRegistry.network:partners("parallel-b-middle") == 2,
        "a remaining parallel wire returns to the centered sprite and keeps both links")

    local cableTile, deviceTile = floorTile(51, 62), floorTile(52, 62)
    local ok, device = runPlacement(deviceTile, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(ok, device)
    parallelCable(cableTile, "port-wire")
    parallelCable(cableTile, "passing-wire")
    parallelCable(deviceTile, "passing-other")
    assert(playerRegistry:link("port-wire", device, "signal"))
    assert(playerRegistry:link("passing-wire", "passing-other"))
    fire("OnTick")
    check(frame("port-wire", 191) and frame("passing-wire", 192) and frame("passing-other", 202),
        "an adjacent device keeps its centered lead and the passing wire keeps a distinct lane")
end

-- The development source drives arbitrary bytes through the actual runtime.
local byteTile, byteWireTile, byteDisplayTile = floorTile(60, 60), floorTile(61, 60), floorTile(62, 60)
local byteSource = worldObject(byteTile, {
    id = "debug-byte", kind = "endpoint", definitionId = "ZedComm.DebugByteSource", rigWire = "debug-wire",
})
byteSource.sprite = "zedcomm_devices_01_0"
function byteSource.getSprite() return { getName = function() return byteSource.sprite end } end
function byteSource.setSprite(_, sprite) byteSource.sprite = sprite:getName() end
local byteWire = worldObject(byteWireTile, { id = "debug-wire", kind = "cable" })
local byteDisplay = worldObject(byteDisplayTile, {
    id = "debug-display", kind = "endpoint", definitionId = "ZedComm.NumericDisplay",
})
for _, object in ipairs({ byteSource, byteWire, byteDisplay }) do fire("OnObjectAdded", object) end
assert(playerRegistry:link("debug-wire", "debug-byte", "signal"))
assert(playerRegistry:link("debug-wire", "debug-display", "signal"))
fire("OnTick")
check(byteSource.sprite == "zedcomm_devices_01_0", "the byte test source keeps its original sprite")
local report = runtime.inspect("debug-wire")
check(report.status == "ok" and report.sourceByte == 0 and report.receivers[1].value == 0,
    "inspector distinguishes valid zero from signal loss")
for _, value in ipairs({ 85, 170, 42, 255 }) do
    assert(runtime.setTestByte(playerRegistry, "debug-byte", tostring(value)))
    fire("OnTick")
    report = runtime.inspect("debug-display")
    check(report.sourceId == "debug-byte" and report.sourceByte == value
        and report.receivers[1].value == value, "inspector reports byte " .. value .. " end to end")
end
do
    local model = playerRegistry.network
    local function deliverWeight(fallback, expected)
        assert(model:setPacket("debug-byte", {
            type = "signal.advanced", value = { kind = "weight", amount = 1150, unit = "kg" },
            basicValue = fallback,
        }))
        simulation.tick()
        local value, _, attached = runtime.getDisplay(byteDisplay)
        return value == expected and attached and runtime.inspect("debug-wire").status == "ok"
    end
    check(deliverWeight(115, 115), "an advanced packet's sender-provided fallback reaches the byte display")
    check(deliverWeight(0, 0), "zero remains a valid advanced fallback")
    check(deliverWeight(256, nil), "an invalid fallback leaves the attached display without a reading")
    check(deliverWeight(nil, nil), "an absent fallback leaves the attached display without a reading")
end
check(not runtime.setTestByte(playerRegistry, "debug-byte", "256")
    and not runtime.setTestByte(playerRegistry, "debug-byte", "0.5")
    and not runtime.setTestByte(playerRegistry, plateId, "85")
    and playerRegistry.network:record("debug-byte").state.byte == 255,
    "invalid bytes and non-debug devices are rejected without changing the source")
assert(runtime.setTestByte(playerRegistry, "debug-byte", "170"))
fire("OnTick")
playerRegistry, playerJava = start(save(playerJava))
fire("OnTick")
check(runtime.inspect("debug-display").receivers[1].value == 170,
    "the debug source and receiver recover their configured byte after reload")
loaded[key(60, 60, 0)] = nil
fire("OnTick")
report = runtime.inspect("debug-display")
check(report.status == "no-source" and report.sourceByte == nil
    and report.receivers[1].reading and report.receivers[1].value == nil,
    "an unloaded source yields no signal while its attached receiver stays bound")
loaded[key(60, 60, 0)] = true
fire("OnTick")
check(runtime.inspect("debug-display").receivers[1].value == 170,
    "source reload restores the current byte without a sender change")

-- Two player-built circuits share a square and stay independently selectable.
do
    playerRegistry, playerJava = start()
    local center = floorTile(70, 70)
    local west, east = floorTile(69, 70), floorTile(71, 70)
    local north, south = floorTile(70, 69), floorTile(70, 71)

    local function placeDevice(tile, itemType)
        local ok, id = runPlacement(tile, { kind = "place", item = give(itemType) })
        assert(ok, id)
        return id
    end
    local westId = placeDevice(west, "ZedComm.PressurePlate")
    local eastId = placeDevice(east, "ZedComm.NumericDisplay")
    local northId = placeDevice(north, "ZedComm.PressurePlate")
    local southId = placeDevice(south, "ZedComm.NumericDisplay")
    give("ZedComm.SignalWire")
    give("ZedComm.SignalWire")

    local function choose(tile, label, group)
        local parent = menuAt(tile)
        local options = group and assert(parent.children[group], "missing submenu: " .. group).options or parent.options
        assert(options[label], "missing option: " .. label)
        queued = nil
        options[label]()
        if queued then
            assert(queued:isValid())
            assert(queued:complete())
        end
    end

    choose(west, "Select pressure plate free end")
    choose(center, "Lay wire here")
    local wireA = playerRegistry.network.pieces[westId].ports.signal
    choose(north, "Select pressure plate free end")
    local units = #carried
    choose(center, "Lay another wire here (1 present)")
    local wireB = playerRegistry.network.pieces[northId].ports.signal
    check(wireA ~= wireB and #carried == units - 1 and #placement.piecesAt(playerRegistry, center) == 2,
        "laying a second wire on the tile creates one distinct segment and consumes one unit")
    check(playerRegistry.network:networkOf(wireA) ~= playerRegistry.network:networkOf(wireB),
        "two wires on one tile do not join their networks")

    local nameA, nameB = "Wire 1 of 2", "Wire 2 of 2"
    if wireB < wireA then nameA, nameB = nameB, nameA end
    local menu = menuAt(center)
    local first, second = menu.children[nameA].options, menu.children[nameB].options
    check(first["Select free end"] and second["Select free end"]
        and first["Pick up"] and second["Pick up"] and first["Inspect"] and second["Inspect"],
        "both shared wires expose actions in their own submenus")
    check(not menu.options["Select free end"] and not menu.options["Pick up"]
        and not menu.options["Pick up wire 1 of 2"] and not menu.options["Inspect wire 2 of 2"],
        "shared wire actions do not clutter the ZedComm parent menu")
    local objectA = placement.resolve(playerRegistry, wireA).object
    local objectB = placement.resolve(playerRegistry, wireB).object
    local childA, childB = menu.children[nameA], menu.children[nameB]
    local function hover(context, label, enabled)
        local option = context.entries[label]
        option:onHighlight(context, enabled, unpack(option.onHighlightParams))
    end
    local previousColor = ColorInfo.new()
    previousColor:setABGR(0xFF123456)
    objectA:setOutlineHighlightCol(0, previousColor)
    hover(menu, nameA, true)
    check(objectA:isOutlineHighlight(0) and objectA:getOutlineHighlightCol(0) == 0xFFFFFF26
        and not objectB:isOutlineHighlight(0), "hovering a wire branch gives only that wire a cyan outline")
    hover(childA, "Select free end", true)
    hover(menu, nameA, false)
    check(objectA:isOutlineHighlight(0) and not objectB:isOutlineHighlight(0),
        "moving into a wire action keeps its sprite outlined")
    hover(menu, nameB, true)
    hover(childA, "Select free end", false)
    check(not objectA:isOutlineHighlight(0) and objectB:isOutlineHighlight(0)
        and objectA:getOutlineHighlightCol(0) == 0xFF123456,
        "switching wires restores the first sprite even when its old action leaves late")
    hover(childB, "Inspect", true)
    hover(childB, "Inspect", false)
    check(objectB:isOutlineHighlight(0), "leaving the child retains the parent wire outline")
    hover(menu, nameB, false)
    check(not objectB:isOutlineHighlight(0) and objectB:getOutlineHighlightCol(0) == -1,
        "closing the menu clears the outline and restores its original color")
    objectB:setOutlineHighlight(0, true)
    hover(menu, nameB, true)
    hover(menu, nameB, false)
    check(objectB:isOutlineHighlight(0) and objectB:getOutlineHighlightCol(0) == -1,
        "closing the menu preserves a pre-existing outline")
    objectB:setOutlineHighlight(0, false)

    choose(center, "Select free end", nameA)
    choose(east, "Connect wire to numeric display")
    choose(south, "Select numeric display free end")
    choose(center, "Connect selected run", nameB)
    check(playerRegistry.network.pieces[eastId].ports.signal == wireA
        and playerRegistry.network.pieces[southId].ports.signal == wireB,
        "menu selection and joining both target the intended wire ID")

    local spoken
    function player.Say(_, message) spoken = message end
    do
        local oldBox, oldLoader = ISTextBox, package.preload["ISUI/ISTextBox"]
        local modal, confirmed, initial, input
        package.preload["ISUI/ISTextBox"] = function()
            ISTextBox = {
                new = function(_, _, _, _, _, _, default, owner, confirm)
                    initial = default
                    confirmed = function() confirm(owner, { internal = "OK" }) end
                    modal = {
                        entry = { getText = function() return input end },
                        initialise = function() end,
                        addToUIManager = function() end,
                    }
                    return modal
                end,
            }
        end
        input = "  West loop  "
        choose(center, "Rename run", nameA)
        assert(initial == "")
        confirmed()
        check(playerRegistry:getRunName(wireA) == "Run 1 (West loop)"
            and playerRegistry:getRunName(wireB) == "Run 2", "renaming a wire changes only its connected run")
        input = "77"
        choose(west, "Set pressure plate output (1)")
        confirmed()
        check(initial == "1" and optionsAt(west)["Set pressure plate output (77)"]
            and optionsAt(north)["Set pressure plate output (1)"],
            "the context menu edits only the chosen pressure plate and shows its current output")
        ISTextBox, package.preload["ISUI/ISTextBox"] = oldBox, oldLoader
        package.loaded["ISUI/ISTextBox"] = nil
    end
    choose(center, "Inspect", nameA)
    check(string.find(spoken, "east device port", 1, true) and string.find(spoken, "west device port", 1, true),
        "wire inspection distinguishes the east-west route")
    choose(center, "Inspect", nameB)
    check(string.find(spoken, "north device port", 1, true) and string.find(spoken, "south device port", 1, true),
        "wire inspection distinguishes the north-south route")

    west.actors, north.actors = { { class = "IsoPlayer" } }, {}
    check(placedReading(eastId) == 77 and placedReading(southId) == 0,
        "first source drives only its own circuit across the shared tile")
    west.actors, north.actors = {}, { { class = "IsoPlayer" } }
    check(placedReading(eastId) == 0 and placedReading(southId) == 1,
        "second source drives only its own circuit across the shared tile")

    playerRegistry, playerJava = start(save(playerJava))
    center.objects[1], center.objects[2] = center.objects[2], center.objects[1]
    check(#placement.piecesAt(playerRegistry, center) == 2 and placedReading(southId) == 1,
        "both wire IDs, links, and isolated signals survive registry reload")
    choose(center, "Inspect", nameA)
    check(string.find(spoken, "west device port", 1, true) and string.find(spoken, "Run 1 (West loop)", 1, true),
        "wire numbering and the custom name survive reload and tile object reordering")
    units = #carried
    choose(center, "Pick up", nameA)
    check(not playerRegistry.network.pieces[wireA] and playerRegistry.network.pieces[wireB]
        and #placement.piecesAt(playerRegistry, center) == 1 and #carried == units + 1,
        "numbered pickup removes only the selected wire and recovers one unit")
    local value, _, attached = placedReading(eastId)
    check(value == nil and not attached and placedReading(southId) == 1,
        "removing one wire leaves the other shared-tile circuit working")
end

-- Durable installation data uses the same save and pickup path as devices.
do
    playerRegistry, playerJava = start()
    local sourceSquare, wireSquare, displaySquare = floorTile(80, 80), floorTile(81, 80), floorTile(82, 80)
    local source = worldObject(sourceSquare, {
        id = "module-test-source", kind = "endpoint", definitionId = "ZedComm.DebugByteSource",
    })
    local wire = worldObject(wireSquare, { id = "module-test-wire", kind = "cable" })
    fire("OnObjectAdded", source)
    fire("OnObjectAdded", wire)
    assert(playerRegistry:link("module-test-wire", "module-test-source"))
    local ok, displayId = runPlacement(displaySquare, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(ok, displayId)
    local moduleId = ZedComm.SignalModules.BYTE_READOUT
    local configuration = { module = { id = moduleId, config = { label = "North bench" } } }
    assert(playerRegistry:setDeviceState(displayId, configuration))
    assert(playerRegistry:link("module-test-wire", displayId))
    assert(runtime.setTestByte(playerRegistry, "module-test-source", "170"))
    check(placedReading(displayId) == 170, "explicit byte readout installation works through the runtime")

    playerRegistry, playerJava = start(save(playerJava))
    local saved = playerRegistry.network:record(displayId).state.module
    check(saved.id == moduleId and saved.config.label == "North bench" and saved.request == nil
        and saved.attached == nil and placedReading(displayId) == 170,
        "reload restores module identity and config and rebuilds the live reading")

    assert(playerRegistry:setDeviceState(displayId, { module = { id = "Example.MissingModule" } }))
    local value, _, attached = placedReading(displayId)
    check(value == nil and not attached and playerRegistry.network:record(displayId).state.module.id == "Example.MissingModule"
        and playerRegistry.network.pieces[displayId].ports.signal == "module-test-wire",
        "incompatible saved module disables delivery while preserving configuration and wiring")
    assert(playerRegistry:setDeviceState(displayId, configuration))
    check(placedReading(displayId) == 170, "restored module receives the held byte without a source change")

    assert(target(displaySquare, displayId, "pickup"))
    fire("OnTick")
    local item = carried[#carried]
    local kept = item:getModData().zedcommPlacement.state.module
    check(kept.id == moduleId and kept.config.label == "North bench" and playerRegistry.network.pieces["module-test-wire"],
        "pickup retains module configuration and leaves the wire in place")
    local replaced, idAgain = runPlacement(displaySquare, { kind = "place", item = item })
    assert(replaced, idAgain)
    local valueAgain, _, attachedAgain = placedReading(idAgain)
    check(idAgain == displayId and valueAgain == nil and not attachedAgain
        and playerRegistry.network.pieces[idAgain].ports.signal == false,
        "replacement retains identity and waits for a new wire connection")
    assert(playerRegistry:link("module-test-wire", idAgain))
    check(placedReading(idAgain) == 170, "reconnecting the recovered fixture restores the held byte")
    assert(playerRegistry:unlink("module-test-wire", idAgain))

    local calls = { binds = 0, releases = 0, values = {} }
    assert(definitions.register({
        id = "Example.ModularFixture", role = "receiver", ports = { "signal" },
        match = function() return false end, receiverModule = moduleId,
        bindFixture = function(_, _, config)
            calls.binds = calls.binds + 1
            calls.label = config.label
            config.label = "changed by fixture"
            return {
                apply = function(_, byte)
                    calls.values[#calls.values + 1] = { byte = byte }
                    return "applied"
                end,
                release = function() calls.releases = calls.releases + 1 end,
            }
        end,
    }))
    local otherSquare = floorTile(81, 81)
    local modular = worldObject(otherSquare, {
        id = "modular-fixture", kind = "endpoint", definitionId = "Example.ModularFixture",
        state = { module = { id = moduleId, config = { label = "copied" } } },
    })
    fire("OnObjectAdded", modular)
    assert(playerRegistry:link("module-test-wire", "modular-fixture"))
    fire("OnTick")
    fire("OnTick")
    check(calls.binds == 1 and #calls.values == 1 and calls.values[1].byte == 170
        and calls.label == "copied" and playerRegistry.network:record("modular-fixture").state.module.config.label == "copied",
        "runtime binds once and gives the adapter a copy of durable config")
    loaded[key(81, 81, 0)] = nil
    fire("OnTick")
    fire("OnTick")
    check(calls.releases == 1, "unloading a receiver releases its module exactly once")
    loaded[key(81, 81, 0)] = true
    fire("OnTick")
    check(calls.binds == 2 and #calls.values == 2 and calls.values[2].byte == 170,
        "reloading the fixture attaches a fresh module and reads the held byte")

    assert(playerRegistry:unlink("module-test-wire", "modular-fixture"))
end

-- A relay uses native lamp power/switch behavior and vanilla moveable data.
do
    local debugBefore = getDebug
    getDebug = function() return true end
    playerRegistry, playerJava = start()
    local relay = ZedComm.RelayLamp
    local srcSquare, wireSquare, lampSquare = floorTile(90, 90), floorTile(91, 90), floorTile(92, 90)
    local newLampSquare = floorTile(91, 91)

    local function lampAt(tile, eligible, movableData)
        local lamp = worldObject(tile, nil)
        lamp.class = "IsoLightSwitch"
        lamp.powered, lamp.active, lamp.switches = true, false, 0
        lamp:getModData().movableData = movableData
        function lamp.getCanBeModified() return eligible end
        function lamp.getSprite() return nil end
        function lamp.canSwitchLight() return lamp.powered end
        function lamp.isActivated() return lamp.active end
        function lamp.setActive(_, value)
            if lamp.powered and lamp.active ~= value then
                lamp.active = value
                lamp.switches = lamp.switches + 1
            end
            return lamp.active
        end
        function lamp.toggle() return lamp:setActive(not lamp.active) end
        lamp.attachments = { { getParentSprite = function() return { getName = function() return "vanilla" end } end } }
        function lamp.getAttachedAnimSprite() return list(lamp.attachments) end
        function lamp.addAttachedAnimSprite(_, sprite)
            lamp.attachments[#lamp.attachments + 1] = { getParentSprite = function() return sprite end }
        end
        function lamp.RemoveAttachedAnim(_, index) table.remove(lamp.attachments, index + 1) end
        return lamp
    end

    local function housingIs(lamp, index)
        return #lamp.attachments == 2
            and lamp.attachments[1]:getParentSprite():getName() == "vanilla"
            and lamp.attachments[2]:getParentSprite():getName() == "zedcomm_devices_01_" .. index
    end

    local plain = lampAt(floorTile(93, 90), false)
    local fixture = lampAt(lampSquare, true, { zedcommDevice = { def = "SpikeLamp" } })
    check(not optionsAt(plain:getSquare())["Install test relay"]
        and not runPlacement(plain:getSquare(), { kind = "install-relay", object = plain }),
        "ineligible lights do not get a retrofit action and reject direct installation")
    local options = optionsAt(lampSquare)
    queued = nil
    assert(options["Install test relay"])()
    assert(queued and queued:isValid() and queued:complete())
    fire("OnTick")
    check(housingIs(fixture, 14) and #plain.attachments == 1, "only the installed lamp gets an unplugged housing")
    local id = fixture:getModData().zedcomm.id
    local installed = playerRegistry.network:record(id).state.module
    check(installed.id == relay.MODULE and fixture:getModData().movableData.zedcommRelay.id == id
        and fixture:getModData().movableData.zedcommDevice.def == "SpikeLamp",
        "test install creates the relay endpoint and preserves unrelated moveable data")
    check(not runPlacement(lampSquare, { kind = "install-relay", object = fixture })
        and playerRegistry.network:record(id).state.module.id == relay.MODULE,
        "reinstall is rejected without changing the installed relay")
    check(optionsAt(lampSquare)["Select relay lamp free end"] and not optionsAt(lampSquare)["Pick up relay lamp"],
        "relay lamp can wire through the player menu and retains native pickup")

    local ok, plateId = runPlacement(srcSquare, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(ok, plateId)
    local laid, wireId = lay(wireSquare, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(lampSquare, wireId, false, id, "signal"))
    fire("OnTick")
    check(relay.isWired(fixture) and not fixture.active, "wired lamp follows the clear plate")
    fire("LoadGridsquare", lampSquare)
    check(housingIs(fixture, 18), "the west lead is attached once, preserving the vanilla child sprite")
    srcSquare.actors = { { class = "IsoPlayer" } }
    fire("OnTick")
    fire("OnTick")
    check(fixture.active and fixture.switches == 1, "steady high drives the lamp once without strobing")

    package.loaded["TimedActions/ISToggleLightAction"] = true
    ISToggleLightAction = {
        isValid = function() return true end,
        complete = function(self) self.object:toggle(); return true end,
    }
    dofile(LUA .. "client/ZedComm/RelayLampControls.lua")
    local manual = setmetatable({ object = fixture }, { __index = ISToggleLightAction })
    check(not manual:isValid() and manual:complete() and fixture.active and fixture.switches == 1,
        "wired manual toggle is blocked both at validation and at completion")

    assert(playerRegistry:unlink(wireId, plateId))
    fire("OnTick")
    check(not fixture.active and fixture.switches == 2 and relay.isWired(fixture),
        "loss of source turns an attached lamp off without releasing native control")
    check(housingIs(fixture, 18), "physical cable direction persists during signal loss")
    fixture.powered = false
    assert(playerRegistry:link(wireId, plateId))
    fire("OnTick")
    check(not fixture.active and fixture.switches == 2, "unpowered lamp does not apply the on request")
    fixture.powered = true
    srcSquare.actors = {}
    fire("OnTick")
    check(not fixture.active and fixture.switches == 2,
        "power restoration plus a same-tick OFF never applies the stale ON")
    fixture.powered = false
    srcSquare.actors = { { class = "IsoZombie" } }
    fire("OnTick")
    fixture.powered = true
    fire("OnTick")
    fire("OnTick")
    check(fixture.active and fixture.switches == 3,
        "power restoration applies the held ON without a new source change")

    options = optionsAt(lampSquare)
    queued = nil
    assert(options["Disconnect relay wire"])()
    assert(queued and queued:isValid() and queued:complete())
    fire("OnTick")
    check(not relay.isWired(fixture) and manual:isValid() and manual:complete()
        and not fixture.active and fixture.switches == 4, "disconnect restores vanilla manual switching")
    check(housingIs(fixture, 14), "disconnect restores the empty socket")
    assert(playerRegistry:link(wireId, id))
    fire("OnTick")
    check(fixture.active, "reconnect applies current source without a new sample")

    local durable = { module = { id = relay.MODULE, config = { label = "workbench" } } }
    assert(playerRegistry:setDeviceState(id, durable))
    fixture:RemoveAttachedAnim(1)
    playerRegistry, playerJava = start(save(playerJava))
    fire("OnTick")
    check(housingIs(fixture, 18), "saved wire restores the attachment after reload")
    check(relay.isWired(fixture) and fixture.active
        and playerRegistry.network:record(id).state.module.config.label == "workbench",
        "registry reload restores wiring and the installed module configuration")

    -- Simulate vanilla copying movableData before it removes the world object.
    local picked = deepCopy(fixture:getModData().movableData)
    fire("OnObjectAboutToBeRemoved", fixture)
    takeOff(lampSquare, fixture)
    fire("OnTick")
    check(not playerRegistry.network.pieces[id] and playerRegistry.network.pieces[wireId]
        and picked.zedcommRelay.state.module.config.label == "workbench",
        "native pickup carries durable installation data while leaving the cable")
    local restored = lampAt(newLampSquare, true, picked)
    local tabletopTexture = {
        getOffsetX = function() return 59 end, getWidth = function() return 30 end,
        getOffsetY = function() return 95 end, getHeight = function() return 58 end,
    }
    function restored.getSprite() return { getTextureForCurrentFrame = function() return tabletopTexture end } end
    function restored.getDir() return "N" end
    function restored.getRenderYOffset() return 18 end
    fire("OnObjectAdded", restored)
    fire("OnTick")
    check(restored:getModData().zedcomm.id == id and playerRegistry.network:record(id).state.module.config.label == "workbench"
        and not relay.isWired(restored) and playerRegistry.network.pieces[id].ports.signal == false,
        "native replacement rebuilds the same endpoint and leaves the cable disconnected")
    check(housingIs(restored, 44), "native replacement mounts the unplugged housing at the tabletop sprite base")
    restored:RemoveAttachedAnim(1)
    fire("OnObjectAdded", restored)
    fire("OnTick")
    check(housingIs(restored, 44), "native placement refreshes the housing even when topology has not changed")
    assert(playerRegistry:link(wireId, id))
    fire("OnTick")
    check(restored.active and restored.switches == 1, "replaced lamp responds after an explicit reconnect")
    check(housingIs(restored, 49), "the raised housing follows the same wire from its new side")

    assert(playerRegistry:unlink(wireId, id))
    for _, test in ipairs({ { 92, 91, 46 }, { 91, 92, 47 }, { 91, 91, 45 } }) do
        local cableId = "visual-cable-" .. test[3]
        local cable = worldObject(floorTile(test[1], test[2]), { id = cableId, kind = "cable" })
        fire("OnObjectAdded", cable)
        assert(playerRegistry:link(cableId, id))
        fire("OnTick")
        check(housingIs(restored, test[3]), "housing follows selected cable for frame " .. test[3])
        assert(playerRegistry:unlink(cableId, id))
    end

    assert(playerRegistry:link(wireId, id))
    local Circuit = ZedComm.InternalCircuit
    local load = 80
    assert(target(srcSquare, plateId, "pickup"))
    local weightPlaced, weightId = runPlacement(srcSquare, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(weightPlaced and playerRegistry:link(wireId, weightId))
    srcSquare.actors = {}
    srcSquare.overlappingVehicle = { getMass = function() return load end }
    local function tickLamp(byte, active, message)
        fire("OnTick")
        local report = runtime.inspect(wireId)
        check(report.sourceByte == byte and restored.active == active, message)
    end
    local layout = Circuit.thresholdPreset()
    assert(runtime.setLampCircuit(playerRegistry, id, layout))
    tickLamp(8, false, "lamp threshold leaves a player reading unchanged on the wire and turns off")
    load = 500
    tickLamp(50, true, "lamp threshold includes the exact trip point")
    load = 1150
    tickLamp(115, true, "a vehicle reading reaches the lamp and clears the threshold")
    local switches = restored.switches
    tickLamp(115, true, "the held byte keeps the lamp on")
    check(restored.switches == switches, "steady threshold output never toggles the lamp")
    layout.modules.threshold.threshold = 120
    assert(runtime.setLampCircuit(playerRegistry, id, layout))
    tickLamp(115, false, "changing the threshold reevaluates a steady input")
    layout.modules.threshold.threshold = 50
    assert(runtime.setLampCircuit(playerRegistry, id, layout))
    tickLamp(115, true, "lowering the threshold turns the lamp back on")
    local invalid = Circuit.thresholdPreset()
    invalid.modules.threshold.column = 1
    check(not runtime.setLampCircuit(playerRegistry, id, invalid)
        and playerRegistry.network:record(id).state.circuit.modules.threshold.column == 2,
        "invalid layouts leave the saved circuit intact")
    layout.links[2] = nil
    assert(runtime.setLampCircuit(playerRegistry, id, layout))
    tickLamp(115, false, "a broken internal link turns off the lamp with live wire input")
    local damagedState = playerRegistry.network:record(id).state
    damagedState.circuit = false
    assert(playerRegistry:setDeviceState(id, damagedState))
    playerRegistry, playerJava = start(save(playerJava))
    tickLamp(115, false, "an invalid saved circuit fails off instead of bypassing its logic")
    check(playerRegistry.network:record(id).state.circuit == false,
        "an invalid saved circuit stays available for repair")

    restored.powered = false
    assert(runtime.setLampCircuit(playerRegistry, id, Circuit.thresholdPreset()))
    tickLamp(115, false, "restoring the link while unpowered retains an ON request")
    restored.powered = true
    load = 80
    tickLamp(8, false, "power recovery uses the current threshold result")
    load = 1150
    tickLamp(115, true, "the lamp turns on when the threshold is satisfied again")
    assert(playerRegistry:unlink(wireId, weightId))
    tickLamp(nil, false, "source loss clears the lamp without detaching its wire")
    check(relay.isWired(restored), "source loss keeps the lamp under network control")
    assert(playerRegistry:link(wireId, weightId))
    tickLamp(115, true, "source reconnect reevaluates the restored input")

    playerRegistry, playerJava = start(save(playerJava))
    load = 80
    tickLamp(8, false, "reload restores the circuit and samples current load")
    local savedCircuit = playerRegistry.network:record(id).state.circuit
    check(savedCircuit.modules.threshold.threshold == 50 and #savedCircuit.links == 2,
        "reload retains the installed module and terminal links")
    local advancedMarker = deepCopy(restored:getModData().movableData)
    fire("OnObjectAboutToBeRemoved", restored)
    takeOff(newLampSquare, restored)
    check(playerRegistry.network.pieces[wireId] ~= nil
        and advancedMarker.zedcommRelay.state.circuit.modules.threshold.threshold == 50,
        "native lamp pickup keeps the internal circuit and leaves its exterior wire")
    restored = lampAt(newLampSquare, true, advancedMarker)
    fire("OnObjectAdded", restored)
    local nextManual = setmetatable({ object = restored }, { __index = ISToggleLightAction })
    check(not relay.isWired(restored) and nextManual:isValid() and nextManual:complete(),
        "the replaced lamp can use its native switch while unwired")
    assert(playerRegistry:link(wireId, id))
    tickLamp(8, false, "reconnecting uses the retained threshold instead of direct on/off")

    getDebug = debugBefore
end

-- Labels keep a saved anchor through topology changes and allocate numbers per save.
do
    local registry, java = start()
    local function cable(x, id)
        fire("OnObjectAdded", worldObject(floorTile(x, 120), { id = id, kind = "cable" }))
    end
    cable(101, "b")
    cable(102, "c")
    cable(103, "d")
    cable(104, "e")
    check(registry:getRunName("b") == nil, "unlinked cable has no run name")
    assert(registry:link("b", "c"))
    assert(registry:link("d", "e"))
    check(registry:getRunName("b") == "Run 1" and registry:getRunName("e") == "Run 2",
        "connected runs receive sequential names")
    check(not registry:renameRun("b", "Bad\nname"), "a run name must be a single line")
    assert(registry:renameRun("d", "Tail"))
    assert(registry:link("c", "d"))
    check(registry:getRunName("b") == "Run 2 (Tail)", "a custom name survives a merge with a default name")
    cable(100, "a")
    assert(registry:link("a", "b"))
    check(registry:getRunName("a") == "Run 2 (Tail)", "extension keeps the run name across an electrical network ID change")
    assert(registry:unlink("c", "d"))
    check(registry:getRunName("c") == "Run 3" and registry:getRunName("e") == "Run 2 (Tail)",
        "after a split the saved anchor keeps its name and the other run gets the next number")
    cable(105, "f")
    assert(registry:link("e", "f"))
    assert(registry:removePiece("d"))
    registry = start(save(java))
    check(registry:getRunName("f") == "Run 2 (Tail)" and registry:getRunName("a") == "Run 3",
        "removing the name anchor preserves the name on a surviving run across reload")
    assert(registry:renameRun("f", "   "))
    check(registry:getRunName("e") == "Run 2", "a blank custom name restores the numbered default")
end

local function floorFixture(tile, flags, container, height, class)
    local object = worldObject(tile, nil)
    local props = {
        has = function(_, key) return flags[key] ~= nil end,
        get = function(_, key) return flags[key] end,
    }
    function object.getProperties() return props end
    object.containers = {}
    if container then
        object.containers[1] = { getContentsWeight = function(self) return self.weight or 0 end }
    end
    function object.getContainerCount() return #object.containers end
    function object.getContainerByIndex(_, index) return object.containers[index + 1] end
    function object.getRenderYOffset() return height or 0 end
    object.class = class
    return object
end

local function droppedItem(weight)
    return { getItem = function()
        return { getUnequippedWeight = function() return weight end }
    end }
end


-- The basic plate treats floor furniture and vehicle footprint as presence.
do
    playerRegistry, playerJava = start()
    local plateTile, displayTile, neighbor = floorTile(105, 125), floorTile(106, 125), floorTile(105, 126)
    local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(placed, plateId)
    local displayPlaced, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(displayPlaced, displayId)
    local laid, wireId = lay(plateTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))
    assert(runtime.setPressureOutput(playerRegistry, plateId, 155))

    floorFixture(plateTile, { solidfloor = true }, false)
    floorFixture(plateTile, { solid = true }, false)
    floorFixture(plateTile, {}, false)
    floorFixture(plateTile, { IsMoveAble = true, solid = true, MoveType = "WallObject" }, true)
    floorFixture(plateTile, { IsMoveAble = true, IsTableTop = true }, true)
    floorFixture(plateTile, { IsMoveAble = true }, true, 12)
    floorFixture(plateTile, { IsMoveAble = true, solid = true }, true, 0, "IsoWorldInventoryObject")
    floorFixture(neighbor, { IsMoveAble = true, solidtrans = true }, true)
    neighbor.overlappingVehicle = {}
    check(placedReading(displayId) == 0,
        "floor, decorative and elevated or wall props, and neighboring loads leave the basic plate clear")
    neighbor.looseItems = { droppedItem(5) }
    check(placedReading(displayId) == 0, "an item on a neighboring square leaves the basic plate clear")
    plateTile.looseItems = { droppedItem(0.1) }
    check(placedReading(displayId) == 155, "a single light floor item holds the configured presence byte")
    plateTile.looseItems = {}
    plateTile.staticActors = { { class = "IsoDeadBody" } }
    check(placedReading(displayId) == 155, "a corpse alone holds the basic plate")
    plateTile.staticActors, plateTile.actors = {}, { { class = "IsoAnimal" } }
    check(placedReading(displayId) == 155, "a live animal alone holds the basic plate")
    plateTile.actors = {}

    local crate = floorFixture(plateTile, {}, true)
    check(placedReading(displayId) == 155, "a floor container holds the configured byte above the same-tile cable")
    playerRegistry, playerJava = start(save(playerJava))
    check(placedReading(displayId) == 155, "a loaded crate still drives the saved circuit after reload")
    local table = floorFixture(plateTile, { IsMoveAble = true, solidtrans = true }, false)
    takeOff(plateTile, crate)
    check(placedReading(displayId) == 155, "solid moveable furniture alone holds the same configured byte")
    plateTile.overlappingVehicle = neighbor.overlappingVehicle
    takeOff(plateTile, table)
    check(placedReading(displayId) == 155, "an overlapping vehicle alone holds the same configured byte")
    plateTile.overlappingVehicle = nil
    check(placedReading(displayId) == 0, "removing the last load clears the signal")
end

-- Occupancy stays a count from placement through signal delivery and reload.
do
    playerRegistry, playerJava = start()
    local plateTile, wireTile, displayTile = floorTile(110, 125), floorTile(111, 125), floorTile(112, 125)
    local function placeDevice(tile, itemType)
        local ok, id = runPlacement(tile, { kind = "place", item = give(itemType) })
        assert(ok, id)
        return id
    end
    local plateId = placeDevice(plateTile, "ZedComm.OccupancyPlate")
    local displayId = placeDevice(displayTile, "ZedComm.NumericDisplay")
    local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))
    check(placedReading(displayId) == 0 and spriteOf(plateId) == "zedcomm_devices_01_421",
        "the wired occupancy plate reports zero and the lead faces the connected wire")

    local playerActor, zombie = { class = "IsoPlayer" }, { class = "IsoZombie" }
    local animal, vehicle = { class = "IsoAnimal" }, { class = "BaseVehicle" }
    local states = {
        { { playerActor }, 1 },
        { { playerActor, zombie, animal, vehicle }, 2 },
        { { zombie, animal }, 1 },
        { { animal, vehicle }, 0 },
    }
    for _, state in ipairs(states) do
        plateTile.actors = state[1]
        check(placedReading(displayId) == state[2], "occupancy display follows actor count " .. state[2])
    end
    check(not runtime.setPressureOutput(playerRegistry, plateId, "155")
        and not optionsAt(plateTile)["Set pressure plate output (1)"],
        "the basic plate's fixed-output control is unavailable on a counting plate")

    plateTile.actors = { playerActor, zombie }
    playerRegistry, playerJava = start(save(playerJava))
    check(placedReading(displayId) == 2 and spriteOf(plateId) == "zedcomm_devices_01_421",
        "reload restores the occupancy endpoint, link and lead, then samples the actors")
    assert(target(plateTile, plateId, "pickup"))
    local recovered = carried[#carried]
    local reading, _, attached = placedReading(displayId)
    check(recovered:getFullType() == "ZedComm.OccupancyPlate" and attached and reading == nil,
        "pickup returns the counting plate and leaves the attached display with no signal")
    local restored, sameId = runPlacement(plateTile, { kind = "place", item = recovered })
    check(restored and sameId == plateId and join(plateTile, wireId, false, plateId, "signal")
        and placedReading(displayId) == 2, "replacing and reconnecting resumes the live count")
end

-- A weight source distinguishes on-foot occupants and a vehicle on the same circuit.
do
    playerRegistry, playerJava = start()
    local plateTile, wireTile, displayTile = floorTile(120, 125), floorTile(121, 125), floorTile(122, 125)
    local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(placed, plateId)
    local displayPlaced, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(displayPlaced, displayId)
    local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))

    local vehicle = { class = "BaseVehicle", getMass = function() return 1200 end }
    local pedestrian = { class = "IsoPlayer" }
    function pedestrian:getVehicle() return self.vehicle end
    function pedestrian:getNutrition() return { getWeight = function() return 80 end } end
    local zombie, animal = { class = "IsoZombie" }, { class = "IsoAnimal" }
    function animal:getVehicle() return nil end
    function animal:getData() return { getWeight = function() return 45 end } end
    check(placedReading(displayId) == 0 and spriteOf(plateId) == "zedcomm_devices_01_427",
        "the weight plate sends zero empty and aims its lead at the linked tile")

    plateTile.actors = { pedestrian, animal }
    check(placedReading(displayId) == 13, "weight plate combines on-foot player and animal mass")
    plateTile.actors = { pedestrian, zombie }
    check(placedReading(displayId) == 16, "weight plate adds the zombie estimate before quantizing")
    plateTile.actors = {}
    floorFixture(wireTile, { IsMoveAble = true, PickUpWeight = "200" }, true)
    local unweighed = floorFixture(plateTile, { IsMoveAble = true }, true)
    local wallShelf = floorFixture(plateTile, { IsMoveAble = true, PickUpWeight = "200", MoveType = "WallObject" }, true)
    wallShelf.containers[1].weight = 20
    check(placedReading(displayId) == 0, "weight ignores furniture and contents off the plate's floor")
    unweighed.containers[1].weight = 20
    check(placedReading(displayId) == 2, "known contents contribute when the furniture has no pickup weight")
    takeOff(plateTile, unweighed)

    local crate = floorFixture(plateTile, { IsMoveAble = true, PickUpWeight = "75" }, true)
    check(placedReading(displayId) == 1, "the crate's pickup weight produces a nonzero reading")
    crate.containers[1].weight = 12
    crate.containers[2] = { getContentsWeight = function() return 8 end }
    check(placedReading(displayId) == 3, "weight plate adds the empty crate and both compartments before rounding")
    crate.containers[1].weight = 0
    crate.containers[2] = nil
    check(placedReading(displayId) == 1, "emptying the crate restores the fixture-only reading")
    plateTile.actors = { pedestrian }
    check(placedReading(displayId) == 9, "furniture and actor weight combine before rounding")
    plateTile.actors = {}
    takeOff(plateTile, crate)
    local shelf = floorFixture(plateTile, { IsMoveAble = true, solidtrans = true, PickUpWeight = "200" }, false)
    check(placedReading(displayId) == 2, "solid floor furniture can contribute weight without a container")
    takeOff(plateTile, shelf)
    local lightProp = floorFixture(plateTile, { IsMoveAble = true, PickUpWeight = "45" }, false)
    check(placedReading(displayId) == 1, "a lightweight nonblocking floor prop contributes its weight")
    takeOff(plateTile, lightProp)
    local bag = droppedItem(40) -- engine unequipped weight includes the bag and its contents
    plateTile.looseItems = { droppedItem(20), bag }
    check(placedReading(displayId) == 6, "stacked floor items add their weights including a loaded bag")
    plateTile.actors = { pedestrian }
    check(placedReading(displayId) == 14, "loose items and actor weight sum before rounding")
    plateTile.actors = {}
    local loadedCrate = floorFixture(plateTile, { PickUpWeight = "75" }, true)
    loadedCrate.containers[1].weight = 10
    check(placedReading(displayId) == 8, "loose items also add to furniture and its contents")
    takeOff(plateTile, loadedCrate)
    plateTile.looseItems = { bag }
    check(placedReading(displayId) == 4, "picking up part of the pile reduces the sampled weight")
    plateTile.looseItems = {}
    local body = { class = "IsoDeadBody", getWeight = function() return 0 end,
        isAnimal = function() return false end, getInventoryWeight = function() return 5 end }
    plateTile.staticActors = { body }
    check(placedReading(displayId) == 8, "a stationary corpse adds its estimated body mass plus inventory")
    plateTile.staticActors = {}
    wireTile.overlappingVehicle = vehicle
    check(placedReading(displayId) == 0, "an overlapping vehicle on an adjacent tile leaves the plate clear")
    plateTile.overlappingVehicle = vehicle
    check(placedReading(displayId) == 120, "a parked vehicle holds a distinct nonzero reading without occupants")
    plateTile.actors = { pedestrian }
    pedestrian.vehicle = vehicle
    check(placedReading(displayId) == 120, "the player inside the car contributes no separate mass")
    pedestrian.vehicle = nil
    check(placedReading(displayId) == 128, "an on-foot actor adds to a vehicle's contribution")
    plateTile.actors = {}

    playerRegistry, playerJava = start(save(playerJava))
    check(placedReading(displayId) == 120 and spriteOf(plateId) == "zedcomm_devices_01_427",
        "reload preserves the links and resamples the parked vehicle")
    plateTile.overlappingVehicle = nil
    check(placedReading(displayId) == 0, "the signal clears when the vehicle leaves")
    assert(target(plateTile, plateId, "pickup"))
    local recovered = carried[#carried]
    local value, _, attached = placedReading(displayId)
    check(recovered:getFullType() == "ZedComm.WeightPlate" and attached and value == nil,
        "pickup leaves an attached display without a source")
    local restored, idAgain = runPlacement(plateTile, { kind = "place", item = recovered })
    plateTile.actors = { zombie }
    check(restored and idAgain == plateId and join(plateTile, wireId, false, plateId, "signal")
        and placedReading(displayId) == 8, "replacement and reconnect resume estimated weight")
end

-- Render live bytes on the casing and leave other attachments alone.
do
    playerRegistry, playerJava = start()
    local originalNew = IsoObject.new
    IsoObject.new = function(...)
        local object = originalNew(...)
        local children = {}
        local setSprite = object.setSprite
        function object:setSprite(sprite)
            setSprite(self, sprite)
            self.faceChanges = (self.faceChanges or 0) + 1
        end
        function object:getAttachedAnimSprite() return list(children) end
        function object:addAttachedAnimSprite(sprite)
            children[#children + 1] = { getParentSprite = function() return sprite end }
            self.faceChanges = (self.faceChanges or 0) + 1
        end
        function object:RemoveAttachedAnim(index)
            table.remove(children, index + 1)
            self.faceChanges = (self.faceChanges or 0) + 1
        end
        return object
    end

    dofile(LUA .. "client/ZedComm/DisplayReadout.lua")
    local srcTile, wireTile, displayTile = floorTile(130, 125), floorTile(131, 125), floorTile(132, 125)
    local sourceId = "face-test-source"
    local source = worldObject(srcTile, {
        id = sourceId, kind = "endpoint", definitionId = "ZedComm.DebugByteSource",
    })
    fire("OnObjectAdded", source)
    local placed, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(placed, displayId)
    local display = placement.resolve(playerRegistry, displayId).object
    local prefix = "zedcomm_devices_01_"
    local function faceOf(object)
        local frames = {}
        local children = object:getAttachedAnimSprite()
        for i = 0, children:size() - 1 do
            local name = children:get(i):getParentSprite():getName()
            frames[#frames + 1] = tonumber(name:sub(#prefix + 1))
        end
        table.sort(frames)
        return table.concat(frames, ",")
    end
    check(display.sprite == prefix .. "431" and faceOf(display) == "",
        "a newly placed, disconnected display has a blank face")

    display:setSprite(getSprite(prefix .. "2"))
    display:addAttachedAnimSprite(getSprite(prefix .. "16"))
    fire("LoadGridsquare", displayTile)
    check(display.sprite == prefix .. "431" and faceOf(display) == "16",
        "square load restores the blank casing and keeps other attachments")

    local laid, wireId = runPlacement(wireTile, { kind = "place", item = give("ZedComm.SignalWire") })
    assert(laid, wireId)
    assert(playerRegistry:link(wireId, sourceId))
    assert(join(displayTile, wireId, false, displayId, "signal"))
    local samples = {
        { 0, 1 }, { 1, 2 }, { 85, 86 }, { 170, 171 }, { 255, 256 },
    }
    for _, sample in ipairs(samples) do
        assert(runtime.setTestByte(playerRegistry, sourceId, tostring(sample[1])))
        check(placedReading(displayId) == sample[1] and display.sprite == "zedcomm_display_01_" .. sample[2]
            and faceOf(display) == "16",
            "the displayed byte has the expected digits and indicator for " .. sample[1])
    end
    local changesBefore = display.faceChanges
    fire("OnTick")
    check(display.faceChanges == changesBefore, "steady signals keep the same floor sprite")

    assert(playerRegistry:unlink(wireId, sourceId))
    check(placedReading(displayId) == nil and display.sprite == "zedcomm_display_01_0" and faceOf(display) == "16",
        "attached signal loss swaps the reading for dashes with the indicator off")
    assert(playerRegistry:link(wireId, sourceId))
    check(placedReading(displayId) == 255 and display.sprite == "zedcomm_display_01_256",
        "restoring the source redraws its held byte")
    assert(playerRegistry:unlink(wireId, displayId))
    check(placedReading(displayId) == nil and display.sprite == prefix .. "431" and faceOf(display) == "16",
        "detaching the display blanks the face and keeps unrelated attachments")
    assert(playerRegistry:link(wireId, displayId))
    assert(runtime.setTestByte(playerRegistry, sourceId, "85"))
    fire("OnTick")
    playerRegistry, playerJava = start(save(playerJava))
    fire("LoadGridsquare", displayTile)
    check(placedReading(displayId) == 85 and display.sprite == "zedcomm_display_01_86" and faceOf(display) == "16",
        "reload rebuilds the current face from the saved signal path without duplicate digits")

    assert(target(displayTile, displayId, "pickup"))
    local recovered = carried[#carried]
    local restored, idAgain = runPlacement(displayTile, { kind = "place", item = recovered })
    local replacement = placement.resolve(playerRegistry, displayId).object
    check(restored and idAgain == displayId and replacement.sprite == prefix .. "431" and faceOf(replacement) == "",
        "pickup and replacement start with a clean face")
    assert(join(displayTile, wireId, false, displayId, "signal"))
    check(placedReading(displayId) == 85 and replacement.sprite == "zedcomm_display_01_86" and faceOf(replacement) == "",
        "the replacement redraws its received byte after reconnect")
    IsoObject.new = originalNew
end

-- Use the live menu callbacks to spawn, set and disconnect a byte rig.
do
    playerRegistry, playerJava = start()
    local debugBefore = getDebug
    local oldBox, oldLoader = ISTextBox, package.preload["ISUI/ISTextBox"]
    local box, confirm, playerIndex
    local input = "170"
    package.preload["ISUI/ISTextBox"] = function()
        ISTextBox = {
            new = function(_, _, _, _, _, _, _, _, onClick, playerNum)
                playerIndex = playerNum
                box = {
                    entry = { getText = function() return input end },
                    initialise = function() end,
                    addToUIManager = function() end,
                }
                confirm = function() onClick(nil, { internal = "OK", parent = box }) end
                return box
            end,
        }
    end
    dofile(LUA .. "client/ZedComm/DebugCircuits.lua")
    local sourceTile, wireTile, displayTile = floorTile(140, 125), floorTile(141, 125), floorTile(142, 125)
    check(menuAt(sourceTile).children.Debug == nil, "debug controls stay hidden during ordinary play")
    getDebug = function() return true end
    local debugMenu = assert(menuAt(sourceTile).children.Debug)
    assert(debugMenu.options["Place wired byte test rig"])()
    local source, display = sourceTile:getObjects():get(0), displayTile:getObjects():get(0)
    assert(source and display and wireTile:getObjects():size() == 1, logged[#logged])
    local function rigReading()
        fire("OnTick")
        return runtime.getDisplay(display)
    end
    check(source:getModData().zedcomm.definitionId == "ZedComm.DebugByteSource" and rigReading() == 0,
        "the debug menu places a linked byte source, wire and display")
    debugMenu = assert(menuAt(sourceTile).children.Debug)
    assert(debugMenu.options["Set test byte"])()
    confirm()
    check(playerIndex == 0 and rigReading() == 170, "the byte dialog updates its own rig")
    assert(debugMenu.options["Toggle test source link"])()
    local value, _, attached = rigReading()
    check(value == nil and attached, "the debug source can be cut while leaving the receiver attached")
    assert(debugMenu.options["Toggle test source link"])()
    check(rigReading() == 170, "the debug source restores its held byte")
    local lampTile = floorTile(143, 125)
    local lamp = worldObject(lampTile, nil)
    lamp.class = "IsoLightSwitch"
    function lamp.getCanBeModified() return true end
    function lamp.getSprite() return nil end
    assert(runPlacement(lampTile, { kind = "install-relay", object = lamp }))
    local lampId = lamp:getModData().zedcomm.id
    local install = assert(menuAt(lampTile).children.Debug.options["Install test lamp threshold"])
    install()
    check(playerRegistry.network:record(lampId).state.circuit.modules.threshold.threshold == 50,
        "the debug menu installs a saved threshold preset")
    local edit = assert(menuAt(lampTile).children.Debug.options["Set test lamp threshold"])
    edit()
    input = "120"
    confirm()
    install()
    check(playerRegistry.network:record(lampId).state.circuit.modules.threshold.threshold == 120,
        "the threshold dialog persists changes and an old preset action cannot reset it")
    edit()
    input = "256"
    confirm()
    check(playerRegistry.network:record(lampId).state.circuit.modules.threshold.threshold == 120,
        "the threshold dialog rejects values outside the byte range")
    getDebug = debugBefore
    ISTextBox, package.preload["ISUI/ISTextBox"] = oldBox, oldLoader
    package.loaded["ISUI/ISTextBox"] = nil
end

-- Select the weight sender through the debug menu and inspect its live packet.
do
    playerRegistry, playerJava = start()
    local debugBefore = getDebug
    local plateTile, wireTile, displayTile = floorTile(145, 125), floorTile(146, 125), floorTile(147, 125)
    local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(placed, plateId)
    local displayPlaced, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(displayPlaced, displayId)
    local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))

    local mass = 1150
    local vehicle = { getMass = function() return mass end }
    plateTile.overlappingVehicle = vehicle
    check(placedReading(displayId) == 115, "the default weight sender delivers the existing byte")
    local initial = runtime.inspect(wireId)
    check(initial.sourcePacket and initial.sourcePacket.type == "signal.basic"
        and initial.sourcePacket.value == 115, "the inspector reports the default basic packet")
    check(menuAt(plateTile).children.Debug == nil, "the weight sender selector is debug-only")
    getDebug = function() return true end
    local function modeMenu(label)
        return assert(assert(menuAt(plateTile).children.Debug).children["Weight plate sender (" .. label .. ")"])
    end

    assert(playerRegistry:setDeviceState(plateId, { label = "Road plate" }))
    assert(modeMenu("Basic Sender").options["Advanced Sender"])()
    check(placedReading(displayId) == 115, "switching to advanced keeps the byte display at the same value")
    local advanced = runtime.inspect(wireId)
    check(advanced.sourcePacket.type == "signal.advanced" and advanced.sourcePacket.value.amount == 1150
        and advanced.sourcePacket.value.unit == "kg" and advanced.sourcePacket.basicValue == 115
        and advanced.receivers[1].value == 115, "the inspector reports full weight, units, fallback and receiver byte")
    assert(menuAt(wireTile).children.Debug.options["Inspect circuit"])()
    local output = logged[#logged]
    check(string.find(output, "signal.advanced", 1, true) and string.find(output, "1150 kg", 1, true)
        and string.find(output, "fallback 115", 1, true) and string.find(output, "receiver 115", 1, true),
        "the actual inspect menu reports the advanced payload and the delivered byte")
    mass = 1151
    check(placedReading(displayId) == 115 and runtime.inspect(wireId).sourcePacket.value.amount == 1151,
        "a changed full reading reaches the inspector even when the fallback stays steady")
    check(not runtime.setWeightPlateSender(playerRegistry, displayId, "ZedComm.AdvancedSender")
        and not runtime.setWeightPlateSender(playerRegistry, plateId, "Example.UnknownSender")
        and playerRegistry.network:record(plateId).state.senderModule.id == "ZedComm.AdvancedSender",
        "invalid targets and sender IDs preserve the selected sender")

    assert(modeMenu("Advanced Sender").options["Basic Sender"])()
    check(placedReading(displayId) == 115 and runtime.inspect(wireId).sourcePacket.type == "signal.basic"
        and playerRegistry.network:record(plateId).state.senderModule == nil
        and playerRegistry.network:record(plateId).state.label == "Road plate",
        "selecting Basic Sender clears only the override and restores the basic packet")

    assert(playerRegistry:setDeviceState(plateId, { label = "Road plate", senderModule = { id = "Example.UnknownSender" } }))
    playerRegistry, playerJava = start(save(playerJava))
    local value, _, attached = placedReading(displayId)
    check(value == nil and attached and runtime.inspect(wireId).sourcePacket == nil
        and playerRegistry.network:record(plateId).state.senderModule.id == "Example.UnknownSender",
        "an unsupported saved sender stays installed and the linked display sees no live signal")
    assert(modeMenu("unavailable").options["Advanced Sender"])()
    check(placedReading(displayId) == 115, "choosing a supported module repairs the circuit")

    mass = 1200
    playerRegistry, playerJava = start(save(playerJava))
    check(placedReading(displayId) == 120 and runtime.inspect(wireId).sourcePacket.value.amount == 1200
        and playerRegistry.network:record(plateId).state.senderModule.id == "ZedComm.AdvancedSender",
        "same-build reload preserves wiring and sender selection and samples the new load")
    plateTile.overlappingVehicle = nil
    check(placedReading(displayId) == 0 and runtime.inspect(wireId).sourcePacket.basicValue == 0,
        "an empty advanced plate publishes a valid zero fallback")
    plateTile.overlappingVehicle = vehicle
    assert(playerRegistry:unlink(wireId, plateId))
    value, _, attached = placedReading(displayId)
    check(value == nil and attached, "disconnecting the source clears the attached display")
    assert(playerRegistry:link(wireId, plateId, "signal"))
    check(placedReading(displayId) == 120, "reconnect restores the current advanced fallback")

    local stale = assert(modeMenu("Advanced Sender").options["Basic Sender"])
    assert(target(plateTile, plateId, "pickup"))
    local item = carried[#carried]
    check(item:getModData().zedcommPlacement.state.senderModule.id == "ZedComm.AdvancedSender",
        "native placement state carries the installed sender through pickup")
    local replaced, sameId = runPlacement(plateTile, { kind = "place", item = item })
    assert(replaced and sameId == plateId)
    stale()
    assert(join(plateTile, wireId, false, plateId, "signal"))
    check(placedReading(displayId) == 120 and runtime.inspect(wireId).sourcePacket.type == "signal.advanced",
        "replacement keeps the module and rejects a stale action aimed at the picked-up object")
    getDebug = debugBefore
end

-- Exercise the actual editor callbacks through vanilla-style panel and dialog stubs.
do
    playerRegistry, playerJava = start()
    local previousDebug, previousCore = getDebug, getCore
    local input, confirm, panel
    local cursorX, cursorY = 0, 0
    local rotateKey = 99 -- rebound from the default
    getDebug = function() return true end
    getCore = function()
        return {
            getScreenWidth = function() return 1200 end, getScreenHeight = function() return 800 end,
            isKey = function(_, binding, key) return binding == "rotate" and key == rotateKey end,
            getKey = function(_, binding) if binding == "rotate" then return rotateKey end end,
        }
    end
    ISPanel = {}
    function ISPanel:derive() return setmetatable({}, { __index = self }) end
    function ISPanel:new() return setmetatable({}, { __index = self }) end
    function ISPanel:initialise() end
    function ISPanel:addChild() end
    function ISPanel:addToUIManager() panel = self; self:createChildren() end
    function ISPanel:removeFromUIManager() panel = nil end
    function ISPanel:setVisible() end
    function ISPanel:setWantKeyEvents(value) self.wantKeyEvents = value end
    function ISPanel:setCapture(value) self.captured = value end
    function ISPanel:bringToTop() end
    function ISPanel:getMouseX() return cursorX end
    function ISPanel:getMouseY() return cursorY end
    function ISPanel:onMouseUpOutside() end
    function ISPanel:setStencilRect() end
    function ISPanel:clearStencilRect() end
    function ISPanel:drawText() end
    function ISPanel:drawTextCentre() end
    function ISPanel:drawRect() end
    function ISPanel:drawRectBorder() end
    function ISPanel:drawTextureScaled() end
    ISButton = { new = function(_, _, _, _, _, _, target, action)
        return { initialise = function() end, setEnable = function() end, click = function() action(target) end }
    end }
    ISTextBox = { new = function(_, _, _, _, _, _, _, _, action)
        local entry = { getText = function() return input end }
        return { entry = entry, initialise = function() end, addToUIManager = function()
            confirm = function()
                action(nil, { internal = "OK", parent = { entry = entry } })
            end
        end }
    end }
    package.loaded["ISUI/ISPanel"] = true
    package.loaded["ISUI/ISButton"] = true
    package.loaded["ISUI/ISTextBox"] = true
    local originalTexture, originalFont, originalDrag = getTexture, UIFont, ISMouseDrag
    local originalBindings, originalKeyboard = KeybindId, Keyboard
    getTexture = function() return {} end
    UIFont, ISMouseDrag = { Small = 1, Medium = 2 }, {}
    KeybindId, Keyboard = { ROTATE_BUILDING = "rotate" }, { getKeyName = tostring }
    dofile(LUA .. "client/ZedComm/AdapterEditor.lua")

    local lampTile, wireTile, plateTile = floorTile(155, 125), floorTile(156, 125), floorTile(157, 125)
    local lamp = worldObject(lampTile, nil)
    lamp.class, lamp.active = "IsoLightSwitch", false
    function lamp.getCanBeModified() return true end
    function lamp.getSprite() return nil end
    function lamp.getAttachedAnimSprite() return nil end
    function lamp.addAttachedAnimSprite() end
    function lamp.canSwitchLight() return true end
    function lamp.isActivated() return lamp.active end
    function lamp.setActive(_, active) lamp.active = active end
    local adapter, part = give("ZedComm.AdvancedAdapter"), give("ZedComm.ThresholdModule")
    queued = nil
    assert(optionsAt(lampTile)["Install Advanced Adapter"])()
    assert(queued and queued:isValid() and queued:complete())
    local id = lamp:getModData().zedcomm.id
    local function circuit() return playerRegistry.network:record(id).state.circuit end
    check(not inventory:contains(adapter) and #circuit().links == 0, "install consumes the carried adapter and creates its empty board")
    local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(placed)
    local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid and join(lampTile, wireId, false, id, "signal"))
    plateTile.overlappingVehicle = { getMass = function() return 1150 end }
    assert(optionsAt(lampTile)["Open Advanced Adapter"])()
    assert(panel and panel:refresh())
    panel:render()
    local function grabCarried() panel:onMouseDown(294, 95) end
    local function click(x, y)
        panel:onMouseDown(x, y)
        panel:onMouseUp(x, y)
    end
    grabCarried()
    check(panel.wantKeyEvents and panel.captured and panel.drag.item == part,
        "dragging a carried module captures the mouse and enables rotate input through the editor")
    panel:onKeyPress(rotateKey)
    check(panel.drag.rotation == 90, "carried modules use the same rotate binding while held")
    panel:onRightMouseUp(133, 142)
    check(not panel.drag and not panel.captured and inventory:contains(part), "cancelling a carried module keeps the item")

    grabCarried()
    cursorX, cursorY = 72, 142
    panel:render()
    check(not panel.drag.preview.valid and panel.drag.part.column == 1 and panel.drag.part.row == 1,
        "the snapped preview rejects a footprint overlapping a fixed part")
    cursorX, cursorY = 133, 86
    panel:render()
    check(not panel.drag.preview.valid and panel.drag.part.row == 0,
        "the preview rejects a footprint that extends above the grid")
    cursorY = 142
    cursorX = 133
    panel:render()
    check(panel.drag.preview.valid and panel.drag.part.column == 2 and panel.drag.part.row == 1
        and inventory:contains(part) and not circuit().modules["threshold-1"],
        "moving the pointer previews a valid snapped location without consuming or installing the module")
    panel:onMouseUp(72, 142)
    check(inventory:contains(part) and not circuit().modules["threshold-1"],
        "an overlapping placement consumes no module")
    grabCarried()
    panel:onMouseUp(133, 142)
    check(not inventory:contains(part) and circuit().modules["threshold-1"].threshold == 50,
        "placing the selected module commits the inventory and board together")
    fire("OnTick")
    check(not lamp.active, "an installed module with no links leaves the lamp off")
    click(85, 142)
    click(103, 142)
    click(163, 142)
    click(181, 142)
    fire("OnTick")
    check(lamp.active and #circuit().links == 2, "terminal selection completes the circuit")
    panel:linkTerminal("threshold-1", "out")
    panel:linkTerminal("output", "in")
    fire("OnTick")
    check(not lamp.active and #circuit().links == 1, "selecting the same connected terminals unlinks them")
    panel.autoButton.click()
    fire("OnTick")
    check(lamp.active and #circuit().links == 2, "automatic routing restores the single module path")
    panel:onMouseDown(122, 105)
    check(not panel:isKeyConsumed(19) and panel:isKeyConsumed(rotateKey),
        "the held module uses the game's configured rotate key")
    panel:onKeyPress(19)
    check(panel.drag.rotation == 0, "unrelated keys leave the preview orientation alone")
    panel:onKeyPress(rotateKey)
    panel:onMouseUp(158, 105)
    check(circuit().modules["threshold-1"].rotation == 0 and #circuit().links == 2,
        "rotation that overlaps a fixed part leaves the existing board intact")
    panel:onRightMouseUp(122, 105)
    input = "120"
    confirm()
    fire("OnTick")
    check(not lamp.active and circuit().modules["threshold-1"].threshold == 120,
        "right-clicking the installed part edits its threshold on a steady byte")
    assert(optionsAt(lampTile)["Set threshold"])()
    input = "50"
    panel:onMouseDown(122, 105)
    panel:onKeyPress(rotateKey)
    confirm()
    panel:onMouseUp(155, 262)
    fire("OnTick")
    check(lamp.active and circuit().modules["threshold-1"].threshold == 50
        and circuit().modules["threshold-1"].rotation == 0 and not panel.captured,
        "an edit from the world shortcut updates the same setting and cancels a stale drag")
    panel:onMouseDown(122, 105)
    panel:onKeyPress(rotateKey)
    panel:onRightMouseUp(155, 262)
    check(not panel.drag and not panel.captured and not panel:isKeyConsumed(rotateKey)
        and circuit().modules["threshold-1"].rotation == 0, "right-click cancels without moving the installed module")
    panel:onMouseUp(155, 262)
    check(not panel.terminal and #circuit().links == 2, "releasing after cancellation does not select a contact")
    panel:onMouseDown(122, 105)
    panel:onMouseUpOutside(-1, 105)
    check(not panel.drag and not panel.captured and circuit().modules["threshold-1"].row == 1,
        "releasing outside the editor leaves the installed part in place")
    panel:onMouseDown(122, 105)
    player.tile = plateTile
    panel:render()
    panel:onMouseUp(155, 262)
    check(not panel.drag and not panel.captured and circuit().modules["threshold-1"].row == 1,
        "losing edit reach cancels a held module before it can be dropped")
    player.tile = lampTile
    panel:onMouseDown(122, 105)
    panel:onKeyPress(rotateKey)
    cursorX, cursorY = 155, 262
    panel:render()
    check(panel.drag.preview.valid and circuit().modules["threshold-1"].rotation == 0,
        "the rotated bottom-row preview does not mutate the live circuit")
    panel:onMouseUp(155, 262)
    fire("OnTick")
    check(circuit().modules["threshold-1"].row == 3 and circuit().modules["threshold-1"].rotation == 90
        and #circuit().links == 2 and lamp.active and not panel.captured,
        "move and rotate together preserve the wired terminal identities")
    inventory.full = true
    panel:removePart()
    inventory.full = false
    check(circuit().modules["threshold-1"] ~= nil, "a full inventory preserves the installed part")
    panel:removePart()
    fire("OnTick")
    check(not circuit().modules["threshold-1"] and #circuit().links == 0 and not lamp.active
        and inventory:getFirstType("ZedComm.ThresholdModule"), "removal returns a module and releases its links")
    local returnedPart = inventory:getFirstType("ZedComm.ThresholdModule")
    grabCarried()
    panel:onKeyPress(rotateKey)
    panel:onMouseUp(118, 275)
    local installed = circuit().modules["threshold-1"]
    check(installed and installed.column == 1 and installed.row == 3 and installed.rotation == 90
        and not inventory:contains(returnedPart), "a carried module can be installed directly in its rotated position")
    panel:removePart()
    local inverterItem = give("ZedComm.NotModule")
    panel:onMouseDown(294, 118)
    panel:onMouseUp(133, 142)
    panel.autoButton.click()
    fire("OnTick")
    check(not inventory:contains(inverterItem) and not lamp.active and #circuit().links == 2,
        "dragging and auto-connecting NOT in the Advanced Adapter inverts a positive byte")
    plateTile.overlappingVehicle = nil
    fire("OnTick")
    check(lamp.active, "NOT on the 3x3 board turns the lamp on for a valid zero")
    assert(playerRegistry:unlink(wireId, plateId))
    fire("OnTick")
    check(not lamp.active, "unplugging NOT's input leaves the wired lamp off")
    panel:removePart()
    panel:close()

    -- Two tiles away the editor opens and reads, but every change asks the player to step closer.
    local openEditor = assert(optionsAt(lampTile)["Open Advanced Adapter"])
    player.tile = plateTile
    openEditor()
    check(panel and panel:refresh() and not panel.reachable, "the editor opens read-only from two tiles away")
    panel:render()
    grabCarried()
    check(not panel.drag and panel.message == "Step next to the lamp to make changes.",
        "starting a placement from two tiles away asks the player to step closer")
    panel:onMouseUp(111, 82)
    check(not circuit().modules["threshold-1"], "a click from two tiles away changes nothing")
    panel:linkTerminal("input", "out")
    check(panel.terminal == nil, "contact selection needs reach")
    wireTile.blocked = lampTile
    check(not panel:refresh(), "a blocked path closes the looking range")
    wireTile.blocked = nil
    local farTile = floorTile(158, 125)
    player.tile = farTile
    check(not panel:refresh(), "three tiles away is out of range")
    player.tile = lampTile
    check(panel:refresh() and panel.reachable, "stepping back next to the lamp restores editing")
    panel:close()

    local function cabinetScenario()
        -- Build the cabinet from the real placement menu, editor and simulation pass.
        playerRegistry, playerJava = start()
        local cabinetTile = floorTile(170, 125)
        plateTile, lampTile = floorTile(168, 125), floorTile(172, 125)
        local armTile = floorTile(170, 123)
        local inputTile, armWireTile, outputTile = floorTile(169, 125), floorTile(170, 124), floorTile(171, 125)
        local cabinetItem = give("ZedComm.SmallCabinet")
        local cabinetMenu = menuAt(cabinetTile)
        local placementOptions = cabinetMenu.children["Place device"] or cabinetMenu
        assert(placementOptions.options["Place basic small cabinet"])()
        assert(queued and queued:isValid() and queued:complete())
        local cabinet = cabinetTile.objects[1]
        local cabinetId = cabinet:getModData().zedcomm.id
        local function cabinetPiece() return playerRegistry.network.pieces[cabinetId] end
        check(cabinet.sprite == "zedcomm_devices_01_466" and not inventory:contains(cabinetItem)
            and cabinetPiece().ports.input == false and cabinetPiece().ports.output == false,
            "normal placement creates a cabinet with two fixed external jacks")
        local plateOK, cabinetPlate = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
        local armItem = give("ZedComm.NetworkSwitch")
        check(not runPlacement(armTile, { kind = "place", item = armItem }) and inventory:contains(armItem),
            "the network switch needs a wall and an invalid placement keeps the item")
        armTile.northWall = {}
        local armOK, arm = runPlacement(armTile, { kind = "place", item = armItem })
        assert(plateOK and armOK)
        local function armPiece() return playerRegistry.network.pieces[arm] end
        local function armObject() return placement.resolve(playerRegistry, arm).object end
        local function flipArm(on)
            local action = on and "Turn network switch on" or "Turn network switch off"
            assert(optionsAt(armTile)[action])()
            assert(queued and queued:isValid() and queued:complete())
        end
        check(armPiece().state.on == false and armObject().sprite == "zedcomm_devices_01_467",
            "a freshly mounted network switch defaults off")
        lamp = worldObject(lampTile, nil)
        lamp.class, lamp.active = "IsoLightSwitch", false
        function lamp.getCanBeModified() return true end
        function lamp.getSprite() return nil end
        function lamp.getAttachedAnimSprite() return nil end
        function lamp.addAttachedAnimSprite() end
        function lamp.canSwitchLight() return true end
        function lamp.isActivated() return lamp.active end
        function lamp.setActive(_, active) lamp.active = active end
        assert(optionsAt(lampTile)["Install test relay"])()
        assert(queued and queued:isValid() and queued:complete())
        local lampId = lamp:getModData().zedcomm.id

        local andItem, extension = give("ZedComm.AndModule"), give("ZedComm.InputExtension")
        assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
        assert(panel and panel:refresh())
        panel:render()
        check(panel.gridSize == 6 and panel.parts.input.height == 120 and panel.parts.output.height == 120,
            "the cabinet uses the same editor with fixed two-cell parts on a 6 by 6 grid")
        panel:onMouseDown(420, 84)
        panel:onMouseUp(106, 124)
        panel:onMouseDown(420, 118)
        panel:onMouseUp(226, 244)
        panel:onMouseDown(420, 152)
        panel:onKeyPress(rotateKey)
        panel:onMouseUp(207, 104)
        check(not inventory:contains(andItem) and not inventory:contains(extension)
            and cabinetPiece().state.circuit.modules["inputExtension-3"].rotation == 90,
            "dragging from the cabinet inventory installs AND and a rotated extension")
        panel:linkTerminal("input", "out")
        panel:linkTerminal("threshold-1", "in")
        panel:linkTerminal("threshold-1", "out")
        panel:linkTerminal("and-2", "a")
        panel:linkTerminal("inputExtension-3", "out")
        panel:linkTerminal("and-2", "b")
        panel:linkTerminal("and-2", "out")
        panel:linkTerminal("output", "in")
        check(#cabinetPiece().state.circuit.links == 4, "editor wires each named AND contact")

        local laidInput, inputWire = lay(inputTile, give("ZedComm.SignalWire"), cabinetPlate, "signal")
        local laidArm, armWire = lay(armWireTile, give("ZedComm.SignalWire"), arm, "signal")
        local laidOutput, outputWire = lay(outputTile, give("ZedComm.SignalWire"), lampId, "signal")
        assert(laidInput and laidArm and laidOutput)
        assert(join(cabinetTile, inputWire, false, cabinetId, "input"))
        assert(join(cabinetTile, armWire, false, cabinetId, "inputExtension-3"))
        assert(join(cabinetTile, outputWire, false, cabinetId, "output"))
        local function tick()
            fire("OnTick")
            fire("OnTick")
        end
        local function output()
            return runtime.inspect(cabinetId, "output").sourceByte
        end
        tick()
        local net = playerRegistry.network
        local labelMenu = assert(menuAt(cabinetTile).children["Label cabinet jack"])
        local boardBefore = cabinetPiece().board
        assert(labelMenu.options.IN)()
        input = "Load"
        confirm()
        check(cabinetPiece().state.portLabels.input == "Load" and cabinetPiece().board == boardBefore
            and cabinetPiece().ports.input == inputWire and optionsAt(cabinetTile)["Disconnect cabinet jack (IN (Load))"],
            "labeling a wired jack preserves its board, port identity and cable")
        player.isDead, player.isAiming, player.isIgnoreContextKey = function() return false end, function() return false end,
            function() return false end
        player.isClimbingLadder, player.isClimbingDownLadder = player.isDead, player.isDead
        local previousUI = UIManager
        UIManager = { getSpeedControls = function() return nil end }
        player.tile = armTile
        fire("OnObjectLeftMouseButtonDown", armObject())
        assert(queued and queued:isValid() and queued:complete())
        tick()
        check(armPiece().state.on and runtime.inspect(arm).sourceByte == 255
            and armObject().sprite == "zedcomm_switch_01_7", "a direct click toggles the mounted, wired switch")
        UIManager = previousUI
        flipArm(false)
        tick()
        check(net:networkOf(inputWire) ~= net:networkOf(armWire) and net:networkOf(armWire) ~= net:networkOf(outputWire)
            and net:networkOf(inputWire) ~= net:networkOf(outputWire), "the three cabinet runs stay independent")
        local load = 80
        plateTile.overlappingVehicle = { getMass = function() return load end }
        flipArm(true)
        tick()
        check(output() == 0 and not lamp.active and runtime.inspect(arm).sourceByte == 255
            and armObject().sprite == "zedcomm_switch_01_7",
            "the arm latches at 255 and shows the on sprite while a low load leaves the receiver off")
        load = 1150
        flipArm(false)
        fire("OnTick")
        check(output() == 0 and runtime.inspect(arm).sourceByte == 0
            and armObject().sprite == "zedcomm_switch_01_2" and not ZedComm.Simulation.hasPending(),
            "coalesced input changes do not publish a transient ON or requeue an equal output")
        local packets = ZedComm.SignalModules.Packet
        runtime.prepare(playerRegistry)
        runtime.deliver(net:networkOf(inputWire), packets.basic(8))
        runtime.deliver(net:networkOf(armWire), packets.basic(255))
        runtime.finish()
        runtime.prepare(playerRegistry)
        runtime.deliver(net:networkOf(armWire), packets.basic(0))
        runtime.deliver(net:networkOf(inputWire), packets.basic(115))
        runtime.finish()
        check(output() == 0 and not ZedComm.Simulation.hasPending(),
            "explicitly reversed delivery order produces the same output without extra work")
        flipArm(true)
        fire("OnTick")
        check(output() == 255 and not lamp.active, "the cabinet publishes after the input pass")
        fire("OnTick")
        check(lamp.active, "the changed output reaches the lamp in the next pass")
        assert(runtime.setWeightPlateSender(playerRegistry, cabinetPlate, ZedComm.SignalModules.ADVANCED_SENDER))
        load = 0
        tick()
        check(output() == 0 and not lamp.active, "a valid advanced fallback of zero is delivered as OFF")
        load = 1150
        tick()
        assert(lamp.active)
        runtime.prepare(playerRegistry)
        runtime.deliver(net:networkOf(inputWire), packets.weight(1150))
        runtime.finish()
        check(output() == nil, "an advanced packet without a byte fallback clears a required cabinet input")
        ZedComm.Simulation.markDirty(net:networkOf(inputWire))
        tick()
        assert(lamp.active)
        local options = optionsAt(cabinetTile)
        assert(options["Disconnect cabinet jack (IN 3)"])()
        assert(queued and queued:isValid() and queued:complete())
        tick()
        check(output() == nil and not lamp.active, "unplugging the arm clears the wired lamp")
        assert(join(cabinetTile, armWire, false, cabinetId, "inputExtension-3"))
        tick()
        check(output() == 255 and lamp.active, "reconnecting adopts the held arm byte")
        panel:linkTerminal("inputExtension-3", "out")
        panel:linkTerminal("and-2", "b")
        tick()
        check(output() == nil and not lamp.active, "cutting an internal arm link clears the cabinet output")
        panel:linkTerminal("inputExtension-3", "out")
        panel:linkTerminal("and-2", "b")
        tick()
        check(output() == 255 and lamp.active, "restoring an internal arm link uses the existing wire reading")

        assert(playerRegistry:renameCabinetPort(cabinetId, "inputExtension-3", "Arm"))
        panel:onMouseDown(160, 89) -- top-edge extension body
        panel:onKeyPress(rotateKey)
        panel:onMouseUp(365, 289)
        check(cabinetPiece().ports["inputExtension-3"] == armWire
            and cabinetPiece().state.circuit.modules["inputExtension-3"].rotation == 180
            and cabinetPiece().state.portLabels["inputExtension-3"] == "Arm",
            "moving a wired extension to another edge preserves its jack identity")
        panel:removePart()
        tick()
        check(output() == nil and not lamp.active and not net:record(armWire).links[cabinetId]
            and not cabinetPiece().state.portLabels["inputExtension-3"]
            and inventory:getFirstType("ZedComm.InputExtension"), "extension removal returns the item and clears its label")
        panel:onMouseDown(420, 152)
        panel:onKeyPress(rotateKey)
        panel:onMouseUp(207, 104)
        check(cabinetPiece().ports["inputExtension-4"] == false and cabinetPiece().ports["inputExtension-3"] == nil,
            "reinstalled extension has a fresh, disconnected jack ID")
        panel:linkTerminal("inputExtension-4", "out")
        panel:linkTerminal("and-2", "b")
        assert(join(cabinetTile, armWire, false, cabinetId, "inputExtension-4"))
        assert(playerRegistry:renameRun(inputWire, "Load"))
        tick()
        assert(lamp.active)
        panel:close()
        load = 80
        playerRegistry, playerJava = start(save(playerJava))
        tick()
        local _, runName = playerRegistry:getRunName(inputWire)
        check(runName == "Load" and armPiece().state.on and runtime.inspect(arm).sourceByte == 255
            and cabinetPiece().ports["inputExtension-4"] == armWire
            and cabinetPiece().state.portLabels.input == "Load"
            and #cabinetPiece().state.circuit.links == 4 and output() == 0 and not lamp.active,
            "reload restores layout, jack identities and names and uses the new load")
        load = 1150
        tick()
        check(output() == 255 and lamp.active, "reloaded circuit responds to the next load")

        local downstreamTile, downstreamWireTile = floorTile(171, 126), floorTile(172, 126)
        local downstreamOK, downstreamId = runPlacement(downstreamTile,
            { kind = "place", item = give("ZedComm.SmallCabinet") })
        assert(downstreamOK)
        local downstream = placement.resolve(playerRegistry, downstreamId)
        local downstreamLayout = { modules = {}, links = {
            { from = "input", output = "out", to = "output", input = "in" },
        } }
        assert(placement.editCircuit(player, playerRegistry, downstream, downstream.piece.state.circuit, downstreamLayout))
        assert(playerRegistry:unlink(outputWire, lampId))
        assert(join(downstreamTile, outputWire, false, downstreamId, "input"))
        local wiredDownstream, downstreamWire = lay(downstreamWireTile, give("ZedComm.SignalWire"), downstreamId, "output")
        assert(wiredDownstream and join(lampTile, downstreamWire, false, lampId, "signal"))
        tick()
        assert(lamp.active)
        load = 80
        fire("OnTick")
        check(output() == 0 and runtime.inspect(downstreamId, "output").sourceByte == 255 and lamp.active,
            "a chained cabinet sees the upstream change on the following pass")
        fire("OnTick")
        check(runtime.inspect(downstreamId, "output").sourceByte == 0 and lamp.active,
            "the chained cabinet schedules its own downstream run")
        fire("OnTick")
        check(not lamp.active and not ZedComm.Simulation.hasPending(), "the two-cabinet chain settles and drains its work")

        local function combinedLoad()
            local secondTile, secondWireTile = floorTile(170, 127), floorTile(170, 126)
            local placedSecond, second = runPlacement(secondTile, { kind = "place", item = give("ZedComm.WeightPlate") })
            assert(placedSecond)
            local extensionItem, adderItem = give("ZedComm.InputExtension"), give("ZedComm.AdderModule")
            assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
            panel:onMouseDown(420, 152)
            for _ = 1, 3 do panel:onKeyPress(rotateKey) end
            panel:onMouseUp(146, 406)
            local secondJack = panel.selected
            panel:onMouseDown(420, 220)
            panel:onMouseUp(106, 244)
            local adderId = panel.selected
            check(not inventory:contains(extensionItem) and not inventory:contains(adderItem)
                and cabinetPiece().state.circuit.modules[adderId].kind == "adder", "the editor installs the Adder and its second jack")
            panel:linkTerminal("input", "out")
            panel:linkTerminal("threshold-1", "in")
            panel:linkTerminal("input", "out")
            panel:linkTerminal(adderId, "a")
            panel:linkTerminal(secondJack, "out")
            panel:linkTerminal(adderId, "b")
            panel:linkTerminal(adderId, "out")
            panel:linkTerminal("threshold-1", "in")
            assert(optionsAt(cabinetTile)["Set threshold"])()
            input = "100"
            confirm()
            local laidSecond, secondWire = lay(secondWireTile, give("ZedComm.SignalWire"), second, "signal")
            assert(laidSecond and join(cabinetTile, secondWire, false, cabinetId, secondJack))
            local function settle()
                tick()
                fire("OnTick")
            end
            plateTile.overlappingVehicle = nil
            plateTile.looseItems = { droppedItem(600) }
            settle()
            check(output() == 0 and not lamp.active, "60 alone stays below the threshold of 100")
            plateTile.looseItems = {}
            secondTile.looseItems = { droppedItem(550) }
            settle()
            check(output() == 0 and not lamp.active, "55 alone stays below the threshold of 100")
            plateTile.looseItems = { droppedItem(600) }
            settle()
            check(output() == 255 and lamp.active, "60 plus 55 trips the armed threshold")
            flipArm(false)
            settle()
            check(output() == 0 and not lamp.active, "the arm switch still cuts the combined load")
            flipArm(true)
            assert(playerRegistry:unlink(secondWire, cabinetId))
            settle()
            check(output() == nil and not lamp.active, "disconnecting one plate clears the sum")
            assert(join(cabinetTile, secondWire, false, cabinetId, secondJack))
            settle()
            check(output() == 255 and lamp.active, "reconnecting restores both held plate readings")
            panel:close()
        end
        combinedLoad()

        local westTile = floorTile(171, 123)
        westTile.westWall = {}
        check(not target(armTile, arm, "set-network-switch", { on = 1 }) and armPiece().state.on,
            "the switch command rejects a non-boolean state")
        assert(target(armTile, arm, "pickup"))
        local savedSwitch = inventory:getFirstType("ZedComm.NetworkSwitch")
        check(savedSwitch and savedSwitch:getModData().zedcommPlacement.state.on
            and not playerRegistry.network:record(armWire).links[arm],
            "picking up an active switch keeps its latch and leaves the run end loose")
        check(placement.previewSprite(westTile, savedSwitch) == "zedcomm_devices_01_470",
            "the placement preview uses the destination wall and the saved latch state")
        local replaced, sameId = runPlacement(westTile, { kind = "place", item = savedSwitch })
        check(replaced and sameId == arm and armObject().sprite == "zedcomm_devices_01_470"
            and armPiece().state.on and armPiece().ports.signal == false,
            "remounting keeps the switch state and uses the west-facing sprite")

        local southTile, eastTile = floorTile(175, 124), floorTile(177, 124)
        floorTile(175, 125).northWall = {}
        floorTile(178, 124).westWall = {}
        assert(target(westTile, arm, "pickup"))
        savedSwitch = inventory:getFirstType("ZedComm.NetworkSwitch")
        check(placement.previewSprite(southTile, savedSwitch) == "zedcomm_devices_01_472",
            "south mounting recognizes the north wall owned by the neighboring tile")
        replaced, sameId = runPlacement(southTile, { kind = "place", item = savedSwitch })
        check(replaced and sameId == arm and armPiece().state.mount == "south"
            and armObject().sprite == "zedcomm_devices_01_472", "south-facing placement preserves the on state")
        armTile = southTile
        flipArm(false)
        tick()
        check(armObject().sprite == "zedcomm_devices_01_471" and runtime.inspect(arm).sourceByte == 0,
            "toggling keeps the south face and publishes zero")
        assert(target(southTile, arm, "pickup"))
        savedSwitch = inventory:getFirstType("ZedComm.NetworkSwitch")
        check(placement.previewSprite(eastTile, savedSwitch) == "zedcomm_devices_01_473",
            "east mounting recognizes the west wall owned by the neighboring tile")
        replaced, sameId = runPlacement(eastTile, { kind = "place", item = savedSwitch })
        check(replaced and sameId == arm and armPiece().state.mount == "east"
            and armObject().sprite == "zedcomm_devices_01_473", "east-facing placement preserves the off state")
        armTile = eastTile
        flipArm(true)
        tick()
        check(armObject().sprite == "zedcomm_devices_01_474" and runtime.inspect(arm).sourceByte == 255,
            "toggling keeps the east face and publishes 255")
        southTile.northWall, southTile.westWall = {}, {}
        check(ZedComm.NetworkSwitch.mount(southTile) == "north", "multiple walls keep north-first preference")
        check(ZedComm.NetworkSwitch.nextMount(southTile, "north") == "west"
            and ZedComm.NetworkSwitch.nextMount(southTile, "west") == "south"
            and ZedComm.NetworkSwitch.nextMount(southTile, "south") == "north",
            "corner rotation cycles eligible walls and skips the open edge")
        assert(target(eastTile, arm, "pickup"))
        savedSwitch = assert(inventory:getFirstType("ZedComm.NetworkSwitch"))
        check(not runPlacement(southTile, { kind = "place", item = savedSwitch, mount = "east" })
            and inventory:contains(savedSwitch), "an ineligible chosen wall cannot consume the switch")
        local corner = menuAt(southTile)
        local placeMenu = corner.children["Place device"] or corner
        assert(placeMenu.children["Place network switch"].options["Mount on west wall"])()
        assert(queued:isValid() and queued:complete())
        check(armPiece().state.mount == "west" and armObject().sprite == "zedcomm_devices_01_470",
            "the corner context menu can mount the carried switch on its non-default wall")

        local logicTile = floorTile(185, 125)
        local logicPlaced, logicId = runPlacement(logicTile, { kind = "place", item = give("ZedComm.SmallCabinet") })
        assert(logicPlaced and optionsAt(logicTile)["Open Small Cabinet"])()
        for ix, kind in ipairs({ "or", "xor", "not" }) do
            local itemType = ZedComm.InternalCircuit.kinds[kind].item
            local item = inventory:getFirstType(itemType) or give(itemType)
            panel:onMouseDown(420, 254 + (ix - 1) * 34)
            panel:onMouseUp(106 + (ix - 1) * 60, 244)
            local logic = playerRegistry.network.pieces[logicId].state.circuit
            check(not inventory:contains(item) and logic.modules[panel.selected].kind == kind,
                "cabinet editor installs the " .. kind .. " module from the carried pane")
        end
        panel:render()
        panel:close()
    end
    cabinetScenario()

    local function placeTestItem(tile, itemType)
        local ok, id = runPlacement(tile, { kind = "place", item = give(itemType) })
        assert(ok, id)
        return id
    end

    local function runTestWire(tile, source, from, targetTile, receiver, port)
        local ok, wire = lay(tile, give("ZedComm.SignalWire"), source, from)
        assert(ok and join(targetTile, wire, false, receiver, port))
        return wire
    end

    local function packetScenario()
        playerRegistry, playerJava = start()
        local plateTile, cabinetTile, displayTile = floorTile(193, 124), floorTile(195, 124), floorTile(197, 124)
        local plateId = placeTestItem(plateTile, "ZedComm.WeightPlate")
        local cabinetId = placeTestItem(cabinetTile, "ZedComm.AdvancedSmallCabinet")
        local displayId = placeTestItem(displayTile, "ZedComm.AdvancedDisplay")
        assert(runtime.setWeightPlateSender(playerRegistry, plateId, ZedComm.SignalModules.ADVANCED_SENDER))
        local mass = 1150.25
        plateTile.overlappingVehicle = { getMass = function() return mass end }
        local inputWire = runTestWire(floorTile(194, 124), plateId, "signal", cabinetTile, cabinetId, "input")
        runTestWire(floorTile(196, 124), cabinetId, "output", displayTile, displayId, "signal")
        assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
        local cache = give("ZedComm.CacheModule")
        panel.nextPage.click()
        panel:onMouseDown(420, 84)
        panel:onMouseUp(166, 184)
        local cacheId = panel.selected
        check(not inventory:contains(cache) and cacheId ~= nil, "the carried palette can install Cache on its second page")
        panel.configureButton.click()
        panel:linkTerminal("input", "out")
        panel:linkTerminal(cacheId, "data")
        panel:linkTerminal(cacheId, "out")
        panel:linkTerminal("output", "in")
        local function shown()
            fire("OnTick")
            fire("OnTick")
            local _, _, attached, received = placedReading(displayId)
            assert(attached)
            return received
        end
        check(shown().value == 115, "advanced display receives only the byte from a basic output")
        panel:onMouseDown(345, 96)
        panel:onMouseUp(345, 96)
        panel.configureButton.click()
        check(shown().value.amount == 1150.25, "advanced output delivers full weight through a native placed receiver")
        mass = 1150.75
        local received = shown()
        check(received.value.amount == 1150.75 and received.basicValue == 115,
            "a change beneath fallback resolution reaches the advanced display")
        received.value.amount = 0
        check(shown().value.amount == 1150.75, "the readout exposes a copy of the held packet")
        local oldSay, said = player.Say
        function player:Say(line) said = line end
        assert(optionsAt(displayTile)["Read full signal"])()
        player.Say = oldSay
        check(said and said:find("1150.75 kg", 1, true), "advanced display context action shows value and unit")
        panel:close()
        assert(playerRegistry:unlink(inputWire, cabinetId))
        check(shown() == nil, "advanced display clears when the data run is cut")
        assert(join(cabinetTile, inputWire, false, cabinetId, "input"))
        playerRegistry, playerJava = start(save(playerJava))
        check(shown().value.amount == 1150.75, "output mode and Cache settings restore after reload")

        assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
        panel.selected = cacheId
        panel:removePart()
        give("ZedComm.MultiplierModule")
        give("ZedComm.BatterySourceModule")
        panel.nextPage.click()
        panel:onMouseDown(420, 152)
        panel:onMouseUp(166, 184)
        local multiplierId = panel.selected
        panel.configureButton.click()
        panel:onMouseDown(420, 288)
        panel:onMouseUp(226, 214)
        local batteryId = panel.selected
        panel.configureButton.click()
        input = "4"
        confirm()
        give("Base.Battery"):setUsedDelta(0.8)
        panel.batteryButton.click()
        panel:linkTerminal("input", "out")
        panel:linkTerminal(multiplierId, "a")
        panel:linkTerminal(batteryId, "out")
        panel:linkTerminal(multiplierId, "b")
        panel:linkTerminal(multiplierId, "out")
        panel:linkTerminal("output", "in")
        local full = shown()
        check(full.value.amount == 4603 and full.basicValue == 255,
            "player-configured full multiplier and battery factor deliver the uncapped typed result")
        panel.selected = "output"
        panel.configureButton.click()
        check(shown().value == 255, "the same math output supplies the generated capped fallback in Basic mode")
        panel:close()
    end
    packetScenario()

    local function splitterScenario()
        playerRegistry, playerJava = start()
        local plateTile, cabinetTile = floorTile(220, 124), floorTile(222, 124)
        local firstTile, secondTile = floorTile(224, 124), floorTile(222, 126)
        local plate = placeTestItem(plateTile, "ZedComm.WeightPlate")
        local cabinet = placeTestItem(cabinetTile, "ZedComm.SmallCabinet")
        local first = placeTestItem(firstTile, "ZedComm.AdvancedDisplay")
        local second = placeTestItem(secondTile, "ZedComm.AdvancedDisplay")
        plateTile.overlappingVehicle = { getMass = function() return 1150.25 end }
        assert(runtime.setWeightPlateSender(playerRegistry, plate, ZedComm.SignalModules.ADVANCED_SENDER))
        local function record() return playerRegistry.network:record(cabinet) end
        local function reading(id)
            fire("OnTick")
            fire("OnTick")
            local _, _, _, packet = placedReading(id)
            return packet and packet.value
        end
        check(record().state.adapter == "basic", "a new default cabinet has a Basic Adapter")
        assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
        local splitter = give("ZedComm.SplitterModule")
        local extension = give("ZedComm.OutputExtension")
        panel.nextPage.click()
        panel:onMouseDown(420, 322)
        panel:onMouseUp(166, 184)
        check(inventory:contains(splitter) and record().state.circuit.modules["splitter-1"] == nil,
            "dropping the splitter in the middle leaves it in inventory")
        panel:onMouseDown(420, 322)
        panel:onMouseUp(46, 244)
        local splitterId = assert(panel.selected)
        panel.previousPage.click()
        panel:onMouseDown(420, 186)
        panel:onMouseUp(346, 244)
        local extensionId = assert(panel.selected)
        check(not inventory:contains(splitter) and not inventory:contains(extension),
            "the editor installs the output extension on the right without rotating it")
        panel:linkTerminal("input", "out")
        panel:linkTerminal(splitterId, "in")
        panel:linkTerminal(splitterId, "outA")
        panel:linkTerminal("output", "in")
        panel:linkTerminal(splitterId, "outB")
        panel:linkTerminal(extensionId, "in")
        local inRun = runTestWire(floorTile(221, 124), plate, "signal", cabinetTile, cabinet, "input")
        local firstRun = runTestWire(floorTile(223, 124), cabinet, "output", firstTile, first, "signal")
        local secondRun = runTestWire(floorTile(222, 125), cabinet, extensionId, secondTile, second, "signal")
        assert(playerRegistry:renameRun(firstRun, "First branch"))
        assert(playerRegistry:renameRun(secondRun, "Second branch"))
        local firstName, secondName = playerRegistry:getRunName(firstRun), playerRegistry:getRunName(secondRun)
        check(reading(first) == 115 and reading(second) == 115, "Basic cabinet delivers a byte to both split runs")
        panel.selected = "output"
        panel.configureButton.click()
        check(not record().state.circuit.outputModes, "Basic cabinet editor leaves both outputs in byte mode")
        panel:close()

        local upgrade = give("ZedComm.AdvancedAdapter")
        assert(optionsAt(cabinetTile)["Upgrade cabinet with Advanced Adapter"])()
        inventory.full = true
        check(not queued:complete() and inventory:contains(upgrade) and record().state.adapter == "basic",
            "failed cabinet upgrade returns the Advanced Adapter")
        inventory.full = false
        assert(optionsAt(cabinetTile)["Upgrade cabinet with Advanced Adapter"])()
        assert(queued:isValid() and queued:complete())
        local upgraded = record()
        check(not inventory:contains(upgrade) and inventory:getFirstType("ZedComm.BasicAdapter")
            and upgraded.state.adapter == "advanced" and #upgraded.state.circuit.links == 3
            and upgraded.ports.input == inRun and upgraded.ports.output == firstRun
            and upgraded.ports[extensionId] == secondRun, "upgrade returns the Basic Adapter and preserves circuit and runs")
        check(playerRegistry:getRunName(firstRun) == firstName and playerRegistry:getRunName(secondRun) == secondName,
            "cabinet upgrade keeps both splitter run names")
        assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
        panel.selected = "output"
        panel.configureButton.click()
        check(reading(first).amount == 1150.25 and reading(second) == 115, "splitter branches respect their own output modes")
        panel.selected = extensionId
        panel.configureButton.click()
        check(reading(second).amount == 1150.25, "both splitter runs can deliver the full reading")
        assert(playerRegistry:unlink(secondRun, second))
        check(reading(first).amount == 1150.25 and reading(second) == nil, "unplugging a branch leaves the other live")
        assert(join(secondTile, secondRun, false, second, "signal"))
        assert(playerRegistry:unlink(inRun, cabinet))
        check(reading(first) == nil and reading(second) == nil, "unplugging the one input clears both branches")
        assert(join(cabinetTile, inRun, false, cabinet, "input"))
        panel:close()
        playerRegistry, playerJava = start(save(playerJava))
        check(record().state.adapter == "advanced" and reading(first).amount == 1150.25
            and reading(second).amount == 1150.25, "upgrade and both splitter routes restore on reload")
        assert(target(cabinetTile, cabinet, "pickup"))
        local moved = floorTile(226, 124)
        local item = assert(inventory:getFirstType("ZedComm.AdvancedSmallCabinet"))
        assert(runPlacement(moved, { kind = "place", item = item }))
        check(record().state.adapter == "advanced" and #record().state.circuit.links == 3,
            "replacing a picked-up cabinet preserves its adapter grade and circuit")
    end
    splitterScenario()

    local function timingScenario()
        playerRegistry, playerJava = start()
        local previousTime, previousItems = getGameTime, ItemContainer
        local delta, powered = 0, false
        getGameTime = function()
            return { getRealworldSecondsSinceLastUpdate = function() return delta end }
        end
        ItemContainer = { isObjectPowered = function(_, allowGenerator) return powered and allowGenerator end }
        local function seconds(value)
            delta = value
            fire("OnTick")
            delta = 0
            fire("OnTick")
        end
        local sourceTile, cabinetTile, displayTile = floorTile(203, 124), floorTile(205, 124), floorTile(207, 124)
        local inputId = placeTestItem(sourceTile, "ZedComm.DebugByteSource")
        local cabinetId = placeTestItem(cabinetTile, "ZedComm.SmallCabinet")
        local displayId = placeTestItem(displayTile, "ZedComm.NumericDisplay")
        local inputWire = runTestWire(floorTile(204, 124), inputId, "signal", cabinetTile, cabinetId, "input")
        runTestWire(floorTile(206, 124), cabinetId, "output", displayTile, displayId, "signal")
        assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
        panel.nextPage.click()
        give("ZedComm.TimerModule")
        give("ZedComm.WaitModule")
        panel:onMouseDown(420, 186)
        panel:onMouseUp(166, 244)
        local timer = panel.selected
        panel:onMouseDown(420, 220)
        panel:onMouseUp(106, 124)
        local wait = panel.selected
        panel:linkTerminal("input", "out")
        panel:linkTerminal(wait, "in")
        panel:linkTerminal(wait, "out")
        panel:linkTerminal(timer, "in")
        panel:linkTerminal(timer, "out")
        panel:linkTerminal("output", "in")
        seconds(0)
        assert(runtime.setTestByte(playerRegistry, inputId, 255))
        seconds(0)
        check(placedReading(displayId) == 0, "a native cabinet starts with Wait's OFF output")
        seconds(2)
        check(placedReading(displayId) == 255, "the cabinet runs scheduled Wait and Timer even with a quiet wire")
        assert(runtime.setTestByte(playerRegistry, inputId, 0))
        seconds(0)
        check(placedReading(displayId) == 255, "timer holds ON after valid zero")
        seconds(10)
        check(placedReading(displayId) == 0, "timer expiration publishes OFF through the normal dispatch pass")
        assert(runtime.setTestByte(playerRegistry, inputId, 255))
        seconds(0)
        seconds(2)
        assert(playerRegistry:unlink(inputWire, cabinetId))
        seconds(0)
        check(placedReading(displayId) == nil, "disconnect cancels the live timing chain")
        panel:close()

        cabinetTile, displayTile = floorTile(213, 124), floorTile(215, 124)
        cabinetId = placeTestItem(cabinetTile, "ZedComm.SmallCabinet")
        displayId = placeTestItem(displayTile, "ZedComm.NumericDisplay")
        runTestWire(floorTile(214, 124), cabinetId, "output", displayTile, displayId, "signal")
        assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
        panel.nextPage.click()
        give("ZedComm.MainsSourceModule")
        panel:onMouseDown(420, 254)
        panel:onMouseUp(106, 94)
        local mains = panel.selected
        panel.configureButton.click()
        input = "37"
        confirm()
        panel:linkTerminal(mains, "out")
        panel:linkTerminal("output", "in")
        seconds(0)
        check(placedReading(displayId) == nil, "a placed mains source waits for host power")
        powered = true
        seconds(0)
        check(placedReading(displayId) == 37, "power recovery sends the tuned byte without changes to wiring")
        powered = false
        seconds(0)
        check(placedReading(displayId) == nil, "power loss clears the source run")
        panel.selected = mains
        panel:removePart()
        give("ZedComm.BatterySourceModule")
        panel:onMouseDown(420, 288)
        panel:onMouseUp(106, 94)
        local batterySource = panel.selected
        panel:linkTerminal(batterySource, "out")
        panel:linkTerminal("output", "in")
        panel.selected = batterySource
        local battery = give("Base.Battery")
        battery:setUsedDelta(0.45)
        panel.batteryButton.click()
        seconds(0)
        check(not inventory:contains(battery) and placedReading(displayId) == 255,
            "installing a battery powers the source without mains")
        panel.batteryButton.click()
        seconds(0)
        check(inventory:getFirstType("Base.Battery"):getCurrentUsesFloat() == 0.45
            and placedReading(displayId) == nil, "battery removal returns its charge and clears the signal")
        panel:close()
        getGameTime, ItemContainer = previousTime, previousItems
    end
    timingScenario()

    getTexture, UIFont, ISMouseDrag = originalTexture, originalFont, originalDrag
    KeybindId, Keyboard = originalBindings, originalKeyboard
    getDebug, getCore = previousDebug, previousCore
end

print = realPrint
print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
