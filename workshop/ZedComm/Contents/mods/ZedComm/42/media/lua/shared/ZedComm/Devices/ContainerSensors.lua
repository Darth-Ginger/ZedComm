-- Sources read the same native storage quantities the inventory page displays.
local Contact = require "ZedComm/Devices/DoorContact"
local Sensors = { STORAGE = "ZedComm.StorageSensor", FLUID = "ZedComm.FluidFillSensor" }

local function spriteName(object)
    local sprite = object and object:getSprite()
    return sprite and sprite:getName()
end

local function storageType(host)
    local name = spriteName(host)
    if not name then return nil end
    if name:match("^carpentry_01_1[6-9]$") then return "crate" end
    local shelf = tonumber(name:match("^crafted_05_(%d+)$"))
    if shelf and shelf >= 36 and shelf <= 43 then return "shelves" end
end

local function containerAt(host, index)
    if type(index) ~= "number" or index < 0 or index ~= math.floor(index)
        or index >= host:getContainerCount() then return nil end
    local container = host:getContainerByIndex(index)
    if container and container:getParent() == host then return container end
end

function Sensors.compartments(host)
    local result = {}
    local kind = storageType(host)
    if kind then
        for index = 0, host:getContainerCount() - 1 do
            local container = containerAt(host, index)
            if container then
                result[#result + 1] = { index = index, container = container }
            end
        end
    end
    return result
end

function Sensors.storageState(host, selection, mode)
    if not host or not storageType(host) or type(selection) ~= "table"
        or (mode ~= "fullness" and mode ~= "free") then return nil end
    local container = containerAt(host, selection.index)
    if not container or container ~= selection.container then return nil end
    return { compartment = selection.index, containerType = container:getType(),
        compartmentCount = host:getContainerCount(), mode = mode }
end

local function byte(amount, capacity, free)
    if type(amount) ~= "number" or amount ~= amount or math.abs(amount) == math.huge
        or type(capacity) ~= "number" or capacity <= 0 or capacity ~= capacity or capacity == math.huge then return nil end
    local fraction = math.min(1, math.max(0, amount / capacity))
    return math.floor((free and (1 - fraction) or fraction) * 255 + 0.5)
end

local function storageSample(host, _, state)
    if type(state) ~= "table" or host:getContainerCount() ~= state.compartmentCount
        or (state.mode ~= "fullness" and state.mode ~= "free") then return nil end
    local container = containerAt(host, state.compartment)
    local player = getSpecificPlayer(0)
    if not container or container:getType() ~= state.containerType or not player then return nil end
    return byte(container:getCapacityWeight(), container:getEffectiveCapacity(player), state.mode == "free")
end

local function collectorHost(host)
    return spriteName(host) == "carpentry_02_54"
end

Contact.register(Sensors.STORAGE, {
    name = "Storage Sensor",
    sprite = "zedcomm_contact_floor_01_0",
    matchHost = storageType,
    canFit = function(host) return #Sensors.compartments(host) > 0 end,
    installState = function(host, selection) return Sensors.storageState(host, selection, "fullness") end,
    sample = storageSample,
})

Contact.register(Sensors.FLUID, {
    name = "Fluid Fill Sensor",
    sprite = "zedcomm_contact_floor_01_0",
    matchHost = collectorHost,
    canFit = function(host) return collectorHost(host) and host:getFluidContainer() ~= nil end,
    sample = function(host)
        local container = host:getFluidContainer()
        if container then return byte(container:getAmount(), container:getCapacity()) end
    end,
})

ZedComm.ContainerSensors = Sensors
return Sensors
