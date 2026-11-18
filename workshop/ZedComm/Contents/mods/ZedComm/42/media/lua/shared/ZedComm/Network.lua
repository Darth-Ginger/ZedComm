-- ZedComm network model: placed pieces, explicit links, derived networks.
--
-- Pure data, no game calls, so it runs the same in singleplayer, on a server
-- and in the offline tests. The world objects and the server tile registry
-- feed it records; it works out which pieces form one network and what packet
-- each network carries.
--
-- Pieces:
--   cable    - one cable piece on one square. Holds at most two links (its
--              two ends), so a run is a chain and can bend.
--   endpoint - a device on one square. Fixtures have a source or sink role.
--              Cabinets have individual jack directions, output packets and
--              directed dependencies between their jacks.
--
-- Links are explicit records. A cable links to a cable on an orthogonally
-- adjacent square, or to a free endpoint port on its own or an adjacent
-- square. Being next to something never connects it: adjacency is required
-- for a link, not sufficient (ADR-304).
--
-- Networks are derived, never stored: the connected parts of the link graph.
-- An endpoint's ports are separate nodes, so two ports on one device are not
-- joined through it. A network's id is its smallest node key; it can change
-- when the topology changes, so receivers look their network up on delivery.
--
-- Every topology or value change marks the affected networks dirty on the
-- attached simulation (ADR-305): it never recomputes inside the change.
--
-- Kahlua (Lua 5.1): no goto, no integer division, no io/os.

require "ZedComm/SignalModules"
require "ZedComm/InternalCircuit"

local Packet = ZedComm.SignalModules.Packet
local Circuit = ZedComm.InternalCircuit
local Network = {}
Network.__index = Network

Network.MAX_CABLE_LINKS = 2
Network.DEFAULT_PORT = "signal"

-- Status of a derived network.
Network.OK = "ok"                     -- one live source packet
Network.NO_SOURCE = "no-source"       -- nothing drives it: disconnected
Network.MULTI_SOURCE = "multi-source" -- more than one source: treated as disconnected

local function portKey(endpointId, port)
    return endpointId .. "#" .. port
end

local function direction(piece, port)
    return piece.board and piece.board.directions[port] or piece.role
end

local function sourcePacket(piece, port)
    if piece.board then return piece.packets[port] end
    return piece.packet
end

function Network.new()
    local self = setmetatable({}, Network)
    self.pieces = {}  -- id -> piece record
    self.version = 0  -- bumps on every topology change
    self.built = -1   -- version the derived networks were built for
    self.nodeNet = {} -- node key -> network id
    self.nets = {}    -- network id -> { nodes = {...}, sources = {...}, sinks = {...} }
    self.sim = nil
    return self
end

-- Attach to the shared simulation: dirty marks go to it, and its per-tick
-- pass recomputes through this model.
function Network:attach(sim)
    self.sim = sim
    local model = self
    sim.setRecompute(function(networkId) return model:recompute(networkId) end)
end

---------------------------------------------------------------------------
-- Derived networks
---------------------------------------------------------------------------

-- Neighbouring node keys of one node.
function Network:neighbours(key)
    local out = {}
    local hash = string.find(key, "#", 1, true)
    if hash then
        local piece = self.pieces[string.sub(key, 1, hash - 1)]
        local cableId = piece and piece.ports[string.sub(key, hash + 1)]
        if cableId then out[1] = cableId end
    else
        local piece = self.pieces[key]
        if piece then
            for otherId, port in pairs(piece.links) do
                if port == true then out[#out + 1] = otherId
                else out[#out + 1] = portKey(otherId, port) end
            end
        end
    end
    return out
end

function Network:build()
    if self.built == self.version then return end
    local nodeNet, nets = {}, {}
    local all = {}
    for id, piece in pairs(self.pieces) do
        if piece.kind == "cable" then
            all[#all + 1] = id
        else
            for port in pairs(piece.ports) do all[#all + 1] = portKey(id, port) end
        end
    end
    local seen = {}
    for i = 1, #all do
        local start = all[i]
        if not seen[start] then
            local nodes, stack = {}, { start }
            seen[start] = true
            while #stack > 0 do
                local key = table.remove(stack)
                nodes[#nodes + 1] = key
                local next_ = self:neighbours(key)
                for j = 1, #next_ do
                    if not seen[next_[j]] then
                        seen[next_[j]] = true
                        stack[#stack + 1] = next_[j]
                    end
                end
            end
            local netId = nodes[1]
            for j = 2, #nodes do if nodes[j] < netId then netId = nodes[j] end end
            local net = { nodes = nodes, sources = {}, sinks = {} }
            for j = 1, #nodes do
                nodeNet[nodes[j]] = netId
                local hash = string.find(nodes[j], "#", 1, true)
                if hash then
                    local endpointId = string.sub(nodes[j], 1, hash - 1)
                    local piece = self.pieces[endpointId]
                    local port = string.sub(nodes[j], hash + 1)
                    if direction(piece, port) == "source" then
                        net.sources[#net.sources + 1] = endpointId
                        net.sourcePort = port
                    else
                        net.sinks[#net.sinks + 1] = endpointId
                    end
                end
            end
            nets[netId] = net
        end
    end
    self.nodeNet, self.nets, self.built = nodeNet, nets, self.version
end

-- A link only merges two runs. Project that merge onto the internal
-- dependencies before writing any links, packets, or dirty marks.
function Network:hasFeedback(mergedInto, mergedFrom, replacement)
    self:build()
    local edges = {}
    local function runOf(id, port)
        local run = self.nodeNet[portKey(id, port)]
        if run == mergedFrom then return mergedInto end
        return run
    end
    for id, piece in pairs(self.pieces) do
        local board = replacement and replacement.id == id and replacement.board or piece.board
        if board then
            for output, inputs in pairs(board.dependencies) do
                local target = runOf(id, output)
                if target then
                    for input in pairs(inputs) do
                        local source = runOf(id, input)
                        if source then
                            local group = edges[source] or {}
                            group[target] = true
                            edges[source] = group
                        end
                    end
                end
            end
        end
    end
    local visited = {}
    local function cycle(run)
        if visited[run] ~= nil then return visited[run] end
        visited[run] = true
        for target in pairs(edges[run] or {}) do
            if cycle(target) then return true end
        end
        visited[run] = false
        return false
    end
    for run in pairs(edges) do
        if cycle(run) then return true end
    end
    return false
end

-- The network a cable, or an endpoint's port, belongs to.
function Network:networkOf(id, port)
    self:build()
    local piece = self.pieces[id]
    if not piece then return nil end
    if piece.kind == "cable" then return self.nodeNet[id] end
    return self.nodeNet[portKey(id, port or Network.DEFAULT_PORT)]
end

function Network:status(networkId)
    self:build()
    local net = self.nets[networkId]
    if not net or #net.sources == 0 then return Network.NO_SOURCE end
    if #net.sources > 1 then return Network.MULTI_SOURCE end
    local source = self.pieces[net.sources[1]]
    if source.definitionUnavailable or sourcePacket(source, net.sourcePort) == nil then return Network.NO_SOURCE end
    return Network.OK
end

-- Return a snapshot of the current packet, or nil for unavailable input.
-- A caller may inspect its copy without changing the held signal (ADR-309).
function Network:recompute(networkId)
    if self:status(networkId) ~= Network.OK then return nil end
    local net = self.nets[networkId]
    return Packet.copy(sourcePacket(self.pieces[net.sources[1]], net.sourcePort))
end

-- Sink endpoints on a network, for delivery.
function Network:sinksOf(networkId)
    self:build()
    local net = self.nets[networkId]
    local out = {}
    if net then
        for i = 1, #net.sinks do
            local id = net.sinks[i]
            if not self.pieces[id].definitionUnavailable then out[#out + 1] = id end
        end
    end
    return out
end

function Network:networkCount()
    self:build()
    local n = 0
    for _ in pairs(self.nets) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Dirty marking
---------------------------------------------------------------------------

-- Node keys touched by a change to these pieces: every node in their current
-- networks. Taken before the change, then re-resolved after it, so both the
-- network that lost a piece and the one that gained it are marked.
function Network:affectedNodes(ids)
    self:build()
    local nodes = {}
    for i = 1, #ids do
        local piece = self.pieces[ids[i]]
        if piece then
            local keys = {}
            if piece.kind == "cable" then keys[1] = ids[i]
            else for port in pairs(piece.ports) do keys[#keys + 1] = portKey(ids[i], port) end end
            for k = 1, #keys do
                local net = self.nets[self.nodeNet[keys[k]]]
                if net then for j = 1, #net.nodes do nodes[net.nodes[j]] = true end end
            end
        end
    end
    return nodes
end

function Network:changed(nodes)
    self.version = self.version + 1
    if not self.sim then return end
    self:build()
    local marked = {}
    for key in pairs(nodes) do
        local netId = self.nodeNet[key]
        if netId and not marked[netId] then
            marked[netId] = true
            self.sim.markDirty(netId)
        end
    end
end

---------------------------------------------------------------------------
-- Changes
---------------------------------------------------------------------------

local function checkPosition(x, y, z)
    return type(x) == "number" and type(y) == "number" and type(z) == "number"
end

function Network:addCable(id, x, y, z)
    if type(id) ~= "string" or string.find(id, "#", 1, true) then return false, "bad id" end
    if not checkPosition(x, y, z) then return false, "bad position" end
    local existing = self.pieces[id]
    if existing then
        if existing.kind == "cable" and existing.x == x and existing.y == y and existing.z == z then
            return true -- already registered: loading twice adds nothing
        end
        return false, "id in use"
    end
    self.pieces[id] = { id = id, kind = "cable", x = x, y = y, z = z, links = {} }
    self:changed({ [id] = true })
    return true
end

-- Kahlua modData can store string/number keys and plain serializable values.
-- Reject unsupported state before changing a record. The copy also separates
-- the caller, model and saved record so updates go through the registry.
local function copyState(state, ancestors, depth)
    if type(state) ~= "table" or getmetatable(state) ~= nil then
        return nil, "state must be a plain table"
    end
    if ancestors[state] then return nil, "cyclic device state" end
    if depth > 32 then return nil, "device state is too deeply nested" end
    ancestors[state] = true
    local copy = {}
    for key, value in pairs(state) do
        local keyType, valueType = type(key), type(value)
        if keyType ~= "string" and (keyType ~= "number" or key - key ~= 0) then
            return nil, "unsupported device state key"
        end
        if valueType == "table" then
            local child, err = copyState(value, ancestors, depth + 1)
            if not child then return nil, err end
            copy[key] = child
        elseif valueType == "string" or valueType == "boolean"
            or (valueType == "number" and value - value == 0) then
            copy[key] = value
        else
            return nil, "unsupported device state value"
        end
    end
    ancestors[state] = nil
    return copy
end

local function validatedState(definitionId, state)
    if definitionId ~= nil and (type(definitionId) ~= "string" or definitionId == "") then
        return nil, "bad definition id"
    end
    if state == nil then return nil end
    if definitionId == nil then return nil, "device state requires a definition id" end
    return copyState(state, {}, 1)
end

-- Persist device metadata without running callbacks. Sources start without a
-- packet and publish their first live reading through the runtime.
-- role: "source", "sink" or "cabinet". ports: list of port names (default
-- { "signal" }); a cabinet's ports come from its circuit.
function Network:addEndpoint(id, x, y, z, role, ports, definitionId, state)
    if type(id) ~= "string" or string.find(id, "#", 1, true) then return false, "bad id" end
    if not checkPosition(x, y, z) then return false, "bad position" end
    if role ~= "source" and role ~= "sink" and (role ~= "cabinet" or definitionId ~= Circuit.CABINET_ID) then
        return false, "bad role"
    end
    local existing = self.pieces[id]
    if existing then
        if existing.kind == "endpoint" and existing.role == role
            and existing.definitionId == definitionId and existing.x == x and existing.y == y and existing.z == z then
            return true
        end
        return false, "id in use"
    end
    local stateCopy, stateError = validatedState(definitionId, state)
    if stateError then return false, stateError end
    local portTable = {}
    local evaluate, board
    local profile = Circuit.profileFor(definitionId)
    if profile then
        if definitionId == Circuit.DOOR_ID and role ~= "sink" then return false, "door must be a receiver" end
        evaluate, stateError, board = Circuit.compilePackets(stateCopy and stateCopy.circuit, profile,
            stateCopy and stateCopy.adapter)
        if not evaluate then return false, stateError end
        for port in pairs(board.directions) do portTable[port] = false end
    else
        ports = ports or { Network.DEFAULT_PORT }
        for i = 1, #ports do
            if string.find(ports[i], "#", 1, true) then return false, "bad port" end
            portTable[ports[i]] = false
        end
    end
    self.pieces[id] = {
        id = id, kind = "endpoint", x = x, y = y, z = z,
        role = role, ports = portTable,
        definitionId = definitionId, state = stateCopy,
        board = board, evaluate = evaluate, packets = board and {} or nil,
    }
    local nodes = {}
    for port in pairs(portTable) do nodes[portKey(id, port)] = true end
    self:changed(nodes)
    return true
end

local function linkCount(cable)
    local n = 0
    for _ in pairs(cable.links) do n = n + 1 end
    return n
end

-- Connect a cable to an adjacent cable (port nil) or to an endpoint's port.
function Network:link(cableId, otherId, port)
    local cable, other = self.pieces[cableId], self.pieces[otherId]
    if not cable or not other then return false, "unknown piece" end
    if cable.kind ~= "cable" then return false, "first piece must be a cable" end
    if cableId == otherId then return false, "cannot link to itself" end
    if cable.links[otherId] ~= nil then return false, "already linked" end
    if cable.z ~= other.z then return false, "not on the same level" end
    local distance = math.abs(cable.x - other.x) + math.abs(cable.y - other.y)
    if linkCount(cable) >= Network.MAX_CABLE_LINKS then return false, "cable has no free end" end

    if other.kind == "cable" then
        if port ~= nil then return false, "cables have no ports" end
        if distance ~= 1 then return false, "cables must be on adjacent squares" end
        if linkCount(other) >= Network.MAX_CABLE_LINKS then return false, "cable has no free end" end
    else
        port = port or Network.DEFAULT_PORT
        if other.ports[port] == nil then return false, "no such port" end
        if other.ports[port] ~= false then return false, "port in use" end
        if distance > 1 then return false, "endpoint is not on or next to the cable" end
    end
    self:build()
    local a = self.nodeNet[cableId]
    local b = self.nodeNet[port and portKey(otherId, port) or otherId]
    if a ~= b then
        if #self.nets[a].sources > 0 and #self.nets[b].sources > 0 then
            return false, port and "network already has a source" or "would join two sources"
        end
        if self:hasFeedback(a, b) then return false, "cabinet circuit feedback" end
    end

    local nodes = self:affectedNodes({ cableId, otherId })
    if other.kind == "cable" then
        cable.links[otherId] = true
        other.links[cableId] = true
    else
        cable.links[otherId] = port
        other.ports[port] = cableId
    end
    self:changed(nodes)
    return true
end

function Network:unlink(cableId, otherId)
    local cable, other = self.pieces[cableId], self.pieces[otherId]
    if not cable or not other or cable.kind ~= "cable" then return false, "unknown link" end
    local port = cable.links[otherId]
    if port == nil then return false, "not linked" end
    local nodes = self:affectedNodes({ cableId, otherId })
    cable.links[otherId] = nil
    if port == true then other.links[cableId] = nil
    else other.ports[port] = false end
    self:changed(nodes)
    return true
end

-- Remove a piece and every link it holds. For an endpoint this is pickup
-- (ADR-304): its cables stay placed, with that end free again.
function Network:remove(id)
    local piece = self.pieces[id]
    if not piece then return false, "unknown piece" end
    local nodes = self:affectedNodes({ id })
    if piece.kind == "cable" then
        for otherId, port in pairs(piece.links) do
            local other = self.pieces[otherId]
            if port == true then other.links[id] = nil
            else other.ports[port] = false end
        end
    else
        for _, cableId in pairs(piece.ports) do
            if cableId then self.pieces[cableId].links[id] = nil end
        end
    end
    self.pieces[id] = nil
    -- The removed piece's own nodes no longer resolve; the rest are re-marked.
    self:changed(nodes)
    return true
end

-- Publish a current packet, or clear it with nil. Mark only on a real change.
function Network:setPacket(id, packet, port)
    local piece = self.pieces[id]
    if not piece or piece.kind ~= "endpoint" or (piece.board and piece.board.directions[port] ~= "source")
        or (not piece.board and piece.role ~= "source") then
        return false, "not a source"
    end
    if piece.definitionUnavailable then return false, "device definition unavailable" end
    local valid, reason = Packet.validate(packet)
    if not valid then return false, reason end
    if Packet.equal(sourcePacket(piece, port), packet) then return true end
    if piece.board then
        piece.packets[port] = Packet.copy(packet)
        if self.sim then self.sim.markDirty(self:networkOf(id, port)) end
    else
        piece.packet = Packet.copy(packet)
        if self.sim then
            for name in pairs(piece.ports) do
                self.sim.markDirty(self:networkOf(id, name))
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Records: what the server registry saves, and rebuilds the model from
---------------------------------------------------------------------------

function Network:setDeviceState(id, state)
    local piece = self.pieces[id]
    if not piece or not piece.definitionId then return false, "not a defined endpoint" end
    if piece.definitionUnavailable then return false, "device definition unavailable" end
    local stateCopy, err = validatedState(piece.definitionId, state)
    if err then return false, err end
    if piece.state and piece.state.fixtureName then
        stateCopy = stateCopy or {}
        stateCopy.fixtureName = piece.state.fixtureName
    end
    if piece.board then
        local evaluate, reason, board = Circuit.compilePackets(stateCopy and stateCopy.circuit, piece.board.profile,
            stateCopy and stateCopy.adapter)
        if not evaluate then return false, reason end
        if self:hasFeedback(nil, nil, { id = id, board = board }) then return false, "cabinet circuit feedback" end
        local affected, ports = self:affectedNodes({ id }), {}
        for port, role in pairs(board.directions) do
            if piece.board.directions[port] and piece.board.directions[port] ~= role then
                return false, "cabinet port direction cannot change"
            end
            ports[port] = piece.ports[port] or false
            affected[portKey(id, port)] = true
        end
        for port, cable in pairs(piece.ports) do
            if ports[port] == nil then
                if cable then self.pieces[cable].links[id] = nil end
                piece.packets[port] = nil
                if stateCopy.portLabels then stateCopy.portLabels[port] = nil end
            end
        end
        piece.ports, piece.board, piece.evaluate = ports, board, evaluate
        piece.state = stateCopy
        self:changed(affected)
        return true
    end
    piece.state = stateCopy
    return true
end

local function cleanLabel(name)
    if type(name) ~= "string" or name:find("[%c]") then return nil, "Use a single-line label." end
    name = name:match("^%s*(.-)%s*$")
    if #name > 64 then return nil, "Use a shorter label." end
    return name
end

-- Labels change the saved record without rebuilding the board or restarting timers.
function Network:renameFixture(id, name)
    local piece = self.pieces[id]
    if not piece or piece.kind ~= "endpoint" or not piece.definitionId or piece.definitionUnavailable then
        return false, "That fixture is no longer available."
    end
    local label, reason = cleanLabel(name)
    if not label then return false, reason end
    piece.state = piece.state or {}
    piece.state.fixtureName = label ~= "" and label or nil
    return true, piece.state.fixtureName
end

function Network:renameCabinetPort(id, port, name)
    local piece = self.pieces[id]
    if not piece or not piece.board or not piece.board.directions[port] then return false, "That cabinet jack is gone." end
    local label, reason = cleanLabel(name)
    if not label then return false, reason end
    local labels = piece.state.portLabels or {}
    piece.state.portLabels = labels
    labels[port] = label ~= "" and label or nil
    return true, Circuit.jackLabel(port, piece.board.directions[port], labels[port])
end

-- One plain record per piece, a copy the caller may keep. Each side of a
-- link is stored with its piece, so a piece's record is complete on its own
-- tile. Nil for an unknown id.
function Network:record(id)
    local piece = self.pieces[id]
    if not piece then return nil end
    local r = { id = id, kind = piece.kind, x = piece.x, y = piece.y, z = piece.z }
    if piece.kind == "cable" then
        r.links = {}
        for otherId, port in pairs(piece.links) do r.links[otherId] = port end
    else
        r.role, r.ports = piece.role, {}
        r.definitionId = piece.definitionId
        if piece.state ~= nil then r.state = copyState(piece.state, {}, 1) end
        for port, cableId in pairs(piece.ports) do r.ports[port] = cableId end
    end
    return r
end

-- Ids of the pieces linked to this one.
function Network:partners(id)
    local piece, out = self.pieces[id], {}
    if not piece then return out end
    if piece.kind == "cable" then
        for otherId in pairs(piece.links) do out[#out + 1] = otherId end
    else
        for _, cableId in pairs(piece.ports) do
            if cableId then out[#out + 1] = cableId end
        end
    end
    return out
end

function Network:records()
    local out = {}
    for id in pairs(self.pieces) do out[#out + 1] = self:record(id) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Rebuild from saved records. Pieces first, then links, through the normal
-- checks, so a loaded model obeys the same rules as a built one. A link only
-- one side remembers, or one that breaks a rule, is dropped and reported.
-- Loading the same records twice registers nothing twice.
function Network:load(records)
    local dropped = {}
    for i = 1, #records do
        local r = records[i]
        local ok, err
        if r.kind == "cable" then
            ok, err = self:addCable(r.id, r.x, r.y, r.z)
        else
            local ports = {}
            for port in pairs(r.ports or {}) do ports[#ports + 1] = port end
            table.sort(ports)
            ok, err = self:addEndpoint(r.id, r.x, r.y, r.z, r.role, ports, r.definitionId, r.state)
        end
        if not ok then dropped[#dropped + 1] = r.id .. ": " .. err end
    end
    local byId = {}
    for i = 1, #records do byId[records[i].id] = records[i] end
    for i = 1, #records do
        local r = records[i]
        if r.kind == "cable" and self.pieces[r.id] then
            for otherId, port in pairs(r.links or {}) do
                local o = byId[otherId]
                local mutual = o and (
                    (port == true and o.links and o.links[r.id] == true) or
                    (port ~= true and o.ports and o.ports[port] == r.id))
                if not mutual then
                    dropped[#dropped + 1] = r.id .. " -> " .. otherId .. ": one-sided link"
                elseif self.pieces[r.id].links[otherId] == nil then
                    local ok, err = self:link(r.id, otherId, port ~= true and port or nil)
                    if not ok then dropped[#dropped + 1] = r.id .. " -> " .. otherId .. ": " .. err end
                end
            end
        end
    end
    return dropped
end

ZedComm.Network = Network
return Network
