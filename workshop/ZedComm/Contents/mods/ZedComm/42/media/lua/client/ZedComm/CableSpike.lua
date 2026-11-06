-- ZedComm cable spike (Implement Endpoints And Cables, first criterion).
--
-- Question it answers: does a plain IsoObject placed by a mod, carrying a
-- ZedComm id in its modData, come back after save and load?
--
-- Singleplayer only, and temporary: it puts three options in the right-click
-- menu of any square, under "ZedComm spike":
--   Place test cable   - adds a tagged IsoObject to the square
--   Show pieces here   - says how many tagged objects the square holds
--   Remove test cables - removes them again
-- On load, every tagged object found while chunks load is printed to
-- console.txt as "[ZedComm spike] found ...". Remove this file once the real
-- cable placement replaces it.

if isClient() or isServer() then return end -- multiplayer is out of scope for the spike

local Spike = {}

-- A vanilla sprite stands in until ZedComm has its own art. The first name
-- the game knows is used; if none is known the menu says so.
Spike.SPRITES = { "trash_01_9", "trash_01_40", "carpentry_02_53" }
Spike.found = 0

local function pickSprite()
    for i = 1, #Spike.SPRITES do
        if getSprite(Spike.SPRITES[i]) then return Spike.SPRITES[i] end
    end
    return nil
end

local function tagOf(object)
    if not object or not object.hasModData or not object:hasModData() then return nil end
    local data = object:getModData()
    return data and data.zedcomm
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
    local p = getSpecificPlayer(player)
    if p then p:Say(text) end
    print("[ZedComm spike] " .. text)
end

function Spike.place(player, square)
    local sprite = pickSprite()
    if not sprite then
        say(player, "no stand-in sprite found; edit Spike.SPRITES")
        return
    end
    local n = #taggedOn(square) + 1
    local id = "spike-" .. where(square) .. "-" .. n .. "-" .. getTimestampMs()
    local object = IsoObject.new(square, sprite, "ZedCommTestCable")
    object:getModData().zedcomm = { id = id, kind = "cable", spike = 1 }
    square:AddTileObject(object)
    -- AddTileObject does not fire this in singleplayer; vanilla traps and
    -- rain barrels fire it by hand so their server systems register them.
    triggerEvent("OnObjectAdded", object)
    say(player, "placed " .. id .. " (" .. sprite .. "), " .. n .. " on this square")
end

function Spike.show(player, square)
    local tagged = taggedOn(square)
    local ids = {}
    for i = 1, #tagged do ids[i] = tagOf(tagged[i]).id end
    say(player, #tagged .. " ZedComm piece(s) at " .. where(square)
        .. (#ids > 0 and (": " .. table.concat(ids, ", ")) or ""))
end

function Spike.remove(player, square)
    local tagged = taggedOn(square)
    for i = 1, #tagged do
        square:transmitRemoveItemFromSquare(tagged[i])
    end
    say(player, "removed " .. #tagged .. " test cable(s) at " .. where(square))
end

local function onFillMenu(player, context, worldObjects, test)
    if test then return end -- probe pass: no menu changes
    local square = nil
    for _, object in ipairs(worldObjects) do
        square = object:getSquare()
        if square then break end
    end
    if not square then return end

    local root = context:addOption("ZedComm spike", nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    sub:addOption("Place test cable", player, Spike.place, square)
    sub:addOption("Show pieces here", player, Spike.show, square)
    sub:addOption("Remove test cables", player, Spike.remove, square)
end

-- Report every tagged object that comes back as its chunk loads.
local function onLoadSquare(square)
    local tagged = taggedOn(square)
    for i = 1, #tagged do
        Spike.found = Spike.found + 1
        print("[ZedComm spike] found " .. tostring(tagOf(tagged[i]).id) .. " at " .. where(square))
    end
end

local function onGameStart()
    print("[ZedComm spike] ready; " .. Spike.found .. " tagged object(s) loaded so far")
end

Events.OnFillWorldObjectContextMenu.Add(onFillMenu)
Events.LoadGridsquare.Add(onLoadSquare)
Events.OnGameStart.Add(onGameStart)

ZedComm = ZedComm or {}
ZedComm.CableSpike = Spike
