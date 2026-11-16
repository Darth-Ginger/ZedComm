-- Shared board geometry, validation and packet evaluation for both hosts.
require "ZedComm/SignalModules"
local Packet = ZedComm.SignalModules.Packet
local Sender = ZedComm.SignalModules.Sender
local Circuit = {
    CABINET_ID = "ZedComm.SmallCabinet",
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
    splitter = { ports = { ["in"] = "in", outA = "out", outB = "out" },
        item = "ZedComm.SplitterModule", label = "Splitter", edgeMount = true },
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
Circuit.moduleOrder = {
    "threshold", "and", "inputExtension", "outputExtension", "adder", "or", "xor", "not",
    "cache", "subtractor", "multiplier",
    "timer", "wait", "mainsSource", "batterySource", "splitter",
}
Circuit.adapterModules = { "threshold", "not", "timer", "wait", "mainsSource", "batterySource" }

function Circuit.size(cabinet) return cabinet and 6 or 3 end

function Circuit.defaultRotation(kind)
    return kind == "outputExtension" and 180 or 0
end

-- Untagged playtest cabinets already supported full packets.
function Circuit.cabinetAdapter(state)
    if state and state.adapter ~= nil then return state.adapter end
    return "advanced"
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

-- Coordinates are relative to the rotated footprint, in cells.
function Circuit.terminalPosition(rotation, terminal, kind)
    if kinds[kind] and kinds[kind].source then
        local points = { [0] = { 1, 0.5 }, [90] = { 0.5, 1 }, [180] = { 0, 0.5 }, [270] = { 0.5, 0 } }
        return points[rotation][1], points[rotation][2]
    end
    local x, y = terminal == "out" and 1 or 0, 1
    if terminal == "a" or terminal == "data" then y = 0.5 end
    if terminal == "b" or terminal == "enable" then y = 1.5 end
    if terminal == "outA" then x, y = 1, 0.5 end
    if terminal == "outB" then x, y = 1, 1.5 end
    if kind == "splitter" and terminal == "in" then x = 0.2 end
    if kind == "outputExtension" then x = 1 end
    return rotatePoint(rotation, x, y)
end

function Circuit.jackAt(part)
    local x, y = rotatePoint(part.rotation, part.kind == "output" and 1 or 0, 1)
    return x, y
end

function Circuit.jackLabel(id, direction, custom)
    local number = id:match("%-(%d+)$")
    local label = (direction == "sink" and "IN" or "OUT") .. (number and (" " .. number) or "")
    return custom and label .. " (" .. custom .. ")" or label
end

function Circuit.fixedParts(cabinet)
    return {
        input = { column = 1, row = 1, rotation = 0, kind = "input" },
        output = { column = Circuit.size(cabinet), row = 1, rotation = 0, kind = "output" },
    }
end

function Circuit.moduleAllowed(kind, cabinet)
    local spec = kinds[kind]
    return spec and spec.item ~= nil and (cabinet or spec.adapter == true)
end

local function integer(value, low, high)
    return type(value) == "number" and value >= low and value <= high and math.floor(value) == value
end

local function occupy(cells, part, size)
    local column, row = part.column, part.row
    local width, height = Circuit.footprint(part.rotation, part.kind)
    if not integer(column, 1, size - width + 1) or not integer(row, 1, size - height + 1) then
        return false, "module outside board"
    end
    for y = row, row + height - 1 do
        for x = column, column + width - 1 do
            local key = (y - 1) * size + x
            if cells[key] then return false, "module overlaps another part" end
            cells[key] = true
        end
    end
    return true
end

local function mountFacesEdge(part, size)
    if part.rotation == 0 then return part.column == 1 end
    if part.rotation == 90 then return part.row == 1 end
    if part.rotation == 180 then return part.column == size end
    return part.row == size
end

local function collectParts(modules, cabinet)
    local parts, cells = Circuit.fixedParts(cabinet), {}
    local size = Circuit.size(cabinet)
    for _, part in pairs(parts) do occupy(cells, part, size) end
    for id, part in pairs(modules) do
        if type(id) ~= "string" or id == "" or id:find("#", 1, true) or parts[id] or type(part) ~= "table"
            or not Circuit.moduleAllowed(part.kind, cabinet) or not rotations[part.rotation]
            or (part.kind == "threshold" and not integer(part.threshold, 0, 255)) then
            return nil, "invalid circuit module"
        end
        local ok, reason = occupy(cells, part, size)
        if not ok then return nil, reason end
        local spec = kinds[part.kind]
        if (spec.jack or spec.edgeMount) and not mountFacesEdge(part, size) then
            return nil, spec.edgeMount and "Splitter must mount on an edge with outputs facing in"
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

local function collectDrivers(parts, links, size)
    local drivers, count, last = {}, 0, 0
    for index, link in pairs(links) do
        if not integer(index, 1, size * size) or type(link) ~= "table" then
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

function Circuit.compilePackets(layout, cabinet, adapter)
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
    local basicCabinet = cabinet and adapter == "basic"
    if basicCabinet then
        for _, part in pairs(parts) do
            if part.fullReading then return nil, "Full Reading requires an Advanced Cabinet" end
        end
    end
    local drivers, linkError = collectDrivers(parts, layout.links, Circuit.size(cabinet))
    if not drivers then return nil, linkError end
    local order = orderParts(parts, drivers)
    if not order then return nil, "internal circuit feedback" end
    local modes = {}
    if layout.outputModes ~= nil then
        if not cabinet or type(layout.outputModes) ~= "table" then return nil, "invalid output modes" end
        for id, mode in pairs(layout.outputModes) do
            if basicCabinet then return nil, "Advanced output requires an Advanced Cabinet" end
            if not parts[id] or kinds[parts[id].kind].jack ~= "source" or mode ~= "advanced" then
                return nil, "invalid output mode"
            end
            modes[id] = mode
        end
    end

    local directions, dependencies, ancestors = {}, {}, {}
    local hasMains
    for _, id in ipairs(order) do
        local kind = parts[id].kind
        if kind == "mainsSource" then hasMains = true end
        local jack = kinds[kind].jack
        directions[id] = jack
        local inputs = {}
        if jack == "sink" then inputs[id] = true end
        for _, driver in pairs(drivers[id] or {}) do
            for input in pairs(ancestors[driver]) do inputs[input] = true end
        end
        ancestors[id] = inputs
        if jack == "source" then dependencies[id] = inputs end
    end

    local function evaluate(inputs, environment)
        local values, outputs = {}, {}
        local deadline
        for _, id in ipairs(order) do
            local part, ports = parts[id], drivers[id] or {}
            local kind = part.kind
            local spec = kinds[kind]
            -- Both Splitter contacts share the value of their sole input.
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
            elseif directions[id] == "source" then
                local byte = Packet.basicValue(value)
                if directions[ports["in"]] == "sink" then
                    value = byte ~= nil and Packet.basic(byte > 0 and 255 or 0) or nil
                elseif modes[id] ~= "advanced" then
                    value = byte ~= nil and Packet.basic(byte) or nil
                end
            end
            values[id] = value
            if directions[id] == "source" then outputs[id] = value end
        end
        return outputs, deadline
    end

    return evaluate, nil, { directions = directions, dependencies = dependencies, hasMains = hasMains }
end

-- Numeric preview and byte-facing fixtures use the same compiled graph.
function Circuit.compile(layout, cabinet, adapter)
    local evaluate, reason, board = Circuit.compilePackets(layout, cabinet, adapter)
    if not evaluate then return nil, reason end
    if not cabinet then
        return function(value, environment)
            local outputs, deadline = evaluate({ input = Packet.basic(value) }, environment)
            return Packet.basicValue(outputs.output), deadline
        end, nil, board
    end
    return function(inputs)
        local packets, outputs = {}, {}
        for id, value in pairs(inputs) do packets[id] = Packet.basic(value) end
        for id, packet in pairs(evaluate(packets)) do outputs[id] = Packet.basicValue(packet) end
        return outputs
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
