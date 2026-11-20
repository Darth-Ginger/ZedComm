require "ZedComm/DeviceDefinitions"
require "ZedComm/InternalCircuit"
require "ZedComm/SignalModules"

local Door = { ID = ZedComm.InternalCircuit.DOOR_ID }

function Door.isEligible(object)
    if not object or not (instanceof(object, "IsoDoor")
        or (instanceof(object, "IsoThumpable") and object:isDoor())) then return false end
    return object:getSquare() ~= nil and not object:isDestroyed()
        and IsoDoor.getDoubleDoorIndex(object) == -1 and IsoDoor.getGarageDoorIndex(object) == -1
end

function Door.oppositeSquare(object)
    local square = object:getSquare()
    local north = object:isNorth()
    local x, y = square:getX(), square:getY()
    return getCell():getGridSquare(north and x or x - 1, north and y - 1 or y, square:getZ())
end

function Door.reverseHinge(object)
    local sprite = object:getOpenSprite()
    local props = sprite and sprite:getProperties()
    return props ~= nil and (props:has("attachedE") or props:has("attachedS"))
end

local Controller = {}
Controller.__index = Controller

local function setLock(object, locked, keyed)
    -- Native setLockedByKey also sets the general locked flag.
    if object:isLockedByKey() ~= keyed then object:setLockedByKey(keyed) end
    if object:isLocked() ~= locked then object:setIsLocked(locked) end
end

function Controller:adapter(action)
    local controller = self
    return {
        apply = function(_, desired)
            if controller.requests[action] ~= desired then
                controller.requests[action], controller.results[action] = desired, nil
            end
            local result = controller.results[action]
            return result and result.status or "unavailable", result and result.reason
        end,
        release = function()
            controller.requests[action], controller.results[action] = nil, nil
        end,
    }
end

local function moveDoor(object, desired)
    if object:isOpen() == desired then return "applied" end
    if object:isBarricaded() or object:isObstructed() then return "unavailable", "Door is obstructed or barricaded." end
    if desired then
        object:ToggleDoorActual(getSpecificPlayer(0))
    else
        object:ToggleDoorSilent()
    end
    if object:isOpen() ~= desired then return "unavailable", "Door rejected the requested state." end
    if not desired then
        -- Silent toggles skip the native collision, path and render refreshes.
        local square = object:getSquare()
        square:RecalcAllWithNeighbours(true)
        square:setSquareChanged()
        object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
        triggerEvent("OnContainerUpdate")
    end
    return "applied"
end

function Controller:flush()
    if self.busy then return end
    self.busy = true
    local object, requests = self.object, self.requests
    if isClient() or isServer() then
        for action in pairs(requests) do self.results[action] = { status = "unsupported", reason = "Door retrofit is singleplayer only." } end
        self.busy = false
        return
    end
    if not Door.isEligible(object) then
        for action in pairs(requests) do self.results[action] = { status = "unavailable", reason = "Door is unavailable." } end
        self.busy = false
        return
    end
    local lock, open = requests.lockAction, requests.openAction
    if lock ~= nil then
        if not self.ownsLock then
            if self.nativeLock then
                self.originalLock, self.originalKey = self.nativeLock.locked, self.nativeLock.keyed
            else
                self.originalLock, self.originalKey = object:isLocked(), object:isLockedByKey()
            end
            self.ownsLock = true
        end
        if not lock then setLock(object, false, false); self.lockedApplied = false end
    elseif self.ownsLock then
        setLock(object, self.originalLock, self.originalKey)
        self.ownsLock, self.lockedApplied = false, false
    end
    if open ~= nil then
        local status, reason
        if open and lock then
            status, reason = "unavailable", "Lock request prevents opening."
        elseif open and (object:isLocked() or object:isLockedByKey()
            or (instanceof(object, "IsoThumpable") and (object:isLockedByPadlock() or object:getLockedByCode() ~= 0))) then
            status, reason = "unavailable", "Door is mechanically locked."
        else
            status, reason = moveDoor(object, open)
        end
        self.results.openAction = { status = status, reason = reason }
    end
    if lock then
        -- Closing here corrects a native bypass of an already-applied lock.
        if self.lockedApplied and object:isOpen() then moveDoor(object, false) end
        if object:isOpen() then
            self.results.lockAction = { status = "unavailable", reason = "Lock pending until the door closes." }
        else
            setLock(object, true, true)
            self.lockedApplied = object:isLocked() and object:isLockedByKey()
            self.results.lockAction = { status = self.lockedApplied and "applied" or "unavailable" }
        end
    elseif lock == false then
        self.results.lockAction = { status = "applied" }
    end
    self.busy = false
end

function Controller:release()
    self.requests, self.results = {}, {}
    self:flush()
end

function Door.bindFixture(object, context, nativeLock)
    return setmetatable({ object = object, nativeLock = nativeLock, requests = {}, results = {} }, Controller)
end

local ok, reason = ZedComm.DeviceDefinitions.register({
    id = Door.ID, role = "receiver", ports = { "lock", "open" },
    match = function(object, context)
        return context.getDefinitionId(object) == Door.ID and Door.isEligible(object)
    end,
    receiverModule = ZedComm.SignalModules.ON_OFF,
    bindFixture = Door.bindFixture,
})
if not ok then error(Door.ID .. ": " .. reason) end
ZedComm.Door = Door
return Door
