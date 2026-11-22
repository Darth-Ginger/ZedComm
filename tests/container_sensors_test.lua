local test = dofile("tests/support/editor_harness.lua")()
local check, fire = test.check, test.fire
local Sensors, Contact = ZedComm.ContainerSensors, ZedComm.DoorContact

if test.GAME then
    local file = assert(io.open(test.PZ .. "/client/ISUI/ISInventoryPage.lua", "r"))
    local inventoryPage = file:read("*a")
    file:close()
    check(inventoryPage:find("inv:getCapacityWeight()", 1, true)
        and inventoryPage:find("inventory:getEffectiveCapacity(playerObj)", 1, true)
        and inventoryPage:find("o:getContainerByIndex(containerIndex-1)", 1, true),
        "installed inventory page uses the sensor's weight, capacity, and compartment APIs")
end

local labels = {
    StorageSensor = "Storage Sensor", FluidFillSensor = "Fluid Fill Sensor",
    FitStorageSensor = "Fit %1", FitFluidFillSensor = "Fit fluid fill sensor",
    StorageCompartment = "%1. %2", StorageOutput = "%1 - %2", StorageSelected = "%1 (selected)",
    StorageFree = "Free capacity", StorageFullness = "Fullness", RemoveSensor = "Remove sensor",
}
function getText(key, ...)
    local args = { ... }
    return (labels[key:match("^IGUI_ZedComm_(.+)$")] or key):gsub("%%(%d)", function(i) return args[tonumber(i)] end)
end
function getTextOrNull() return nil end

test.give("Base.Screwdriver")
test.player.electrical = 1
test.player.isTimedActionInstant = function() return false end
local function host(tile, sprite)
    local object = test.worldObject(tile)
    function object:getSprite() return { getName = function() return sprite end } end
    object.compartments = {}
    function object:getContainerCount() return #self.compartments end
    function object:getContainerByIndex(index) return self.compartments[index + 1] end
    function object:getFluidContainer() return self.fluid end
    return object
end

local function compartment(object, label, used, effective)
    local container = { used = used, effective = effective }
    function container:getParent() return object end
    function container:getType() return "shelves" end
    function container:getCustomName() return label end
    function container:getCapacityWeight() return self.used end
    function container:getEffectiveCapacity(player) assert(player == test.player); return self.effective end
    object.compartments[#object.compartments + 1] = container
    return container
end

local function queue(tile, name, label)
    assert(test.optionsAt(tile, name)[label], label)()
    return test.queued
end

local function reading(tile, id)
    local outputTile = test.floorTile(tile:getX() + 1, tile:getY())
    local output = test.placeTestItem(outputTile, "ZedComm.NumericDisplay")
    local wire = test.runTestWire(tile, id, "signal", outputTile, output, "signal")
    return function() return test.placedReading(output) end, wire
end

local crateTile = test.floorTile(412, 413)
local crate = host(crateTile, "carpentry_01_16")
compartment(crate, "Crate", 60, 60)
local storageItem = test.give(Sensors.STORAGE)
local fit = queue(crateTile, "Storage Sensor", "Fit 1. Crate")
check(fit.maxTime == 120 and fit:isValid() and fit:complete(), "crate fitting uses the timed action")
local crateId = assert(crate:getModData().zedcommContact)
check(not test.inventory:contains(storageItem) and not crate:getModData().zedcomm,
    "fitting consumes the item and leaves the native crate unconverted")
local crateReading, crateWire = reading(crateTile, crateId)
check(crateReading() == 255, "full crate sends 255")
local replacement = host(crateTile, "carpentry_01_16")
compartment(replacement, "Crate", 60, 60)
test.takeOff(crateTile, crate)
check(crateReading() == nil and not replacement:getModData().zedcommContact,
    "same-tile crate replacement cannot inherit the output")
test.registry:OnChunkLoaded(math.floor(crateTile:getX() / 8), math.floor(crateTile:getY() / 8))
check(not test.registry.network.pieces[crateId] and not test.registry.network.pieces[crateWire].links[crateId],
    "loaded orphan cleanup removes sensor and detaches its wire")

local shelfTile = test.floorTile(412, 415)
local shelf = host(shelfTile, "crafted_05_36")
local top = compartment(shelf, "Top", 20, 20)
local bottom = compartment(shelf, "Bottom", 5, 20)
test.give(Sensors.STORAGE)
fit = queue(shelfTile, "Storage Sensor", "Fit 2. Bottom")
shelf.compartments[2] = top
check(not fit:isValid() and not shelf:getModData().zedcommContact, "queued fitting rejects a stale compartment")
shelf.compartments[2] = bottom
check(fit:isValid() and fit:complete(), "two-compartment shelf fitting accepts the selected compartment")
local shelfId = assert(shelf:getModData().zedcommContact)
local shelfReading, shelfWire = reading(shelfTile, shelfId)
check(shelfReading() == 64, "storage uses selected compartment and defaults to fullness")
local configure = queue(shelfTile, "Storage Sensor", "2. Bottom - Free capacity")
check(configure:isValid() and configure:complete() and shelfReading() == 191, "free capacity persists on the same jack")
test.registry, test.java = test.start(test.save(test.java))
local piece = test.registry.network.pieces[shelfId]
check(piece.state.compartment == 1 and piece.state.mode == "free" and piece.ports.signal == shelfWire
    and shelfReading() == 191, "reload restores selected compartment, mode, and signal wire")
shelf.compartments[2] = nil
check(shelfReading() == nil and test.registry.network.pieces[shelfId] ~= nil,
    "missing compartment suppresses the reading while preserving the installation")
shelf.compartments[2] = bottom
bottom.effective = 0
check(shelfReading() == nil, "zero capacity makes a native compartment unavailable")
bottom.effective, bottom.used = 20, 25
check(shelfReading() == 0, "overfilled storage sends a valid free-capacity zero")

local copiedCrate = host(crateTile, "carpentry_01_19")
local copiedCompartment = compartment(copiedCrate, "Moved crate", 0, 40)
copiedCrate:getModData().zedcommContact = shelfId
fire("OnObjectAboutToBeRemoved", copiedCrate)
check(test.registry.network.pieces[shelfId] ~= nil, "copied moveable marker cannot detach a sensor on another tile")
copiedCrate:getModData().zedcommContact = shelfId
check(Contact.canFit(copiedCrate, Sensors.STORAGE)
    and Sensors.storageState(copiedCrate, { index = 0, container = copiedCompartment }, "fullness"),
    "obsolete moveable marker allows a fresh fitting")

local collectorTile = test.floorTile(412, 417)
local collector = host(collectorTile, "carpentry_02_54")
collector.fluid = { amount = 0, capacity = 400, nativeSetting = "untouched" }
function collector.fluid:getAmount() return self.amount end
function collector.fluid:getCapacity() return self.capacity end
local fluid = collector.fluid
collector:getModData().canBeWaterPiped = true
test.give(Sensors.FLUID)
fit = queue(collectorTile, "Fluid Fill Sensor", "Fit fluid fill sensor")
check(fit:isValid() and fit:complete(), "native collector accepts a timed fluid sensor fitting")
local fluidId = assert(collector:getModData().zedcommContact)
local fluidReading, fluidWire = reading(collectorTile, fluidId)
check(fluidReading() == 0, "empty collector sends valid zero")
fluid.amount = 200
check(fluidReading() == 128, "collector samples native amount and capacity")
test.registry, test.java = test.start(test.save(test.java))
check(fluidReading() == 128, "collector binding survives reload")
collector.fluid = nil
check(fluidReading() == nil, "missing native fluid component produces no signal")
collector.fluid = fluid
local detach = queue(collectorTile, "Fluid Fill Sensor", "Remove sensor")
check(detach:isValid() and detach:complete() and collector.fluid == fluid and fluid.amount == 200
    and fluid.capacity == 400 and fluid.nativeSetting == "untouched" and collector:getModData().canBeWaterPiped
    and not collector:getModData().zedcommContact and not test.registry.network.pieces[fluidWire].links[fluidId]
    and test.inventory:getFirstType(Sensors.FLUID), "detachment returns the sensor, disconnects the wire, and preserves the fluid fixture")
fire("OnObjectAboutToBeRemoved", shelf)
test.takeOff(shelfTile, shelf)
check(not test.registry.network.pieces[shelfId] and not test.registry.network.pieces[shelfWire].links[shelfId],
    "native host removal detaches the sensor and wire")
test.finish()
