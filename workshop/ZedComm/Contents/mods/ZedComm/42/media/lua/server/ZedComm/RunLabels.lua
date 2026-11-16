-- Names belong to connected cable runs. A saved cable anchor keeps the
-- name stable even when the derived electrical network gets a new ID.
local RunLabels = {}
RunLabels.__index = RunLabels

function RunLabels.new(network, data)
    if type(data.records) ~= "table" then data.records = {} end
    data.lastNumber = tonumber(data.lastNumber) or 0
    return setmetatable({ network = network, data = data }, RunLabels)
end

local function connectedCable(piece)
    if not piece or piece.kind ~= "cable" then return false end
    for _ in pairs(piece.links) do return true end
    return false
end

local function preferred(first, second)
    if not first then return second end
    if not second then return first end
    if first.saved.name == nil and second.saved.name ~= nil then return second end
    return first
end

function RunLabels:refresh()
    local network = self.network
    if self.version == network.version then return end
    network:build()

    local anchors, components = {}, {}
    for id, piece in pairs(network.pieces) do
        if connectedCable(piece) then
            local component = network.nodeNet[id]
            local anchor = anchors[component]
            if not anchor then
                components[#components + 1] = component
                anchors[component] = id
            elseif id < anchor then
                anchors[component] = id
            end
        end
    end
    table.sort(components)

    local names, records = {}, self.data.records
    for number, saved in pairs(records) do
        local component = network.nodeNet[saved.anchor]
        if connectedCable(network.pieces[saved.anchor]) then
            local current = names[component]
            local claim = { number = number, saved = saved }
            -- If load repaired topology, use the oldest custom name or
            -- the oldest default for a component with multiple anchors.
            local first, second = current, claim
            if current and claim.number < current.number then first, second = claim, current end
            local winner = preferred(first, second)
            if current then records[winner == claim and current.number or number] = nil end
            names[component] = winner
        else
            records[number] = nil
        end
    end
    for _, component in ipairs(components) do
        if not names[component] then
            local number = self.data.lastNumber + 1
            self.data.lastNumber = number
            local saved = { anchor = anchors[component] }
            records[number] = saved
            names[component] = { number = number, saved = saved }
        end
    end
    self.names, self.version = names, network.version
end

function RunLabels:get(id)
    if not connectedCable(self.network.pieces[id]) then return nil end
    self:refresh()
    return self.names[self.network.nodeNet[id]]
end

function RunLabels:merge(first, second)
    if not first or not second or first == second then return end
    local winner = preferred(first, second)
    self.data.records[winner == first and second.number or first.number] = nil
end

function RunLabels:beforeCut(id)
    local claim = self:get(id)
    if not claim then return nil end
    return { saved = claim.saved, nodes = self.network.nets[self.network.nodeNet[id]].nodes }
end

function RunLabels:afterCut(previous)
    if not previous or connectedCable(self.network.pieces[previous.saved.anchor]) then return end
    local survivor
    for _, id in ipairs(previous.nodes) do
        if connectedCable(self.network.pieces[id]) and (not survivor or id < survivor) then survivor = id end
    end
    if survivor then previous.saved.anchor = survivor end
end

function RunLabels:display(id)
    local claim = self:get(id)
    if not claim then return nil end
    local default = "Run " .. claim.number
    local custom = claim.saved.name
    return custom and default .. " (" .. custom .. ")" or default, custom
end

function RunLabels:rename(id, name)
    local claim = self:get(id)
    if not claim then return false, "Connect the wire before naming its run." end
    if type(name) ~= "string" or name:find("[%c]") then return false, "Use a single-line run name." end
    name = name:match("^%s*(.-)%s*$")
    if #name > 64 then return false, "Use a shorter run name." end
    claim.saved.name = name ~= "" and name or nil
    return true, self:display(id)
end

ZedComm.RunLabels = RunLabels
return RunLabels

