-- Bind loaded world objects to their device definitions, sample sources and
-- run lamp and cabinet circuits around each simulation pass.
-- Display readings and availability live in memory and are rebuilt on load.
require "ZedComm/NativeDevices"
require "ZedComm/Simulation"
require "ZedComm/SignalModules"

local Modules = ZedComm.SignalModules
local Definitions = ZedComm.DeviceDefinitions
local Simulation = ZedComm.Simulation
local Runtime = {}
local Relay = ZedComm.RelayLamp
local pressureSensorId = "ZedComm.PressureSensor"
local weightPlateId = "ZedComm.WeightPlate"
local network
local receivers = {}
local byNetwork = {}
local readings = {}
local circuitTime = 0

local function tagOf(object)
    if object:hasModData() then
        local tag = object:getModData().zedcomm
        if type(tag) == "table" then return tag end
    end
end

local function findObject(cell, piece)
    local square = cell and cell:getGridSquare(piece.x, piece.y, piece.z)
    if not square then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local tag = tagOf(object)
        if tag and tag.id == piece.id and tag.kind == "endpoint"
            and tag.definitionId == piece.definitionId then
            return object
        end
    end
end

local function isPressureOutput(value)
    return type(value) == "number" and value >= 1 and value <= 255 and math.floor(value) == value
end

function Runtime.getPressureOutput(piece)
    local value = piece and piece.state and piece.state.occupiedOutput
    return isPressureOutput(value) and value or 1
end

function Runtime.setPressureOutput(registry, id, input)
    local piece = registry and registry.network.pieces[id]
    if not piece or piece.definitionId ~= pressureSensorId then
        return false, "No pressure plate at that position."
    end
    local value = tonumber(input)
    if not isPressureOutput(value) then
        return false, "Enter a whole number from 1 to 255."
    end
    local state = registry.network:record(id).state or {}
    state.occupiedOutput = value
    return registry:setDeviceState(id, state)
end

local function occupantKind(actor)
    if instanceof(actor, "IsoPlayer") then
        -- Build 42 animals are IsoPlayer subclasses.
        return instanceof(actor, "IsoAnimal") and "animal" or "player"
    end
    if instanceof(actor, "IsoZombie") then return "zombie" end
end

local function floorFurnitureProperties(object)
    if tagOf(object) or instanceof(object, "IsoWorldInventoryObject") then return nil end
    local props = object:getProperties()
    if not props or props:has(IsoFlagType.solidfloor) or props:has(IsoFlagType.WallOverlay)
        or props:has("IsTableTop") or (props:has("MoveType") and props:get("MoveType") ~= "Object") then
        return nil
    end

    -- A floor prop can rest on the plate without blocking movement.
    if object:getRenderYOffset() <= 0
        and (object:getContainerCount() > 0 or props:has("IsMoveAble") or props:has("PickUpWeight")) then
        return props
    end
end

local function isPressurePlateOccupied(object)
    local square = object:getSquare()
    if square:getVehicleContainer() then return true end
    local actors = square:getMovingObjects()
    for i = 0, actors:size() - 1 do
        if occupantKind(actors:get(i)) then return true end
    end
    local loose = square:getWorldObjects()
    for i = 0, loose:size() - 1 do
        if loose:get(i):getItem() then return true end
    end
    local bodies = square:getStaticMovingObjects()
    for i = 0, bodies:size() - 1 do
        if instanceof(bodies:get(i), "IsoDeadBody") then return true end
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if floorFurnitureProperties(objects:get(i)) then return true end
    end
    return false
end

local function getWeightPlateLoad(object)
    local estimatedActorMass = 75
    local square = object:getSquare()
    -- The engine finds a vehicle intersecting this tile, including one whose
    -- center is on another tile. Use its reported mass for the whole footprint.
    local vehicle = square:getVehicleContainer()
    local load = vehicle and vehicle:getMass() or 0
    local occupants = square:getMovingObjects()
    for i = 0, occupants:size() - 1 do
        local actor = occupants:get(i)
        local kind = occupantKind(actor)
        if kind == "zombie" then
            load = load + estimatedActorMass
        elseif kind == "player" and not actor:getVehicle() then
            local nutrition = actor:getNutrition()
            load = load + (nutrition and nutrition:getWeight() or estimatedActorMass)
        elseif kind == "animal" and not actor:getVehicle() then
            local data = actor:getData()
            load = load + (data and data:getWeight() or 0)
        end
    end
    local loose = square:getWorldObjects()
    for i = 0, loose:size() - 1 do
        local item = loose:get(i):getItem()
        if item then load = load + item:getUnequippedWeight() end
    end
    local bodies = square:getStaticMovingObjects()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if instanceof(body, "IsoDeadBody") then
            local mass = body:getWeight()
            if mass <= 0 and not body:isAnimal() then mass = estimatedActorMass end
            load = load + math.max(0, mass) + body:getInventoryWeight()
        end
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local furniture = objects:get(i)
        local props = floorFurnitureProperties(furniture)
        if props then
            if props:has("PickUpWeight") then
                -- Vanilla moveables convert PickUpWeight in tenths to item weight.
                local rawWeight = tonumber(props:get("PickUpWeight"))
                if rawWeight and rawWeight > 0 then load = load + rawWeight / 10 end
            end
            for index = 0, furniture:getContainerCount() - 1 do
                load = load + furniture:getContainerByIndex(index):getContentsWeight()
            end
        end
    end
    return load
end

local context = {
    getDefinitionId = function(object)
        local tag = tagOf(object)
        return tag and tag.definitionId
    end,
    getDebugByte = function(object)
        local tag = tagOf(object)
        local piece = tag and network and network.pieces[tag.id]
        return piece and piece.state and piece.state.byte or 0
    end,
    isNetworkSwitchOn = function(object)
        local tag = tagOf(object)
        local piece = tag and network and network.pieces[tag.id]
        return piece and piece.state and piece.state.on == true
    end,
    getPressureOutput = function(object)
        local tag = tagOf(object)
        return Runtime.getPressureOutput(tag and network and network.pieces[tag.id])
    end,
    isPressurePlateOccupied = isPressurePlateOccupied,
    getWeightPlateLoad = getWeightPlateLoad,
    getOccupantKinds = function(object)
        local kinds = {}
        local occupants = object:getSquare():getMovingObjects()
        for i = 0, occupants:size() - 1 do
            local kind = occupantKind(occupants:get(i))
            if kind then kinds[#kinds + 1] = kind end
        end
        return kinds
    end,
    clearDisplay = function(object) readings[object] = nil end,
    setDisplay = function(object, value, lit)
        local previous = readings[object]
        if previous and previous.value == value and previous.lit == lit then return end
        readings[object] = { value = value, lit = lit }
        local label = value == nil and "no signal" or tostring(value)
        print("[ZedComm] display " .. tagOf(object).id .. ": " .. label)
    end,
    setDisplayPacket = function(object, packet)
        local value = Modules.Packet.basicValue(packet)
        readings[object] = { value = value, lit = value ~= nil and value ~= 0, packet = Modules.Packet.copy(packet) }
    end,
}

function Runtime.getDisplay(object)
    local reading = readings[object]
    if reading then return reading.value, reading.lit, true, Modules.Packet.copy(reading.packet) end
    return nil, false, false
end

function Runtime.getCircuitOutput(id)
    local receiver = receivers[id]
    return receiver and receiver.output
end

-- Expose current readings without handing rendering code the mutable cache.
function Runtime.forEachDisplay(visit)
    for object, reading in pairs(readings) do
        local packet = reading.packet
        local weight = packet and packet.type == "signal.advanced" and packet.value.amount or nil
        visit(object, reading.value, reading.lit, weight)
    end
end

function Runtime.setTestByte(registry, id, input)
    local piece = registry and registry.network.pieces[id]
    if not piece or piece.definitionId ~= "ZedComm.DebugByteSource" then
        return false, "No byte test source at that position."
    end
    local value = tonumber(input)
    if not value or value < 0 or value > 255 or math.floor(value) ~= value then
        return false, "Enter a whole decimal value from 0 to 255."
    end
    return registry:setDeviceState(id, { byte = value })
end

function Runtime.getSenderModule(piece, definition)
    local installation = piece.state and piece.state.senderModule
    if installation == nil then return Modules.BASIC_SENDER end

    definition = definition or Definitions.get(piece.definitionId)
    if type(installation) ~= "table" or not definition
        or not Modules.Sender.supports(installation.id, definition.readingKind) then
        return nil, "incompatible saved sender module"
    end
    return installation.id
end

function Runtime.setWeightPlateSender(registry, id, moduleId)
    local piece = registry and registry.network.pieces[id]
    if not piece or piece.definitionId ~= weightPlateId or piece.definitionUnavailable then
        return false, "No weight plate at that position."
    end
    if not Modules.Sender.supports(moduleId, "weight") then return false, "Incompatible sender module." end

    local state = registry.network:record(id).state or {}
    state.senderModule = moduleId == Modules.ADVANCED_SENDER and { id = moduleId } or nil
    return registry:setDeviceState(id, state)
end

function Runtime.setLampCircuit(registry, id, layout)
    local piece = registry and registry.network.pieces[id]
    if not piece or piece.definitionId ~= Relay.ID or piece.definitionUnavailable then
        return false, "No ZedComm lamp at that position."
    end
    if layout ~= nil then
        local valid, reason = ZedComm.InternalCircuit.compile(layout)
        if not valid then return false, reason end
    end
    local state = registry.network:record(id).state
    if not state or type(state.module) ~= "table" or state.module.id ~= Relay.MODULE then
        return false, "The lamp needs an installed ZedComm adapter."
    end
    state.circuit = layout
    return registry:setDeviceState(id, state)
end

-- One view of topology and actual readings from the last simulation tick.
function Runtime.inspect(id, port)
    local networkId = network and network:networkOf(id, port)
    if not networkId then return nil end
    local net = network.nets[networkId]
    local source = #net.sources == 1 and net.sources[1] or nil
    local packet = network:recompute(networkId)
    local report = {
        status = network:status(networkId),
        sourceId = source,
        sourcePort = source and net.sourcePort or nil,
        sourcePacket = packet,
        sourceByte = Modules.Packet.basicValue(packet),
        receivers = {},
    }
    for _, sinkId in ipairs(net.sinks) do
        local receiver = receivers[sinkId]
        local value, _, reading
        if receiver then value, _, reading = Runtime.getDisplay(receiver.object) end
        report.receivers[#report.receivers + 1] = { id = sinkId, value = value, reading = reading == true }
    end
    table.sort(report.receivers, function(a, b) return a.id < b.id end)
    return report
end

local function reportError(piece, message)
    if message and message ~= piece.runtimeError then
        print("[ZedComm] device " .. piece.id .. ": " .. message)
    end
    piece.runtimeError = message
end

local function sampleSource(piece, definition, object)
    local packet, reason
    if object and definition then
        local moduleId
        moduleId, reason = Runtime.getSenderModule(piece, definition)
        if moduleId then
            local ok, result = pcall(definition.sample, object, context)
            if ok then
                packet, reason = Modules.Sender.encode(result, definition.readingKind, moduleId)
            else
                reason = tostring(result)
            end
        end
    end
    local published, publishError = network:setPacket(piece.id, packet)
    if not published then network:setPacket(piece.id, nil) end
    local failure = reason or publishError
    reportError(piece, failure and ("sample failed: " .. tostring(failure)) or nil)
end

local function bindReceiver(definition, object, piece, installation)
    local moduleId = definition.receiverModule
    if not moduleId then return nil end
    local config
    if installation ~= nil then
        if type(installation) ~= "table" or installation.id ~= moduleId
            or (installation.config ~= nil and type(installation.config) ~= "table") then
            return nil, "incompatible saved receiver module"
        end
        -- The fixture gets a copy of the saved configuration, never the
        -- registry's live table or transient state from a prior attachment.
        config = network:record(piece.id).state.module.config
    end
    local ok, adapter = pcall(definition.bindFixture, object, context, config)
    if not ok then return nil, tostring(adapter) end
    return Modules.newReceiver(moduleId, adapter)
end

local function powerRecovered(receiver)
    local adapter = receiver.module and receiver.module.adapter
    if not adapter or not adapter.isAvailable then return false end
    local ok, available = pcall(adapter.isAvailable, adapter)
    available = ok and available == true
    local recovered = receiver.available == false and available
    receiver.available = available
    return recovered
end

local function releaseReceiver(receiver)
    if receiver.module then
        local _, reason = receiver.module:detach()
        if reason then reportError(receiver.piece, reason) end
    end
    readings[receiver.object] = nil
end

local cabinets, cabinetInputs, pendingCabinets = {}, {}, {}

local function updateCircuitClock(logic, board, object)
    local mains = board.hasMains and ItemContainer.isObjectPowered(object, true) or false
    local changed = logic.mains ~= mains
    logic.mains, logic.now = mains, circuitTime
    return changed or (logic.deadline ~= nil and logic.deadline <= circuitTime)
end

local function prepareCabinet(cell, piece, previous)
    local object = findObject(cell, piece)
    if not object then
        for port, role in pairs(piece.board.directions) do
            if role == "source" then network:setPacket(piece.id, nil, port) end
        end
        return nil
    end
    local cabinet = previous and previous.piece == piece and previous or { piece = piece, inputs = {}, runs = {} }
    if cabinet.board ~= piece.board then
        cabinet.board = piece.board
        cabinet.inputs, cabinet.runs = {}, {}
        cabinet.logic = { timers = {} }
        pendingCabinets[piece.id] = cabinet
    end
    if updateCircuitClock(cabinet.logic, piece.board, object) then pendingCabinets[piece.id] = cabinet end
    for port, role in pairs(piece.board.directions) do
        if role == "sink" then
            local run = piece.ports[port] and network:networkOf(piece.id, port) or nil
            if cabinet.runs[port] ~= run then
                cabinet.runs[port], cabinet.inputs[port] = run, nil
                pendingCabinets[piece.id] = cabinet
                Simulation.markDirty(run)
            end
            if run then
                local group = cabinetInputs[run] or {}
                group[#group + 1] = { cabinet = cabinet, port = port }
                cabinetInputs[run] = group
            end
        end
    end
    return cabinet
end

function Runtime.prepare(registry)
    local time = getGameTime and getGameTime()
    if time and time.getRealworldSecondsSinceLastUpdate then
        circuitTime = circuitTime + math.max(0, time:getRealworldSecondsSinceLastUpdate())
    end
    local current = registry and registry.network
    if current ~= network then
        for _, previous in pairs(receivers) do releaseReceiver(previous) end
        network = current
        receivers, readings, cabinets = {}, {}, {}
    end
    byNetwork, cabinetInputs, pendingCabinets = {}, {}, {}
    if not network then return end

    local cell = getCell()
    local attached, loadedCabinets = {}, {}
    for id, piece in pairs(network.pieces) do
        if piece.board then
            loadedCabinets[id] = prepareCabinet(cell, piece, cabinets[id])
        elseif piece.definitionId and not piece.definitionUnavailable then
            local definition = Definitions.get(piece.definitionId)
            -- A definition callback takes or returns one value, so only
            -- single-port definitions are bound. Cabinets are handled above.
            local port = definition and #definition.ports == 1 and definition.ports[1]
            local object = port and piece.ports[port] ~= nil and findObject(cell, piece)
            local expectedRole = piece.role == "source" and "source" or "receiver"
            if definition and definition.role ~= expectedRole then object = nil end
            if piece.role == "source" then
                sampleSource(piece, definition, object)
            elseif object and piece.ports[port] then
                local networkId = network:networkOf(id, port)
                if networkId then
                    local cableId = piece.ports[port]
                    local installation
                    if definition.receiverModule and piece.state then installation = piece.state.module end
                    local circuit
                    if piece.definitionId == Relay.ID and piece.state then circuit = piece.state.circuit end
                    local previous = receivers[id]
                    local receiver = previous
                    if not previous or previous.piece ~= piece or previous.object ~= object
                        or previous.cableId ~= cableId or previous.installation ~= installation
                        or previous.circuit ~= circuit then
                        local module, reason = bindReceiver(definition, object, piece, installation)
                        local evaluate, circuitError, board
                        if circuit ~= nil then
                            evaluate, circuitError, board = Relay.compileCircuit(piece.state)
                        end
                        receiver = {
                            object = object, definition = definition, piece = piece, cableId = cableId,
                            installation = installation, module = module,
                            circuit = circuit, evaluate = evaluate, circuitError = circuitError,
                            board = board, logic = board and { timers = {} },
                        }
                        if reason then reportError(piece, "receiver bind failed: " .. reason) end
                    end
                    -- Retry after the simulation samples the latest input.
                    -- This avoids applying a stale ON when power and input
                    -- both change in the same tick.
                    if powerRecovered(receiver) then receiver.reconcile = true end
                    local clockChanged = receiver.board and updateCircuitClock(receiver.logic, receiver.board, object)
                    if receiver ~= previous or receiver.networkId ~= networkId or receiver.reconcile or clockChanged then
                        Simulation.markDirty(networkId)
                    end
                    receiver.networkId = networkId
                    attached[id] = receiver
                    local group = byNetwork[networkId]
                    if not group then
                        group = {}
                        byNetwork[networkId] = group
                    end
                    group[#group + 1] = receiver
                end
            end
        end
    end
    for id, previous in pairs(receivers) do
        if attached[id] ~= previous then releaseReceiver(previous) end
    end
    receivers, cabinets = attached, loadedCabinets
end

function Runtime.deliver(networkId, packet)
    local group = byNetwork[networkId]
    local inputs = cabinetInputs[networkId]
    if not group and not inputs then return end
    local value = Modules.Packet.basicValue(packet)
    if inputs then
        for _, input in ipairs(inputs) do
            local cabinet, port = input.cabinet, input.port
            if not Modules.Packet.equal(cabinet.inputs[port], packet) then
                cabinet.inputs[port] = Modules.Packet.copy(packet)
                pendingCabinets[cabinet.piece.id] = cabinet
            end
        end
    end
    if not group then return end
    for i = 1, #group do
        local receiver = group[i]
        if receiver.module then
            local input = value
            if receiver.module.moduleId == Modules.ADVANCED_READOUT then input = packet end
            if receiver.logic then
                input, receiver.logic.deadline = receiver.evaluate(value, receiver.logic)
                receiver.output = input
            elseif receiver.evaluate then
                input = receiver.evaluate(value)
            end
            local status, reason = receiver.module:receive(input, receiver.reconcile)
            receiver.reconcile = nil
            local failed = status ~= "applied" and reason
            local message = failed and ("receive failed: " .. tostring(failed))
            if receiver.circuitError then message = "invalid internal circuit: " .. receiver.circuitError end
            reportError(receiver.piece, message or nil)
        end
    end
end

-- Publish only after all input runs for this pass have delivered. The
-- simulation queues changed output runs for its next pass.
function Runtime.finish()
    for id, cabinet in pairs(pendingCabinets) do
        local piece = cabinet.piece
        local outputs, deadline = piece.evaluate(cabinet.inputs, cabinet.logic)
        cabinet.logic.deadline = deadline
        for port, role in pairs(piece.board.directions) do
            if role == "source" then
                network:setPacket(id, outputs[port], port)
            end
        end
    end
end

ZedComm.DeviceRuntime = Runtime
return Runtime
