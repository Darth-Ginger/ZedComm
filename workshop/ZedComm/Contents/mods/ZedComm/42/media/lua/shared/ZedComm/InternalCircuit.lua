-- Shared board geometry, validation and packet evaluation.
require "ZedComm/SignalModules"
local Packet = ZedComm.SignalModules.Packet
local Sender = ZedComm.SignalModules.Sender
local Circuit = {
    CABINET_ID = "ZedComm.SmallCabinet",
    DOOR_ID = "ZedComm.Door",
    ADVANCED_CABINET_ITEM = "ZedComm.AdvancedSmallCabinet",
    BASIC_ADAPTER_ITEM = "ZedComm.BasicAdapter",
    ADVANCED_ADAPTER_ITEM = "ZedComm.AdvancedAdapter",
}
local rotations = { [0] = true, [90] = true, [180] = true, [270] = true }
local pair = { a = "in", b = "in", out = "out" }

local kinds = {
    input = { ports = { out = "out" }, jack = "sink" },
    output = { ports = { ["in"] = "in" }, jack = "source" },
    threshold = { ports = { ["in"] = "in", out = "out" }, item = "ZedComm.ThresholdModule",
        label = "Threshold", adapter = true },
    ["and"] = { ports = pair, item = "ZedComm.AndModule", label = "AND",
        combine = function(a, b) return a > 0 and b > 0 and 255 or 0 end },
    adder = { ports = pair, item = "ZedComm.AdderModule", label = "Adder",
        combine = function(a, b) return math.min(a + b, 255) end,
        full = function(a, b) return a + b end },
    subtractor = { ports = pair, item = "ZedComm.SubtractorModule", label = "Subtractor",
        combine = function(a, b) return math.max(0, a - b) end,
        full = function(a, b) return math.max(0, a - b) end },
    multiplier = { ports = pair, item = "ZedComm.MultiplierModule", label = "Multiplier", factor = true,
        combine = function(a, b) return math.min(255, a * b) end,
        full = function(a, b) return a * b end },
    ["or"] = { ports = pair, item = "ZedComm.OrModule", label = "OR",
        combine = function(a, b) return (a > 0 or b > 0) and 255 or 0 end },
    xor = { ports = pair, item = "ZedComm.XorModule", label = "XOR",
        combine = function(a, b) return ((a > 0) ~= (b > 0)) and 255 or 0 end },
    ["not"] = { ports = { ["in"] = "in", out = "out" }, item = "ZedComm.NotModule",
        label = "NOT", adapter = true, transform = function(value) return value == 0 and 255 or 0 end },
    cache = { ports = { data = "in", enable = "in", out = "out" },
        item = "ZedComm.CacheModule", label = "Cache" },
    splitter = { ports = { ["in"] = "in" }, externalOutputs = 2,
        item = "ZedComm.SplitterModule", label = "Splitter" },
    timer = { ports = { ["in"] = "in", out = "out" }, item = "ZedComm.TimerModule",
        label = "Timer", adapter = true, timed = true, defaultSeconds = 10 },
    wait = { ports = { ["in"] = "in", out = "out" }, item = "ZedComm.WaitModule",
        label = "Wait", adapter = true, timed = true, defaultSeconds = 2 },
    mainsSource = { ports = { out = "out" }, item = "ZedComm.MainsSourceModule",
        label = "Mains Source", adapter = true, source = true },
    batterySource = { ports = { out = "out" }, item = "ZedComm.BatterySourceModule",
        label = "Battery Source", adapter = true, source = true },
    inputExtension = { ports = { out = "out" }, jack = "sink", item = "ZedComm.InputExtension", label = "Input Extension" },
    outputExtension = { ports = { ["in"] = "in" }, jack = "source", item = "ZedComm.OutputExtension", label = "Output Extension" },
}
Circuit.kinds = kinds

Circuit.cabinets = {
    [Circuit.CABINET_ID] = { name = "Small Cabinet", sprite = "zedcomm_devices_01_466", cells = 6, pairs = 1 },
    ["ZedComm.LargeCabinet"] = { name = "Large Cabinet", sprite = "zedcomm_cabinets_01_0", cells = 8, pairs = 2 },
    ["ZedComm.XLCabinet"] = { name = "XL Cabinet", sprite = "zedcomm_cabinets_01_1", cells = 10, pairs = 3 },
    ["ZedComm.TabletopCabinet"] = { name = "Tabletop Cabinet", sprite = "zedcomm_cabinets_01_2",
        cells = 6, pairs = 1, mount = "surface" },
    ["ZedComm.WallCabinet"] = { name = "Wall Cabinet", sprite = "zedcomm_cabinets_01_3",
        cells = 8, pairs = 2, mount = "wall" },
}

function Circuit.size(profile)
    local cabinet = Circuit.cabinets[profile]
    return cabinet and cabinet.cells or (profile and 6 or 3)
end

function Circuit.dimensions(profile)
    return Circuit.size(profile), profile == "door" and 3 or Circuit.size(profile)
end

function Circuit.profileFor(definitionId)
    if definitionId == Circuit.DOOR_ID then return "door" end
    if Circuit.cabinets[definitionId] then return definitionId end
end

function Circuit.cabinetPadlockId(piece)
    return Circuit.cabinets[piece.definitionId] and piece.state and piece.state.padlockKeyId or nil
end

function Circuit.defaultRotation(kind)
    local spec = kinds[kind]
    if spec and spec.item and (spec.jack == "source" or spec.externalOutputs) then return 180 end
    return 0
end

function Circuit.footprint(rotation, kind)
    if kinds[kind] and kinds[kind].source then return 1, 1 end
    if rotation == 90 or rotation == 270 then return 2, 1 end
    return 1, 2
end

local function rotatePoint(rotation, x, y)
    if rotation == 90 then return 2 - y, x end
    if rotation == 180 then return 1 - x, 2 - y end
    if rotation == 270 then return y, 1 - x end
    return x, y
end

local terminalRows = { a = 0.5, b = 1.5, data = 0.8, enable = 1.65 }
local sourceTerminals = { [0] = { 1, 0.5 }, [90] = { 0.5, 1 }, [180] = { 0, 0.5 }, [270] = { 0.5, 0 } }

-- Coordinates are relative to the rotated footprint, in cells.
function Circuit.terminalPosition(rotation, terminal, kind)
    local spec = kinds[kind]
    if spec and spec.source then
        local point = sourceTerminals[rotation]
        return point[1], point[2]
    end
    local x, y = terminal == "out" and 1 or 0, terminalRows[terminal] or 1
    if kind == "outputExtension" or (spec and spec.externalOutputs) then x = 1 end
    return rotatePoint(rotation, x, y)
end

function Circuit.jackAt(part, branch)
    return rotatePoint(part.rotation, part.kind == "output" and 1 or 0, branch and branch - 0.5 or 1)
end

function Circuit.splitterPort(id, branch)
    return id .. "/spl-" .. branch
end

function Circuit.jackLabel(id, direction, custom)
    local splitter, branch = id:match("^([^/]+)/spl%-(%d+)$")
    local label
    if id == "lock" or id == "open" then
        label = id == "lock" and "Lock IN" or "Open IN"
    elseif splitter then
        local number = tonumber(splitter:match("%-(%d+)$")) or 1
        label = "SPL-" .. ((number - 1) * kinds.splitter.externalOutputs + tonumber(branch))
    else
        local number = id:match("%-(%d+)$")
        label = (direction == "sink" and "IN" or "OUT") .. (number and (" " .. number) or "")
    end
    return custom and label .. " (" .. custom .. ")" or label
end

function Circuit.fixedParts(cabinet)
    if cabinet == "door" then
        return {
            lock = { column = 1, row = 1, rotation = 0, kind = "input", label = "Lock IN", moveable = false },
            open = { column = 2, row = 3, rotation = 270, kind = "input", label = "Open IN", moveable = false },
            lockAction = { column = 6, row = 1, rotation = 0, kind = "output", label = "Lock", action = true, moveable = false },
            openAction = { column = 4, row = 3, rotation = 90, kind = "output", label = "Open", action = true, moveable = false },
        }
    end
    local profile = Circuit.cabinets[cabinet]
    local count, columns = profile and profile.pairs or 1, Circuit.size(cabinet)
    local parts = {}
    for index = 1, count do
        local suffix = index == 1 and "" or "-" .. index
        local row = 1 + (index - 1) * 3
        parts["input" .. suffix] = { column = 1, row = row, rotation = 0, kind = "input", moveable = false }
        parts["output" .. suffix] = { column = columns, row = row, rotation = 0, kind = "output", moveable = false }
    end
    return parts
end

function Circuit.moduleAllowed(kind, cabinet)
    local spec = kinds[kind]
    return spec and spec.item ~= nil and (cabinet or spec.adapter == true)
        and (cabinet ~= "door" or (not spec.jack and not spec.externalOutputs))
end

local function integer(value, low, high)
    return type(value) == "number" and value >= low and value <= high and math.floor(value) == value
end

local function occupy(cells, part, columns, rows)
    local column, row = part.column, part.row
    local width, height = Circuit.footprint(part.rotation, part.kind)
    if not integer(column, 1, columns - width + 1) or not integer(row, 1, rows - height + 1) then
        return false, "module outside board"
    end
    for y = row, row + height - 1 do
        for x = column, column + width - 1 do
            local key = (y - 1) * columns + x
            if cells[key] then return false, "module overlaps another part" end
            cells[key] = true
        end
    end
    return true
end

local function mountFacesEdge(part, columns, rows)
    if part.rotation == 0 then return part.column == 1 end
    if part.rotation == 90 then return part.row == 1 end
    if part.rotation == 180 then return part.column == columns end
    return part.row == rows
end

local function collectParts(modules, cabinet)
    local parts, cells = Circuit.fixedParts(cabinet), {}
    local size, rows = Circuit.dimensions(cabinet)
    for _, part in pairs(parts) do occupy(cells, part, size, rows) end
    for id, part in pairs(modules) do
        if type(id) ~= "string" or id == "" or id:find("[#/]") or parts[id] or type(part) ~= "table"
            or not Circuit.moduleAllowed(part.kind, cabinet) or not rotations[part.rotation]
            or (part.kind == "threshold" and not integer(part.threshold, 0, 255)) then
            return nil, "invalid circuit module"
        end
        local ok, reason = occupy(cells, part, size, rows)
        if not ok then return nil, reason end
        local spec = kinds[part.kind]
        if (spec.jack or spec.externalOutputs) and not mountFacesEdge(part, size, rows) then
            return nil, spec.externalOutputs and "Splitter must mount on an edge with its jacks facing out"
                or "extension jack must face out from an edge"
        end
        if part.always ~= nil and (part.kind ~= "cache" or type(part.always) ~= "boolean") then
            return nil, "invalid Cache mode"
        end
        if part.fullReading ~= nil and (not kinds[part.kind].full or type(part.fullReading) ~= "boolean") then
            return nil, "invalid arithmetic mode"
        end
        local seconds = part.seconds or spec.defaultSeconds
        if spec.timed and (type(seconds) ~= "number" or seconds <= 0 or seconds - seconds ~= 0) then
            return nil, "duration must be a positive number of seconds"
        end
        if spec.source and not integer(part.level or 255, 1, 255) then
            return nil, "source output must be from 1 to 255"
        end
        if part.charge ~= nil and (part.kind ~= "batterySource" or type(part.charge) ~= "number"
            or not (part.charge >= 0 and part.charge <= 1)) then
            return nil, "invalid battery charge"
        end
        parts[id] = { kind = part.kind, threshold = part.threshold, always = part.always, fullReading = part.fullReading,
            seconds = seconds, level = part.level or 255, charge = part.charge }
    end
    return parts
end

local function collectDrivers(parts, links, limit)
    local drivers, count, last = {}, 0, 0
    for index, link in pairs(links) do
        if not integer(index, 1, limit) or type(link) ~= "table" then
            return nil, "invalid internal link"
        end
        count, last = count + 1, math.max(last, index)
        local from, to = parts[link.from], parts[link.to]
        if not from or not to or kinds[from.kind].ports[link.output] ~= "out"
            or kinds[to.kind].ports[link.input] ~= "in" then
            return nil, "invalid terminal direction"
        end
        local inputs = drivers[link.to] or {}
        if inputs[link.input] then return nil, "input already has a driver" end
        inputs[link.input] = link.from
        drivers[link.to] = inputs
    end
    if count ~= last then return nil, "internal links must be a dense list" end
    return drivers
end

local function orderParts(parts, drivers)
    local order, visited = {}, {}
    local function visit(id)
        if visited[id] ~= nil then return visited[id] end
        visited[id] = false
        for _, driver in pairs(drivers[id] or {}) do
            if not visit(driver) then return false end
        end
        visited[id] = true
        order[#order + 1] = id
        return true
    end
    for id in pairs(parts) do
        if not visit(id) then return nil end
    end
    return order
end

local function weightAmount(packet)
    if packet and packet.type == "signal.advanced" then return packet.value.amount end
end

local function operate(part, spec, a, b)
    if part.fullReading then
        local amount = weightAmount(a)
        local operand
        if spec.factor then
            if b and b.type == "signal.basic" then operand = b.value end
        else
            operand = weightAmount(b)
        end
        if amount ~= nil and operand ~= nil then
            return Sender.encode(spec.full(amount, operand), "weight", ZedComm.SignalModules.ADVANCED_SENDER)
        end
    else
        local x, y = Packet.basicValue(a), Packet.basicValue(b)
        if x ~= nil and y ~= nil then return Packet.basic(spec.combine(x, y)) end
    end
end

local function timedValue(part, id, packet, environment)
    local states, now = environment.timers, environment.now
    local input = Packet.basicValue(packet)
    if input == nil then states[id] = nil; return nil end
    local state = states[id] or {}
    states[id] = state
    if part.kind == "timer" then
        if input == 0 then
            state.armed = true
        elseif state.armed then
            state.armed, state.due = false, now + part.seconds
        end
        if state.due and now < state.due then return Packet.basic(255), state.due end
        state.due = nil
        return Packet.basic(0)
    end
    if input == 0 then
        state.input, state.output, state.due = 0, 0, nil
        return Packet.basic(0)
    end
    if input ~= state.input then state.input, state.due = input, now + part.seconds end
    if state.due and now >= state.due then state.output, state.due = input, nil end
    return Packet.basic(state.output or 0), state.due
end

local function validateLayout(layout, cabinet, adapter)
    if type(layout) ~= "table" or type(layout.modules) ~= "table" or type(layout.links) ~= "table" then
        return nil, "invalid internal circuit"
    end
    if layout.nextModule ~= nil and not integer(layout.nextModule, 1, 2147483647) then
        return nil, "invalid next module number"
    end
    local parts, reason = collectParts(layout.modules, cabinet)
    if not parts then return nil, reason end
    if adapter ~= nil and adapter ~= "basic" and adapter ~= "advanced" then
        return nil, "invalid cabinet adapter"
    end
    -- A cabinet is Basic unless it carries an Advanced Adapter.
    local basicCabinet = cabinet and adapter ~= "advanced"
    if basicCabinet then
        for _, part in pairs(parts) do
            if part.fullReading then return nil, "Full Reading requires an Advanced Cabinet" end
        end
    end
    local columns, rows = Circuit.dimensions(cabinet)
    local drivers, linkError = collectDrivers(parts, layout.links, columns * rows)
    if not drivers then return nil, linkError end
    if cabinet == "door" and basicCabinet then
        for _ in pairs(layout.modules) do return nil, "Door logic requires Advanced Adapters" end
        if #layout.links ~= 2 or not drivers.lockAction or drivers.lockAction["in"] ~= "lock"
            or not drivers.openAction or drivers.openAction["in"] ~= "open" then
            return nil, "Basic Door requires direct Lock and Open paths"
        end
    end
    local order = orderParts(parts, drivers)
    if not order then return nil, "internal circuit feedback" end
    local directions, partOutputs, actions = {}, {}, {}
    for _, id in ipairs(order) do
        local spec = kinds[parts[id].kind]
        local jack = spec.jack
        local action = cabinet == "door" and jack == "source"
        if action then actions[id] = true else directions[id] = jack end
        if jack == "source" then
            partOutputs[id] = { id }
        elseif spec.externalOutputs then
            local ports = {}
            for branch = 1, spec.externalOutputs do
                local port = Circuit.splitterPort(id, branch)
                ports[branch] = port
                directions[port] = "source"
            end
            partOutputs[id] = ports
        end
    end

    local modes = {}
    if layout.outputModes ~= nil then
        if not cabinet or type(layout.outputModes) ~= "table" then return nil, "invalid output modes" end
        for id, mode in pairs(layout.outputModes) do
            if basicCabinet then return nil, "Advanced output requires an Advanced Cabinet" end
            if directions[id] ~= "source" or mode ~= "advanced" then return nil, "invalid output mode" end
            modes[id] = mode
        end
    end

    return { parts = parts, drivers = drivers, order = order, directions = directions, partOutputs = partOutputs,
        actions = actions, modes = modes, basicCabinet = basicCabinet }
end

function Circuit.validate(layout, cabinet, adapter)
    local circuit, reason = validateLayout(layout, cabinet, adapter)
    return circuit ~= nil, reason
end

function Circuit.compilePackets(layout, cabinet, adapter)
    local circuit, reason = validateLayout(layout, cabinet, adapter)
    if not circuit then return nil, reason end
    local parts, drivers, order = circuit.parts, circuit.drivers, circuit.order
    local directions, partOutputs, actions = circuit.directions, circuit.partOutputs, circuit.actions
    local modes, basicCabinet = circuit.modes, circuit.basicCabinet
    local dependencies, ancestors = {}, {}
    local hasMains
    for _, id in ipairs(order) do
        local kind = parts[id].kind
        if kind == "mainsSource" then hasMains = true end
        local inputs = {}
        if directions[id] == "sink" or (cabinet == "door" and kinds[kind].source) then inputs[id] = true end
        for _, driver in pairs(drivers[id] or {}) do
            for input in pairs(ancestors[driver]) do inputs[input] = true end
        end
        ancestors[id] = inputs
        for _, port in ipairs(partOutputs[id] or {}) do dependencies[port] = inputs end
    end

    local function evaluate(inputs, environment)
        local values, outputs = {}, {}
        local deadline
        for _, id in ipairs(order) do
            local part, ports = parts[id], drivers[id] or {}
            local kind = part.kind
            local spec = kinds[kind]
            local value = values[ports["in"]]
            if directions[id] == "sink" then
                value = inputs[id]
                if basicCabinet then value = Packet.basic(Packet.basicValue(value)) end
            elseif kind == "cache" then
                local enable = Packet.basicValue(values[ports.enable])
                if part.always or (enable and enable > 0) then value = values[ports.data] end
            elseif spec.source then
                local powered = kind == "mainsSource" and environment and environment.mains
                    or kind == "batterySource" and (part.charge or 0) > 0
                if powered then value = Packet.basic(part.level) end
            elseif spec.timed then
                value = nil
                if environment then
                    local nextCheck
                    value, nextCheck = timedValue(part, id, values[ports["in"]], environment)
                    if nextCheck and (not deadline or nextCheck < deadline) then deadline = nextCheck end
                end
            elseif spec.combine then
                value = operate(part, spec, values[ports.a], values[ports.b])
            elseif spec.transform or kind == "threshold" then
                local byte = Packet.basicValue(value)
                value = nil
                if byte ~= nil then
                    local result = spec.transform and spec.transform(byte) or (byte >= part.threshold and 255 or 0)
                    value = Packet.basic(result)
                end
            elseif (directions[id] == "source" or actions[id]) and directions[ports["in"]] == "sink" then
                local byte = Packet.basicValue(value)
                value = byte ~= nil and Packet.basic(byte > 0 and 255 or 0) or nil
            end
            values[id] = value
            local outgoing = partOutputs[id]
            if outgoing then
                local basic = Packet.basic(Packet.basicValue(value))
                for _, port in ipairs(outgoing) do
                    outputs[port] = modes[port] == "advanced" and value or basic
                end
            end
        end
        return outputs, deadline
    end

    return evaluate, nil, { directions = directions, dependencies = dependencies, hasMains = hasMains,
        profile = cabinet, actions = actions }
end

function Circuit.doorPreset()
    return { modules = {}, links = {
        { from = "lock", output = "out", to = "lockAction", input = "in" },
        { from = "open", output = "out", to = "openAction", input = "in" },
    } }
end

function Circuit.compile(layout)
    local evaluate, reason, board = Circuit.compilePackets(layout)
    if not evaluate then return nil, reason end
    return function(value, environment)
        local outputs, deadline = evaluate({ input = Packet.basic(value) }, environment)
        return Packet.basicValue(outputs.output), deadline
    end, nil, board
end

function Circuit.thresholdPreset()
    return {
        modules = {
            threshold = { kind = "threshold", column = 2, row = 1, rotation = 0, threshold = 50 },
        },
        links = {
            { from = "input", output = "out", to = "threshold", input = "in" },
            { from = "threshold", output = "out", to = "output", input = "in" },
        },
    }
end

ZedComm = ZedComm or {}
ZedComm.InternalCircuit = Circuit
return Circuit
