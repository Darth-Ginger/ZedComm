if isClient() or isServer() then return end

require "PZAPI/ModOptions"

local options = PZAPI.ModOptions:create("ZedComm", "ZedComm")
local fixtureLabels = options:addTickBox("fixtureLabels", getText("IGUI_ZedComm_FixtureLabels"), true,
    getText("IGUI_ZedComm_FixtureLabelsTooltip"))
local doorMarkers = options:addTickBox("doorMarkers", getText("IGUI_ZedComm_DoorMarkers"), true,
    getText("IGUI_ZedComm_DoorMarkersTooltip"))

local doorId = ZedComm.InternalCircuit.DOOR_ID
local range = 12

local function visible(square)
    return square and square:isCouldSee(0)
end

local function draw(textManager, text, x, y)
    textManager:DrawStringCentre(UIFont.Small, x + 1, y + 1, text, 0, 0, 0, 1)
    textManager:DrawStringCentre(UIFont.Small, x, y, text, 1, 1, 1, 1)
end

Events.OnPostUIDraw.Add(function()
    local showLabels, showMarkers = fixtureLabels:getValue(), doorMarkers:getValue()
    if not showLabels and not showMarkers then return end
    local placement = ZedComm.PlayerPlacement
    local registry = placement and placement.getRegistry()
    local player, cell = getSpecificPlayer(0), getCell()
    if not registry or not player or not cell or player:isDead() then return end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
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
                local x, y = piece.x + 0.5, piece.y + 0.5
                local show = visible(entry.square)
                if door and entry.object:isNorth() then
                    y = piece.y
                    show = show or visible(cell:getGridSquare(piece.x, piece.y - 1, pz))
                elseif door then
                    x = piece.x
                    show = show or visible(cell:getGridSquare(piece.x - 1, piece.y, pz))
                end
                if show then
                    local screenX = isoToScreenX(0, x, y, pz)
                    local screenY = isoToScreenY(0, x, y, pz + (door and 1.7 or 0.45))
                    if showMarker then
                        local locked = entry.object:isLocked() or entry.object:isLockedByKey()
                        local icon = getTexture(locked and "media/textures/ZedCommMaglockLocked.png"
                            or "media/textures/ZedCommMaglockUnlocked.png")
                        if icon then UIManager.DrawTexture(icon, screenX - icon:getWidth() / 2, screenY - icon:getHeight()) end
                        draw(textManager, (locked and "Locked" or "Unlocked") .. " / "
                            .. (entry.object:isOpen() and "Open" or "Closed"), screenX, screenY)
                        screenY = screenY - 35
                    end
                    if showName then
                        local key = piece.x .. "," .. piece.y
                        local row = rows[key] or 0
                        rows[key] = row + 1
                        draw(textManager, piece.state.fixtureName or entry.spec.fixtureType, screenX, screenY - row * 16)
                    end
                end
            end
        end
    end
end)
