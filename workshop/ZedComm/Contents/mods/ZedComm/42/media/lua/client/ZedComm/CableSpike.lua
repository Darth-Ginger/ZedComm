-- Singleplayer debug controls for inspecting circuits and testing sender modules.
if isClient() or isServer() then return end

require "ISUI/ISTextBox"

local Debug = {}

local function tagOf(object)
    if not object or not object.hasModData or not object:hasModData() then return nil end
    local data = object:getModData()
    local tag = data and data.zedcomm
    return type(tag) == "table" and type(tag.id) == "string" and tag or nil
end

local function taggedOn(square)
    local out = {}
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if tagOf(object) then out[#out + 1] = object end
    end
    return out
end

local function where(square)
    return square:getX() .. "," .. square:getY() .. "," .. square:getZ()
end

local function say(player, text)
    if player then player:Say(text) end
    print("[ZedComm debug] " .. text)
end

function Debug.placeByteRig(player, square)
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    if not registry then
        say(player, "device test requires the server registry")
        return
    end
    local sprites = { "zedcomm_devices_01_0", "zedcomm_devices_01_1", "zedcomm_devices_01_431" }
    for _, sprite in ipairs(sprites) do
        if not getSprite(sprite) then
            say(player, "device rig missing sprite: " .. sprite)
            return
        end
    end

    local cell = getCell()
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local tiles = { square, cell:getGridSquare(x + 1, y, z), cell:getGridSquare(x + 2, y, z) }
    for i = 1, 3 do
        if not tiles[i] or #taggedOn(tiles[i]) > 0 then
            say(player, "choose three loaded tiles clear of ZedComm pieces along +X")
            return
        end
    end

    local prefix = "device-spike-" .. where(square) .. "-" .. getTimestampMs()
    local wireId = prefix .. "-wire"
    local tags = {
        { id = prefix .. "-sensor", kind = "endpoint", spikeWire = wireId,
            definitionId = "ZedComm.DebugByteSource" },
        { id = wireId, kind = "cable", useRouteSprite = true },
        { id = prefix .. "-display", kind = "endpoint", definitionId = "ZedComm.NumericDisplay", spikeWire = wireId },
    }
    local names = { "ZedCommTestByteSource", "ZedCommTestCable", "ZedCommTestDisplay" }
    local objects = {}
    local ok, err = pcall(function()
        for i = 1, 3 do
            local object = IsoObject.new(tiles[i], sprites[i], names[i])
            object:getModData().zedcomm = tags[i]
            objects[i] = object
            tiles[i]:AddTileObject(object)
            triggerEvent("OnObjectAdded", object)
            if not registry.network.pieces[tags[i].id] then error(names[i] .. " failed to register") end
        end
        for _, i in ipairs({ 1, 3 }) do
            local linked, reason = registry:link(wireId, tags[i].id, "signal")
            if not linked then error(reason) end
        end
    end)
    if not ok then
        for i = #objects, 1, -1 do
            tiles[i]:transmitRemoveItemFromSquare(objects[i])
        end
        say(player, "device rig failed: " .. tostring(err))
        return
    end
    say(player, "byte source at " .. where(tiles[1]) .. ", wire at " .. where(tiles[2])
        .. ", display at " .. where(tiles[3]))
end

function Debug.toggleDeviceLink(player, object)
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    local tag = tagOf(object)
    local piece = registry and tag and registry.network.pieces[tag.id]
    if not piece or not tag.spikeWire then return end
    local linked = piece.ports.signal
    local ok, err
    if linked then
        ok, err = registry:unlink(linked, tag.id)
    else
        ok, err = registry:link(tag.spikeWire, tag.id, "signal")
    end
    say(player, ok and (linked and "test device disconnected" or "test device connected")
        or tostring(err))
end

function Debug.showDeviceDisplay(player, object)
    local runtime = ZedComm.DeviceRuntime
    if not runtime then return end
    local value, _, hasReading = runtime.getDisplay(object)
    local label = "unattached or awaiting update"
    if hasReading then label = value == nil and "no signal" or tostring(value) end
    say(player, "test display: " .. label)
end

function Debug.inspectCircuit(player, object)
    local runtime = ZedComm.DeviceRuntime
    local tag = tagOf(object)
    local report = runtime and tag and runtime.inspect(tag.id)
    if not report then
        say(player, "Circuit is awaiting the simulation.")
        return
    end
    local lines = { report.status }
    local packet = report.sourcePacket
    if not packet then
        lines[#lines + 1] = "source no signal"
    elseif packet.type == "signal.advanced" then
        local weight = packet.value
        lines[#lines + 1] = "source " .. packet.type .. " " .. weight.kind .. " " .. weight.amount .. " " .. weight.unit
        lines[#lines + 1] = "fallback " .. (report.sourceByte == nil and "none" or tostring(report.sourceByte))
    else
        lines[#lines + 1] = "source " .. packet.type .. " " .. packet.value
    end
    for _, receiver in ipairs(report.receivers) do
        local value = "unattached or unavailable"
        if receiver.reading then value = receiver.value == nil and "no signal" or tostring(receiver.value) end
        lines[#lines + 1] = "receiver " .. value
    end
    if #report.receivers == 0 then lines[#lines + 1] = "no receiver" end
    say(player, table.concat(lines, " | "))
end

function Debug.setByte(player, object)
    local tag = tagOf(object)
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    local runtime = ZedComm.DeviceRuntime
    local piece = registry and tag and registry.network.pieces[tag.id]
    if not runtime or not piece then return end
    local box = ISTextBox:new(0, 0, 280, 150, "Test byte (0 to 255):",
        tostring(piece.state and piece.state.byte or 0), nil, function(_, button)
            if button.internal ~= "OK" then return end
            local current = ZedComm.Registry and ZedComm.Registry.instance
            if current ~= registry then return end
            local value = button.parent.entry:getText()
            local ok, reason = runtime.setTestByte(registry, tag.id, value)
            say(player, ok and ("test source set to " .. value) or tostring(reason))
        end, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

local function resolveDebugTarget(object)
    if not getDebug() then return nil end
    local tag = tagOf(object)
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    local placement = ZedComm.PlayerPlacement
    local entry = tag and registry and placement and placement.resolve(registry, tag.id)
    if entry and entry.object == object then return registry, entry end
end

local function selectWeightPlateSender(player, object, moduleId)
    local registry, entry = resolveDebugTarget(object)
    if not entry then return end
    local ok, reason = ZedComm.DeviceRuntime.setWeightPlateSender(registry, entry.id, moduleId)
    local modules = ZedComm.SignalModules
    local name = moduleId == modules.ADVANCED_SENDER and "Advanced Sender" or "Basic Sender"
    say(player, ok and ("Weight plate sender set to " .. name .. ".") or reason)
end

local function thresholdModule(circuit)
    local threshold = type(circuit) == "table" and type(circuit.modules) == "table" and circuit.modules.threshold
    if type(threshold) == "table" and threshold.kind == "threshold" then return threshold end
end

local function installThresholdPreset(player, object)
    local registry, entry = resolveDebugTarget(object)
    if not entry or thresholdModule(entry.piece.state and entry.piece.state.circuit) then return end
    local ok, reason = ZedComm.DeviceRuntime.setLampCircuit(registry, entry.id,
        ZedComm.InternalCircuit.thresholdPreset())
    say(player, ok and "Installed test threshold at 50." or reason)
end

local function editLampThreshold(player, object)
    local registry, entry = resolveDebugTarget(object)
    local circuit = entry and entry.piece.state and entry.piece.state.circuit
    local threshold = thresholdModule(circuit)
    if not threshold then return end
    local box = ISTextBox:new(0, 0, 280, 150, "Lamp threshold (0 to 255):",
        tostring(threshold.threshold), nil, function(_, button)
            if button.internal ~= "OK" then return end
            local current, target = resolveDebugTarget(object)
            if current ~= registry or not target or not target.piece.state or target.piece.state.circuit ~= circuit then return end
            local layout = registry.network:record(entry.id).state.circuit
            layout.modules.threshold.threshold = tonumber(button.parent.entry:getText())
            local ok, reason = ZedComm.DeviceRuntime.setLampCircuit(registry, entry.id, layout)
            say(player, ok and ("Lamp threshold set to " .. layout.modules.threshold.threshold .. ".") or reason)
        end, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

function Debug.optionsAt(registry, square)
    local options = {}
    local function add(label, callback, target)
        options[#options + 1] = { label, callback, target }
    end

    add("Place wired byte test rig", Debug.placeByteRig, square)
    local tagged = taggedOn(square)
    for _, object in ipairs(tagged) do
        local tag = tagOf(object)
        local piece = registry.network.pieces[tag.id]
        if piece then
            local label = #tagged > 1 and ("Inspect circuit (" .. tag.id .. ")") or "Inspect circuit"
            if not piece.board then add(label, Debug.inspectCircuit, object) end
            if piece.definitionId == "ZedComm.DebugByteSource" then
                add("Set test byte", Debug.setByte, object)
            end
            if piece.definitionId == ZedComm.RelayLamp.ID then
                local circuit = piece.state and piece.state.circuit
                if thresholdModule(circuit) then
                    add("Set test lamp threshold", editLampThreshold, object)
                else
                    add("Install test lamp threshold", installThresholdPreset, object)
                end
            end
            if piece.definitionId == "ZedComm.WeightPlate" then
                local modules = ZedComm.SignalModules
                local moduleId = ZedComm.DeviceRuntime.getSenderModule(piece)
                local current = "unavailable"
                if moduleId == modules.BASIC_SENDER then current = "Basic Sender" end
                if moduleId == modules.ADVANCED_SENDER then current = "Advanced Sender" end
                options[#options + 1] = {
                    "Weight plate sender (" .. current .. ")",
                    children = {
                        { "Basic Sender", selectWeightPlateSender, object, modules.BASIC_SENDER },
                        { "Advanced Sender", selectWeightPlateSender, object, modules.ADVANCED_SENDER },
                    },
                }
            end
            if tag.spikeWire then
                if tag.definitionId == "ZedComm.DebugByteSource" then
                    add("Toggle test source link", Debug.toggleDeviceLink, object)
                elseif tag.definitionId == "ZedComm.NumericDisplay" then
                    add("Read test display", Debug.showDeviceDisplay, object)
                    add("Toggle test display link", Debug.toggleDeviceLink, object)
                elseif tag.definitionId == "ZedComm.PressureSensor" then
                    -- Existing pressure rigs retain their link control.
                    add("Toggle test sensor link", Debug.toggleDeviceLink, object)
                end
            end
        end
    end
    return options
end

ZedComm = ZedComm or {}
ZedComm.DebugCircuits = Debug
