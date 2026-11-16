-- The first internal host is the lamp's 3x3 Advanced Adapter.
local Circuit = {}
local size = 3
local fixed = {
    input = { column = 1, row = 1, output = "out" },
    output = { column = 3, row = 1, input = "in" },
}
local rotations = { [0] = true, [90] = true, [180] = true, [270] = true }

function Circuit.footprint(rotation)
    if rotation == 90 or rotation == 270 then return 2, 1 end
    return 1, 2
end

-- Coordinates are relative to the rotated footprint, in cells.
function Circuit.terminalPosition(rotation, terminal)
    local x = terminal == "in" and 0 or 1
    if rotation == 90 then return 1, x end
    if rotation == 180 then return 1 - x, 1 end
    if rotation == 270 then return 1, 1 - x end
    return x, 1
end

function Circuit.fixedParts()
    return {
        input = { column = fixed.input.column, row = fixed.input.row, rotation = 0, kind = "input" },
        output = { column = fixed.output.column, row = fixed.output.row, rotation = 0, kind = "output" },
    }
end

local function integer(value, low, high)
    return type(value) == "number" and value >= low and value <= high and math.floor(value) == value
end

local function occupy(cells, part, width, height)
    local column, row = part.column, part.row
    if not integer(column, 1, size - width + 1) or not integer(row, 1, size - height + 1) then
        return false, "module outside adapter"
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

local function collectParts(modules)
    local parts, cells = {}, {}
    for id, part in pairs(fixed) do
        parts[id] = part
        occupy(cells, part, 1, 2)
    end
    for id, part in pairs(modules) do
        if type(id) ~= "string" or id == "" or parts[id] or type(part) ~= "table"
            or part.kind ~= "threshold" or not rotations[part.rotation]
            or not integer(part.threshold, 0, 255) then
            return nil, "invalid threshold module"
        end
        local ok, reason = occupy(cells, part, Circuit.footprint(part.rotation))
        if not ok then return nil, reason end
        parts[id] = { input = "in", output = "out", threshold = part.threshold }
    end
    return parts
end

local function collectDrivers(parts, links)
    local drivers, count, last = {}, 0, 0
    for index, link in pairs(links) do
        if not integer(index, 1, size * size) or type(link) ~= "table" then
            return nil, "invalid internal link"
        end
        count, last = count + 1, math.max(last, index)
        local from, to = parts[link.from], parts[link.to]
        if not from or not to or not from.output or not to.input
            or link.output ~= from.output or link.input ~= to.input then
            return nil, "invalid terminal direction"
        end
        if drivers[link.to] then return nil, "input already has a driver" end
        drivers[link.to] = link.from
    end
    if count ~= last then return nil, "internal links must be a dense list" end
    return drivers
end

function Circuit.compile(layout)
    if type(layout) ~= "table" or type(layout.modules) ~= "table" or type(layout.links) ~= "table" then
        return nil, "invalid internal circuit"
    end
    local parts, reason = collectParts(layout.modules)
    if not parts then return nil, reason end
    local drivers, linkError = collectDrivers(parts, layout.links)
    if not drivers then return nil, linkError end
    for id in pairs(parts) do
        local visited, current = {}, id
        while current do
            if visited[current] then return nil, "internal circuit feedback" end
            visited[current] = true
            current = drivers[current]
        end
    end

    local thresholds, current = {}, drivers.output
    while current and current ~= "input" do
        thresholds[#thresholds + 1] = parts[current].threshold
        current = drivers[current]
    end
    local connected = current == "input"
    return function(value)
        if not connected or not integer(value, 0, 255) then return nil end
        for i = #thresholds, 1, -1 do
            value = value >= thresholds[i] and 255 or 0
        end
        return value
    end
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
