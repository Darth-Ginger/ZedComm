-- Choose visual lanes from the actual links crossing each tile edge.
ZedComm = ZedComm or {}
local WireShape = {}

-- Directions are +X, +Y, -X, -Y. The lane increases along +Y on
-- an X seam and +X on a Y seam, from either side of the seam.
local directionIndex = { [1] = 0, [2] = 1, [4] = 2, [8] = 3 }
local clockwise = { [0] = 1, [1] = -1, [2] = -1, [3] = 1 }
local indices = { [0] = 3, [1] = 4, [2] = 5, [3] = 6, [4] = 7, [5] = 8,
    [6] = 9, [8] = 10, [9] = 11, [10] = 12, [12] = 13 }
local lanes = { { 0 }, { -1, 1 }, { -1, 0, 1 }, { -2, -1, 1, 2 }, { -2, -1, 0, 1, 2 } }
local sideLanes = { { 1 }, { -1, 1 }, { -2, -1, 1 }, { -2, -1, 1, 2 } }

function WireShape.directionBit(piece, other)
    if not other or piece.z ~= other.z then return nil end
    local dx, dy = other.x - piece.x, other.y - piece.y
    if dx == 1 and dy == 0 then return 1 end
    if dx == 0 and dy == 1 then return 2 end
    if dx == -1 and dy == 0 then return 4 end
    if dx == 0 and dy == -1 then return 8 end
end

local function sameSquare(a, b)
    return b and a.x == b.x and a.y == b.y and a.z == b.z
end

-- A same-tile cable has direction 0. A free port has no direction.
function WireShape.portDirection(network, piece, port)
    local cable = network.pieces[piece.ports[port]]
    if sameSquare(piece, cable) then return 0 end
    return WireShape.directionBit(piece, cable)
end

local function squareKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function collectRoutes(network)
    local routes, seams, tiles = {}, {}, {}
    network:build()
    for id, piece in pairs(network.pieces) do
        if piece.kind == "cable" then
            local route = { id = id, edges = {} }
            routes[id] = route
            local tileKey = squareKey(piece.x, piece.y, piece.z)
            tiles[tileKey] = tiles[tileKey] or {}
            local tile = tiles[tileKey]
            tile[#tile + 1] = route
            for otherId, port in pairs(piece.links) do
                local other = network.pieces[otherId]
                local bit = WireShape.directionBit(piece, other)
                if bit then
                    local seamKey = squareKey(math.min(piece.x, other.x), math.min(piece.y, other.y), piece.z)
                        .. (piece.x ~= other.x and ":x" or ":y")
                    local seam = seams[seamKey]
                    if not seam then
                        seam = { key = seamKey, links = {}, byId = {}, neighbors = {} }
                        seams[seamKey] = seam
                    end
                    local linkKey = id < otherId and id .. "#" .. otherId or otherId .. "#" .. id
                    local link = seam.byId[linkKey]
                    if not link then
                        link = { key = linkKey, networkId = network.nodeNet[id], port = port ~= true }
                        seam.byId[linkKey] = link
                        seam.links[#seam.links + 1] = link
                    end
                    route.edges[#route.edges + 1] = { bit = bit, seam = seam, link = link }
                elseif port ~= true and sameSquare(piece, other) then
                    route.localPort = true
                end
            end
        end
    end
    return routes, seams, tiles
end

local function bundleDirections(routes)
    local bundles = {}
    for _, route in pairs(routes) do
        local a, b = route.edges[1], route.edges[2]
        if b and a.seam ~= b.seam and not a.link.port and not b.link.port then
            if a.seam.key > b.seam.key then a, b = b, a end
            local key = a.seam.key .. "|" .. b.seam.key
            local first = bundles[key]
            if first and first ~= route then
                -- Two runs using the same turn must have opposite order
                -- around the tile perimeter, so their bends can nest.
                local sign = -clockwise[directionIndex[a.bit]] * clockwise[directionIndex[b.bit]]
                a.seam.neighbors[b.seam.key] = sign
                b.seam.neighbors[a.seam.key] = sign
            else
                bundles[key] = route
            end
        end
    end
end

local function sortedKeys(entries)
    local keys = {}
    for key in pairs(entries) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function orientSeams(seams)
    for _, key in ipairs(sortedKeys(seams)) do
        local root = seams[key]
        if not root.sign then
            root.sign = 1
            local queue = { root }
            local i = 1
            while queue[i] do
                local seam = queue[i]
                for _, neighborKey in ipairs(sortedKeys(seam.neighbors)) do
                    local neighbor = seams[neighborKey]
                    if not neighbor.sign then
                        neighbor.sign = seam.sign * seam.neighbors[neighborKey]
                        queue[#queue + 1] = neighbor
                    end
                end
                i = i + 1
            end
        end
    end
end

local function assignSeamLanes(seams)
    for _, seam in pairs(seams) do
        local cables = {}
        local hasPort = false
        for _, link in ipairs(seam.links) do
            if link.port then
                link.lane = 0
                hasPort = true
            else
                cables[#cables + 1] = link
            end
        end
        table.sort(cables, function(a, b)
            if a.networkId ~= b.networkId then return a.networkId < b.networkId end
            return a.key < b.key
        end)
        local choices = hasPort and sideLanes or lanes
        local positions = choices[math.min(#cables, #choices)]
        for i, link in ipairs(cables) do link.lane = positions[math.min(i, #positions)] * seam.sign end
    end
end

local function assignLooseLanes(tiles)
    for _, tile in pairs(tiles) do
        local loose = {}
        for _, route in ipairs(tile) do
            if #route.edges == 0 and not route.localPort then loose[#loose + 1] = route end
        end
        table.sort(loose, function(a, b) return a.id < b.id end)
        local choices = #loose == #tile and lanes or sideLanes
        local positions = choices[math.min(#loose, #choices)]
        for i, route in ipairs(loose) do route.lane = positions[math.min(i, #positions)] end
    end
end

local function edgeCode(edge)
    return directionIndex[edge.bit] * 5 + edge.link.lane + 2
end

local function frameFor(route)
    local a, b = route.edges[1], route.edges[2]
    -- Frames 184–418 mirror the stub, one-edge, and two-edge groups in the packer.
    if not a then return route.lane and route.lane ~= 0 and 184 + route.lane + 2 or indices[0] end
    if not b then
        if #a.seam.links == 1 then return indices[a.bit] end
        return 189 + (route.localPort and 20 or 0) + edgeCode(a)
    end
    if #a.seam.links == 1 and #b.seam.links == 1 and a.bit ~= b.bit then
        return indices[a.bit + b.bit]
    end
    local first, second = edgeCode(a), edgeCode(b)
    if first > second then first, second = second, first end
    if first == second then return 189 + first end
    return 229 + first * (39 - first) / 2 + second - first - 1
end

function WireShape.layout(network)
    local routes, seams, tiles = collectRoutes(network)
    bundleDirections(routes)
    orientSeams(seams)
    assignSeamLanes(seams)
    assignLooseLanes(tiles)
    local sprites = {}
    for id, route in pairs(routes) do sprites[id] = "zedcomm_devices_01_" .. frameFor(route) end
    return sprites
end

ZedComm.WireShape = WireShape
return WireShape

