-- Singleplayer disposable-save fixture. Its native component owns all fluid.
if isClient() or isServer() then return end
require "ZedComm/DeviceDefinitions"
require "ZedComm/SignalModules"
require "ZedComm/Devices/EnvironmentalSensors"

local definitionId = "ZedCommProbe.RainGauge"
local Definitions = ZedComm.DeviceDefinitions
local function read(object)
    local container = object:getFluidContainer()
    return container and container:getAmount() or nil
end
assert(Definitions.register({
    id = definitionId, role = "source", ports = { "signal" }, readingKind = "fluidVolume",
    match = function(object, context) return context.getDefinitionId(object) == definitionId end,
    sample = read,
}))

-- Index only loaded probe coordinates. Resolve the square from the live cell
-- before each increment; a removed object or an unloaded chunk earns no rain.
local loaded = {}
local function key(square)
    return square:getX() .. "," .. square:getY() .. "," .. square:getZ()
end
local function find(square)
    if not square then return end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local tag = Definitions.readFixtureTag(object)
        if tag and tag.definitionId == definitionId then return object end
    end
end
local function track(square)
    if find(square) then loaded[key(square)] = { square:getX(), square:getY(), square:getZ() } end
end
Events.LoadGridsquare.Add(track)
Events.EveryOneMinute.Add(function()
    local climate = getClimateManager()
    for id, pos in pairs(loaded) do
        local square = getCell():getGridSquare(pos[1], pos[2], pos[3])
        local object = find(square)
        if not object then
            loaded[id] = nil
        else
            local container = object:getFluidContainer()
            local rain = ZedComm.EnvironmentalSensors.rainIntensity(square, climate)
            if container and rain and rain > 0 then
                local increment = math.min(container:getFreeCapacity(), rain / 60)
                if increment > 0 then container:addFluid(FluidType.TaintedWater, increment) end
            end
        end
    end
end)

ZedCommRainGaugeProbe = {}
function ZedCommRainGaugeProbe.place(square)
    assert(square and not find(square), "Choose a loaded square without a probe.")
    local object = IsoObject.new(square, "zedcomm_devices_01_425", "Rain Gauge Probe")
    local container = ComponentType.FluidContainer:CreateComponent()
    container:setCapacity(1)
    GameEntityFactory.AddComponent(object, true, container)
    assert(object:getFluidContainer(), "Native component attachment failed.")
    local id = "rain-gauge-probe-" .. key(square)
    object:getModData().zedcomm = {
        id = id, kind = "endpoint", definitionId = definitionId,
        state = { senderModule = { id = ZedComm.SignalModules.ADVANCED_SENDER } },
    }
    square:AddTileObject(object)
    track(square)
    triggerEvent("OnObjectAdded", object)
    return id
end
