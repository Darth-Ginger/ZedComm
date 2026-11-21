if isClient() or isServer() then return end

require "PZAPI/ModOptions"

local options = PZAPI.ModOptions:create("ZedComm", "ZedComm")
local fixtureLabels = options:addTickBox("fixtureLabels", getText("IGUI_ZedComm_FixtureLabels"), true,
    getText("IGUI_ZedComm_FixtureLabelsTooltip"))
local doorMarkers = options:addTickBox("doorMarkers", getText("IGUI_ZedComm_DoorMarkers"), true,
    getText("IGUI_ZedComm_DoorMarkersTooltip"))

local doorId = ZedComm.InternalCircuit.DOOR_ID
local range = 12
local iconFolder = "media/textures/"
local fixtureHeight = {
    Cabinet = 60, Lamp = 52, Switch = 48, Display = 25, Source = 25,
    Plate = 14, ["Door Contact"] = 37, ["Window Contact"] = 46,
}

local function visible(square)
    return square and square:isCouldSee(0)
end

local function position(entry, door)
    local piece = entry.piece
    local x, y = piece.x + 0.5, piece.y + 0.5
    local contact = ZedComm.DoorContact
    local host = door and entry.object
        or (contact.profiles[piece.definitionId] and contact.host(entry.object))
    if host then
        if host:isNorth() then y = piece.y else x = piece.x end
        return x, y, ZedComm.Door.oppositeSquare(host)
    end
    local mount = piece.state and piece.state.mount
    if mount == "west" then x = piece.x end
    if mount == "east" then x = piece.x + 1 end
    if mount == "north" then y = piece.y end
    if mount == "south" then y = piece.y + 1 end
    return x, y
end

local function drawName(textManager, name, x, y)
    textManager:DrawStringCentre(UIFont.Small, x + 1, y + 1, name, 0, 0, 0, 1)
    textManager:DrawStringCentre(UIFont.Small, x, y, name, 1, 1, 1, 1)
end

local function drawStatus(entry, x, y)
    local object = entry.object
    local locked = object:isLocked() or object:isLockedByKey()
    local lock = getTexture(iconFolder .. (locked and "ZedCommMaglockLocked.png" or "ZedCommMaglockUnlocked.png"))
    local door = getTexture(iconFolder .. (object:isOpen() and "ZedCommDoorOpen.png" or "ZedCommDoorClosed.png"))
    if lock then UIManager.DrawTexture(lock, x - lock:getWidth() - 1, y - lock:getHeight()) end
    if door then UIManager.DrawTexture(door, x + 1, y - door:getHeight()) end
end

Events.OnPreUIDraw.Add(function()
    local showLabels, showMarkers = fixtureLabels:getValue(), doorMarkers:getValue()
    if not showLabels and not showMarkers then return end
    local placement = ZedComm.PlayerPlacement
    local registry = placement and placement.getRegistry()
    local player = getSpecificPlayer(0)
    if not registry or not player or player:isDead() then return end
    local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
    local scale = Core.getTileScale() / getCore():getZoom(0)
    local textManager = getTextManager()
    local rows = {}
    for id, piece in pairs(registry.network.pieces) do
        local showName = showLabels and piece.state and piece.state.showFixtureName
        local door = piece.definitionId == doorId
        local showMarker = door and showMarkers
        if (showName or showMarker) and piece.z == pz and math.abs(piece.x - px) <= range
            and math.abs(piece.y - py) <= range then
            local entry = placement.resolve(registry, id)
            if entry then
                local x, y, opposite = position(entry, door)
                if visible(entry.square) or visible(opposite) then
                    local height = door and 64 or fixtureHeight[entry.spec.fixtureType] or 25
                    local lift = height / 2 + entry.object:getRenderYOffset()
                    local screenX = isoToScreenX(0, x, y, piece.z)
                    local screenY = isoToScreenY(0, x, y, piece.z) - lift * scale
                    if showMarker then
                        drawStatus(entry, screenX, screenY)
                        screenY = screenY - 16
                    end
                    if showName then
                        local key = piece.x .. "," .. piece.y
                        local row = rows[key] or 0
                        rows[key] = row + 1
                        drawName(textManager, piece.state.fixtureName or entry.spec.fixtureType, screenX, screenY - 14 - row * 16)
                    end
                end
            end
        end
    end
end)
