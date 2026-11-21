-- Bind loaded fixtures and update their signals around each simulation pass.
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
local network, topologyVersion
local entries, sources, sinks, boardEntries = {}, {}, {}, {}
local routesDirty = false
local receivers = {}
local byNetwork = {}
local readings = {}
local testSources = {}
local circuitTime = 0

require "ZedComm/DeviceDefinitions"
local tagOf = ZedComm.DeviceDefinitions.readObjectTag

local function findObject(square, piece)
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

local function boundObject(cell, entry)
    local piece = entry.piece
    local square = cell and cell:getGridSquare(piece.x, piece.y, piece.z)
    local object = entry.object
    if square ~= entry.square or (object and object:getSquare() ~= square) then
        entry.square, entry.object = square, findObject(square, piece)
    end
    return entry.object
end

-- Registry load callbacks also cover objects replaced on a reused square.
function Runtime.invalidateBinding(current, id)
    local entry = current == network and entries[id]
    if entry then entry.square = nil end
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
    getOccupantCount = function(object)
        local count = 0
        local occupants = object:getSquare():getMovingObjects()
        for i = 0, occupants:size() - 1 do
            local kind = occupantKind(occupants:get(i))
            if kind == "player" or kind == "zombie" then
                count = count + 1
                if count == 255 then return count end
            end
        end
        return count
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
    local state = registry.network:record(id).state or {}
    state.byte = value
    return registry:setDeviceState(id, state)
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
        local valid, reason = ZedComm.InternalCircuit.validate(layout)
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

function Runtime.getTestSourceValue(object)
    return testSources[object]
end

function Runtime.forEachTestSource(visit)
    for object, value in pairs(testSources) do visit(object, value) end
end

local function sampleSource(cell, entry)
    local piece, definition = entry.piece, entry.definition
    local object = entry.port and boundObject(cell, entry)
    if piece.definitionId == "ZedComm.DebugByteSource" then
        if entry.readout and object ~= entry.readout then testSources[entry.readout] = nil end
        if object then testSources[object] = piece.state and piece.state.byte or 0 end
        entry.readout = object
    end
    local packet, reason
    if object then
        local moduleId
        moduleId, reason = Runtime.getSenderModule(piece, definition)
        if moduleId then
            local ok, reading = pcall(definition.sample, object, context)
            if ok then
                if entry.moduleId == moduleId and entry.reading == reading and entry.packet == piece.packet then return end
                packet, reason = Modules.Sender.encode(reading, definition.readingKind, moduleId)
                if not reason then entry.moduleId, entry.reading = moduleId, reading end
            else
                reason = tostring(reading)
            end
        end
    end
    if not object or reason then entry.moduleId, entry.reading = nil, nil end
    if packet or piece.packet then
        local published, publishError = network:setPacket(piece.id, packet)
        if not published then
            network:setPacket(piece.id, nil)
            entry.moduleId = nil
            reason = reason or publishError
        end
    end
    entry.packet = piece.packet
    reportError(piece, reason and ("sample failed: " .. tostring(reason)) or nil)
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

function Runtime.releaseLamp(id)
    if not receivers[id] then return end
    releaseReceiver(receivers[id])
    receivers[id] = nil
    routesDirty = true
end

local boards, boardInputs, pendingBoards = {}, {}, {}

local function releaseBoard(host)
    if not host or not host.controller then return end
    for _, module in pairs(host.actions) do module:detach() end
    host.controller:release()
end

function Runtime.releaseBoard(id)
    if not boards[id] then return end
    releaseBoard(boards[id])
    boards[id], pendingBoards[id] = nil, nil
    routesDirty = true
end

function Runtime.blocksManualDoorOpening(object)
    local tag = object and tagOf(object)
    local host = tag and boards[tag.id]
    if not host or host.object ~= object or not host.controller
        or not ZedComm.Door.isEligible(object) or object:isOpen() then return false end
    local requests = host.controller.requests
    return requests.lockAction == true or requests.openAction == false
end

function Runtime.getDoorState(id)
    local host = boards[id]
    if not host or not host.controller then return nil end
    local object, results = host.object, {}
    for action, result in pairs(host.controller.results) do
        results[action] = { status = result.status, reason = result.reason }
    end
    return { open = object:isOpen(), locked = object:isLocked(), actions = results }
end

function Runtime.getTimingRemaining(id, moduleId)
    local host = boards[id] or receivers[id]
    if not host or not host.logic then return nil end
    local piece = network and network.pieces[id]
    if not piece or host.piece ~= piece then return nil end
    if piece.board then
        if host.board ~= piece.board then return nil end
    elseif host.circuit ~= (piece.state and piece.state.circuit) then
        return nil
    end
    local timer = host.logic.timers[moduleId]
    if timer and timer.due and timer.due > circuitTime then return timer.due - circuitTime end
end

local function updateCircuitClock(logic, board, object)
    local mains = board.hasMains and ItemContainer.isObjectPowered(object, true) or false
    local changed = logic.mains ~= mains
    logic.mains, logic.now = mains, circuitTime
    return changed or (logic.deadline ~= nil and logic.deadline <= circuitTime)
end

local function prepareBoard(cell, entry)
    local piece = entry.piece
    local id, object = piece.id, boundObject(cell, entry)
    local host = boards[id]
    if not host or host.object ~= object then
        Runtime.releaseBoard(id)
        if not object then
            for port, role in pairs(piece.board.directions) do
                if role == "source" and piece.packets[port] then network:setPacket(id, nil, port) end
            end
            return
        end
        host = { piece = piece, object = object }
        if piece.board.profile == "door" then
            local definition = entry.definition
            host.controller = definition.bindFixture(object, context, piece.state.nativeLock)
            host.actions = {}
            for action in pairs(piece.board.actions) do
                host.actions[action] = assert(Modules.newReceiver(definition.receiverModule, host.controller:adapter(action)))
            end
        end
        boards[id] = host
    end
    if host.board ~= piece.board then
        host.board = piece.board
        host.inputs, host.runs = {}, {}
        host.logic = { timers = {} }
        pendingBoards[id] = host
        routesDirty = true
    end
    if updateCircuitClock(host.logic, piece.board, object) then pendingBoards[id] = host end
end

local function prepareReceiver(cell, entry)
    local piece, definition = entry.piece, entry.definition
    local id, cableId = piece.id, entry.cableId
    local object = entry.networkId and boundObject(cell, entry)
    if not object then
        Runtime.releaseLamp(id)
        return
    end
    local installation = definition.receiverModule and piece.state and piece.state.module
    local circuit
    if piece.definitionId == Relay.ID and piece.state then circuit = piece.state.circuit end
    local receiver = receivers[id]
    if not receiver or receiver.object ~= object or receiver.cableId ~= cableId
        or receiver.installation ~= installation or receiver.circuit ~= circuit then
        Runtime.releaseLamp(id)
        local module, reason = bindReceiver(definition, object, piece, installation)
        local evaluate, circuitError, board
        if circuit ~= nil then evaluate, circuitError, board = Relay.compileCircuit(piece.state) end
        receiver = {
            object = object, piece = piece, cableId = cableId,
            installation = installation, module = module,
            circuit = circuit, evaluate = evaluate, circuitError = circuitError,
            board = board, logic = board and { timers = {} },
        }
        receivers[id] = receiver
        routesDirty = true
        if reason then reportError(piece, "receiver bind failed: " .. reason) end
    end
    -- Deliver the latest input before retrying an installation that regained power.
    if powerRecovered(receiver) then receiver.reconcile = true end
    local clockChanged = receiver.board and updateCircuitClock(receiver.logic, receiver.board, object)
    if receiver.networkId ~= entry.networkId or receiver.reconcile or clockChanged then
        Simulation.markDirty(entry.networkId)
    end
    receiver.networkId = entry.networkId
end

local function rebuildEntries()
    local previous = entries
    entries, sources, sinks, boardEntries = {}, {}, {}, {}
    for id, piece in pairs(network.pieces) do
        if piece.definitionId and not piece.definitionUnavailable then
            local entry = previous[id]
            if not entry or entry.piece ~= piece then
                entry = { piece = piece, definition = Definitions.get(piece.definitionId) }
            end
            local definition = entry.definition
            if piece.board then
                boardEntries[#boardEntries + 1] = entry
            elseif definition then
                local port = #definition.ports == 1 and definition.ports[1]
                local expectedRole = piece.role == "source" and "source" or "receiver"
                if definition.role ~= expectedRole or not port or piece.ports[port] == nil then port = nil end
                entry.port = port
                if piece.role == "source" then
                    sources[#sources + 1] = entry
                else
                    entry.cableId = port and piece.ports[port] or nil
                    entry.networkId = entry.cableId and network:networkOf(id, port) or nil
                    sinks[#sinks + 1] = entry
                end
                if not port or (piece.role ~= "source" and not entry.networkId) then
                    entry.object, entry.square = nil, nil
                end
            end
            entries[id] = entry
        end
    end
    for id, entry in pairs(previous) do
        if entries[id] ~= entry then
            Runtime.releaseLamp(id)
            Runtime.releaseBoard(id)
            if entry.readout then testSources[entry.readout] = nil end
        end
    end
    topologyVersion, routesDirty = network.version, true
end

local function rebuildRoutes()
    byNetwork, boardInputs = {}, {}
    for _, receiver in pairs(receivers) do
        local run = receiver.networkId
        local group = byNetwork[run] or {}
        group[#group + 1] = receiver
        byNetwork[run] = group
    end
    for id, host in pairs(boards) do
        local piece = host.piece
        if host.controller then
            host.controlled = {}
            for action, dependencies in pairs(piece.board.dependencies) do
                for input in pairs(dependencies) do
                    if piece.ports[input] or not piece.board.directions[input] then
                        host.controlled[action] = true
                        break
                    end
                end
            end
        end
        for port, role in pairs(piece.board.directions) do
            if role == "sink" then
                local run = piece.ports[port] and network:networkOf(id, port) or nil
                if host.runs[port] ~= run then
                    host.runs[port], host.inputs[port] = run, nil
                    pendingBoards[id] = host
                    Simulation.markDirty(run)
                end
                if run then
                    local group = boardInputs[run] or {}
                    group[#group + 1] = { host = host, port = port }
                    boardInputs[run] = group
                end
            end
        end
    end
    routesDirty = false
end

function Runtime.prepare(registry)
    local time = getGameTime and getGameTime()
    if time and time.getRealworldSecondsSinceLastUpdate then
        circuitTime = circuitTime + math.max(0, time:getRealworldSecondsSinceLastUpdate())
    end
    local current = registry and registry.network
    if current ~= network then
        for _, previous in pairs(receivers) do releaseReceiver(previous) end
        for _, previous in pairs(boards) do releaseBoard(previous) end
        network, topologyVersion = current, nil
        entries, sources, sinks, boardEntries = {}, {}, {}, {}
        receivers, readings, boards, testSources = {}, {}, {}, {}
        byNetwork, boardInputs, pendingBoards = {}, {}, {}
    end
    if not network then return end
    if topologyVersion ~= network.version then rebuildEntries() end

    local cell = getCell()
    for i = 1, #sources do sampleSource(cell, sources[i]) end
    for i = 1, #sinks do prepareReceiver(cell, sinks[i]) end
    for i = 1, #boardEntries do prepareBoard(cell, boardEntries[i]) end
    if routesDirty then rebuildRoutes() end
end

function Runtime.deliver(networkId, packet)
    local group = byNetwork[networkId]
    local inputs = boardInputs[networkId]
    if not group and not inputs then return end
    local value = Modules.Packet.basicValue(packet)
    if inputs then
        for _, input in ipairs(inputs) do
            local host, port = input.host, input.port
            if not Modules.Packet.equal(host.inputs[port], packet) then
                host.inputs[port] = Modules.Packet.copy(packet)
                pendingBoards[host.piece.id] = host
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
    local batch = pendingBoards
    for id, host in pairs(batch) do
        if pendingBoards == batch then pendingBoards = {} end
        local piece = host.piece
        local outputs, deadline = piece.evaluate(host.inputs, host.logic)
        host.outputs = outputs
        host.logic.deadline = deadline
        for port, role in pairs(piece.board.directions) do
            if role == "source" then
                network:setPacket(id, outputs[port], port)
            end
        end
    end
    for _, host in pairs(boards) do
        if host.controller then
            for action, module in pairs(host.actions) do
                local byte = Modules.Packet.basicValue(host.outputs and host.outputs[action])
                if host.controlled[action] and (action ~= "openAction" or byte ~= nil) then
                    module:receive(byte)
                else
                    module:detach()
                end
            end
            host.controller:flush()
            for _, module in pairs(host.actions) do module:reconcile() end
        end
    end
end

-- Vanilla reports door toggles through this event after changing the door state.
Events.OnContainerUpdate.Add(function()
    for _, host in pairs(boards) do
        if host.controller then host.controller:flush() end
    end
end)

ZedComm.DeviceRuntime = Runtime
return Runtime
