-- ZedComm server registry: saves every ZedComm piece and rebuilds the network
-- model from it on load (Implement Endpoints And Cables).
--
-- Built on the game's global object system (SGlobalObjectSystem), which saves
-- one record per x,y,z to its own file and keeps it while the chunk is
-- unloaded. ZedComm lets several pieces share a square, so each square's
-- record holds a table of piece records keyed by id (Network:record format),
-- and the vanilla helpers that assume one object per square are overridden:
--
--   loadIsoObject           - registers a piece only if its id is missing,
--                             never touching the square's other pieces
--   OnObjectAboutToBeRemoved - removes that one piece, and the square's
--                             record only once it is empty
--   OnChunkLoaded           - drops piece records whose world object is gone,
--                             matching by id, not first object on the square
--
-- World objects carry modData.zedcomm = { id, kind, role? } and nothing else;
-- links live only here. The model is rebuilt from these records when the
-- system starts, so connectivity is derived, not stored twice.
--
-- Multiplayer client sync is not done yet: the client hooks are no-ops until
-- the post-MVP multiplayer work (ADR-305, step 7).

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "Map/SGlobalObject"
require "ZedComm/Network"
require "ZedComm/Simulation"

local Network = ZedComm.Network

local function log(message) print("[ZedComm] registry: " .. message) end

-- The ZedComm tag on a world object, or nil.
local function tagOf(isoObject)
    if not isoObject or not isoObject.hasModData or not isoObject:hasModData() then return nil end
    local tag = isoObject:getModData().zedcomm
    if type(tag) ~= "table" or type(tag.id) ~= "string" then return nil end
    return tag
end

---------------------------------------------------------------------------
-- One square's record
---------------------------------------------------------------------------

SZedCommTile = SGlobalObject:derive("SZedCommTile")

function SZedCommTile:new(luaSystem, globalObject)
    return SGlobalObject.new(self, luaSystem, globalObject)
end

function SZedCommTile:initNew()
    self.pieces = {}
end

-- Called only through the vanilla loadIsoObject, which the system overrides.
function SZedCommTile:stateFromIsoObject(isoObject)
    self.pieces = self.pieces or {}
end

function SZedCommTile:stateToIsoObject(isoObject)
end

---------------------------------------------------------------------------
-- The system
---------------------------------------------------------------------------

SZedCommSystem = SGlobalObjectSystem:derive("SZedCommSystem")

function SZedCommSystem:new()
    return SGlobalObjectSystem.new(self, "zedcomm")
end

function SZedCommSystem:initSystem()
    SGlobalObjectSystem.initSystem(self)
    self.system:setModDataKeys(nil)
    self.system:setObjectModDataKeys({ "pieces" })
end

function SZedCommSystem:newLuaObject(globalObject)
    return SZedCommTile:new(self, globalObject)
end

function SZedCommSystem:isValidIsoObject(isoObject)
    return tagOf(isoObject) ~= nil
end

-- Multiplayer sync comes later; nothing on the client listens yet.
function SZedCommSystem:newLuaObjectOnClient(luaObject) end
function SZedCommSystem:removeLuaObjectOnClient(luaObject) end
function SZedCommSystem:updateLuaObjectOnClient(luaObject) end

-- Saved records loaded: rebuild the model and hand it to the simulation.
function SZedCommSystem:initLuaObjects()
    SGlobalObjectSystem.initLuaObjects(self)
    self:rebuildNetwork()
end

function SZedCommSystem:rebuildNetwork()
    local records = {}
    for i = 1, self:getLuaObjectCount() do
        local tile = self:getLuaObjectByIndex(i)
        for _, r in pairs(tile.pieces or {}) do records[#records + 1] = r end
    end
    table.sort(records, function(a, b) return a.id < b.id end)
    local network = Network.new()
    local dropped = network:load(records)
    for i = 1, #dropped do log("dropped on load: " .. dropped[i]) end
    network:attach(ZedComm.Simulation)
    self.network = network
    -- Write back what the model accepted, so dropped links leave the save.
    for i = 1, #records do self:syncPiece(records[i].id, records[i].x, records[i].y, records[i].z) end
    log("loaded " .. #records .. " piece(s) in " .. network:networkCount() .. " network(s)")
end

-- Copy one piece's record from the model into its square's record, creating
-- or deleting the square's record as needed.
function SZedCommSystem:syncPiece(id, x, y, z)
    local r = self.network:record(id)
    local tile = self:getLuaObjectAt(x, y, z)
    if r then
        if not tile then
            tile = self:newLuaObjectAt(x, y, z)
            tile:initNew()
        end
        tile.pieces[id] = r
    elseif tile then
        tile.pieces[id] = nil
        -- Keep the tile while another piece remains; avoid the next global.
        for _ in pairs(tile.pieces) do return end
        self:removeLuaObject(tile)
    end
end

local function syncAll(self, ids)
    for i = 1, #ids do
        local piece = self.network.pieces[ids[i]]
        if piece then self:syncPiece(ids[i], piece.x, piece.y, piece.z) end
    end
end

---------------------------------------------------------------------------
-- Changes. Placement, removal and wiring actions call these on the server.
---------------------------------------------------------------------------

-- Register a tagged world object that is now on a square.
function SZedCommSystem:addPiece(isoObject)
    local tag, square = tagOf(isoObject), isoObject and isoObject:getSquare()
    if not tag or not square then return false, "not a placed ZedComm object" end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local ok, err
    if tag.kind == "cable" then
        ok, err = self.network:addCable(tag.id, x, y, z)
    elseif tag.kind == "endpoint" then
        ok, err = self.network:addEndpoint(tag.id, x, y, z, tag.role, tag.ports, tag.value)
    else
        ok, err = false, "unknown kind " .. tostring(tag.kind)
    end
    if not ok then
        log("cannot register " .. tag.id .. ": " .. err)
        return false, err
    end
    self:syncPiece(tag.id, x, y, z)
    return true
end

-- Remove a piece and its links; linked pieces stay placed (ADR-304).
function SZedCommSystem:removePiece(id)
    local piece = self.network.pieces[id]
    if not piece then return false, "unknown piece" end
    local partners = self.network:partners(id)
    local x, y, z = piece.x, piece.y, piece.z
    self.network:remove(id)
    self:syncPiece(id, x, y, z)
    syncAll(self, partners)
    return true
end

function SZedCommSystem:link(cableId, otherId, port)
    local ok, err = self.network:link(cableId, otherId, port)
    if ok then syncAll(self, { cableId, otherId }) end
    return ok, err
end

function SZedCommSystem:unlink(cableId, otherId)
    local ok, err = self.network:unlink(cableId, otherId)
    if ok then syncAll(self, { cableId, otherId }) end
    return ok, err
end

-- A source endpoint's byte changed. The value is saved with its record.
function SZedCommSystem:setValue(id, value)
    local ok, err = self.network:setValue(id, value)
    if ok then syncAll(self, { id }) end
    return ok, err
end

---------------------------------------------------------------------------
-- Vanilla hooks, made safe for several pieces on one square
---------------------------------------------------------------------------

-- A tagged object appeared (placement, or a load of an object the registry
-- has no record of). Registers it only if its id is new.
function SZedCommSystem:loadIsoObject(isoObject)
    local tag = tagOf(isoObject)
    if not tag or not isoObject:getSquare() then return end
    if self.network.pieces[tag.id] then return end
    self:addPiece(isoObject)
end

function SZedCommSystem:OnObjectAboutToBeRemoved(isoObject)
    local tag = tagOf(isoObject)
    if not tag then return end
    self:removePiece(tag.id)
end

-- A chunk with ZedComm records loaded: drop records whose object is gone.
-- A square that is not loaded means unavailable, not destroyed.
function SZedCommSystem:OnChunkLoaded(wx, wy)
    local globalObjects = self.system:getObjectsInChunk(wx, wy)
    local stale = {}
    for i = 1, globalObjects:size() do
        local globalObject = globalObjects:get(i - 1)
        local square = getCell():getGridSquare(globalObject:getX(), globalObject:getY(), globalObject:getZ())
        if square then
            local present = {}
            local objects = square:getObjects()
            for j = 0, objects:size() - 1 do
                local tag = tagOf(objects:get(j))
                if tag then present[tag.id] = true end
            end
            local tile = globalObject:getModData()
            for id in pairs(tile.pieces or {}) do
                if not present[id] then stale[#stale + 1] = id end
            end
        end
    end
    self.system:finishedWithList(globalObjects)
    for i = 1, #stale do
        log("world object for " .. stale[i] .. " is gone; dropping its record")
        self:removePiece(stale[i])
    end
end

SGlobalObjectSystem.RegisterSystemClass(SZedCommSystem)

ZedComm = ZedComm or {}
ZedComm.Registry = SZedCommSystem
