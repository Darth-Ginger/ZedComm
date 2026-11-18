-- Player-facing singleplayer placement and wiring actions.
if isClient() or isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"

local Action = ISBaseTimedAction:derive("ISZedCommPlacementAction")
local Cursor = { Type = "ISZedCommPlacementCursor" }
local runs = {}
local wireHover = {}
local hoverOrder = 0
local lastCabinetClick
local cabinetDoubleClickMs = 400

local function say(player, message)
    player:Say(message)
    print("[ZedComm placement] " .. message)
end

local function resolveAnchor(run)
    local placement = ZedComm.PlayerPlacement
    local registry = placement.getRegistry()
    local anchor = registry and registry.network == run.network and placement.resolve(registry, run.id)
    if placement.hasFreeEnd(anchor, run.port) then return anchor end
end

local function reachableAnchor(player, run)
    local anchor = resolveAnchor(run)
    if anchor and ZedComm.PlayerPlacement.canReach(player, anchor.square) then return anchor end
end

local function carries(player, item)
    local inventory = player:getInventory()
    return item:getContainer() == inventory and inventory:contains(item)
end

local function stopRun(player)
    local run = runs[player]
    runs[player] = nil
    if not run or not run.cursor then return end
    local cell, playerNum = getCell(), player:getPlayerNum()
    if cell and cell:getDrag(playerNum) == run.cursor then cell:setDrag(nil, playerNum) end
end

local function actionQueued(player, action)
    return action and ISTimedActionQueue.getTimedActionQueue(player):indexOf(action) ~= -1
end

local function runBusy(player, run)
    return actionQueued(player, run.walk) or actionQueued(player, run.pending)
end

function Action:new(character, command)
    local action = ISBaseTimedAction.new(self, character)
    action.command = command
    local duration = (command.kind == "upgrade-cabinet" or command.kind == "install-door"
        or command.kind == "remove-door-adapters") and 120 or 25
    action.maxTime = character:isTimedActionInstant() and 1 or duration
    return action
end

function Action:isValid()
    local placement = ZedComm.PlayerPlacement
    local registry = placement.getRegistry()
    local command = self.command
    local run = command.run
    if not registry or registry.network ~= command.network or not placement.canReach(self.character, command.square)
        or (run and (runs[self.character] ~= run or (run.id and not reachableAnchor(self.character, run)))) then
        return false
    end
    if command.kind == "lay" then
        local anchor = placement.resolve(registry, command.anchorId)
        return carries(self.character, command.item) and placement.canLay(anchor, command.anchorPort, command.square)
    end
    if command.kind == "place" then
        return carries(self.character, command.item) and placement.canPlace(command.square, command.item:getFullType())
    end
    if command.kind == "upgrade-cabinet" then
        local target = placement.resolve(registry, command.targetId)
        return target and target.object == command.object and target.square == command.square
            and placement.canUpgradeCabinet(self.character, target, command.item)
    end
    if command.kind == "install-door" then
        return ZedComm.Door.isEligible(command.object) and command.object:getSquare() == command.square
            and command.object:getModData().zedcomm == nil
            and ZedComm.DoorInstallation.materials(self.character, command.tier) ~= nil
    end
    return true
end

function Action:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function Action:complete()
    local command = self.command
    if command.run and not self:isValid() then return false end
    local ok, result = ZedComm.PlayerPlacement.perform(self.character, command)
    if not ok then
        say(self.character, tostring(result))
        return false
    end
    local run = runs[self.character]
    local looseNativeWire = command.kind == "place" and run and run.native
        and command.item:getFullType() == ZedComm.PlayerPlacement.WIRE_TYPE
    if (command.kind == "lay" and run) or looseNativeWire then
        runs[self.character] = { network = command.network, id = result, port = false,
            cursor = run.cursor, native = run.native, lastWire = run.native and command.item or nil }
        if run.native then run.cursor:clearCache() end
        say(self.character, run.cursor and "Wire laid." or "Wire laid. Select the next tile or a free end.")
    elseif command.kind == "join" and run then
        if run.native then
            runs[self.character] = nil
            run.cursor:clearCache()
        else
            stopRun(self.character)
        end
        say(self.character, "Wire connected.")
    elseif command.kind == "place" then
        if run and run.native then
            runs[self.character] = nil
            run.cursor:clearCache()
        elseif command.run then
            stopRun(self.character)
        end
        local spec = ZedComm.PlayerPlacement.getSpec(command.item:getFullType())
        say(self.character, spec.kind == "cable" and "Wire placed loose." or "Device placed.")
    elseif command.kind == "install-relay" then
        say(self.character, "Test relay installed. Select the lamp's free end to wire it.")
    elseif command.kind == "disconnect-relay" then
        say(self.character, "Relay wire disconnected. The native lamp switch works again.")
    elseif command.kind == "disconnect-port" then
        say(self.character, "Jack disconnected.")
    elseif command.kind == "install-door" then
        say(self.character, "Door adapters installed. Wire the Lock and Open jacks independently.")
    elseif command.kind == "remove-door-adapters" then
        say(self.character, "Door adapters and modules returned to inventory.")
    elseif command.kind == "upgrade-cabinet" then
        say(self.character, "Cabinet upgraded. Basic Adapter returned to inventory.")
    elseif command.kind == "set-network-switch" then
        say(self.character, command.on and "Switch on." or "Switch off.")
    elseif command.kind == "pickup" then
        if command.run and run.native then
            runs[self.character] = nil
            run.cursor:clearCache()
        elseif run and run.id == command.targetId then
            stopRun(self.character)
        end
        say(self.character, "Piece returned to inventory.")
    end
    return true
end

local function enqueuePlacement(player, command)
    local run = command.run
    if run and runs[player] ~= run then return end
    if not ZedComm.PlayerPlacement.canReach(player, command.square) then
        say(player, "Move onto or next to the target tile.")
        return
    end
    local action = Action:new(player, command)
    if not action:isValid() then
        say(player, "That item, tile, or connection is no longer available.")
        return
    end
    if run then run.pending = action end
    ISTimedActionQueue.add(action)
end

local function queue(player, command, walk)
    local run = command.run
    if run and (runs[player] ~= run or runBusy(player, run)) then return end
    local destination = command.walkSquare or command.square
    if walk and player:getCurrentSquare() ~= destination then
        if not ISWalkToTimedAction then
            say(player, "The walking action is unavailable.")
            return
        end
        local walking = ISWalkToTimedAction:new(player, destination, function()
            return runs[player] ~= run
        end)
        walking:setOnComplete(function()
            run.walk = nil
            enqueuePlacement(player, command)
        end)
        run.walk = walking
        ISTimedActionQueue.add(walking)
        return
    end
    enqueuePlacement(player, command)
end

local function orderedPieces(placement, registry, square)
    local pieces = placement.piecesAt(registry, square)
    table.sort(pieces, function(a, b) return a.id < b.id end)
    return pieces
end

local function fixtureLabel(entry, base)
    local state = entry.piece.state
    local name = state and state.fixtureName
    base = base or entry.spec.name
    return name and (base .. " (" .. name .. ")") or base
end

local function portLabel(entry, port)
    if entry.piece.board then
        local labels = entry.piece.state.portLabels
        return ZedComm.InternalCircuit.jackLabel(port, entry.piece.board.directions[port], labels and labels[port])
    end
    return port
end

local function openEnds(placement, registry, square)
    local ends, wireNumber = {}, 0
    for _, entry in ipairs(orderedPieces(placement, registry, square)) do
        local label = fixtureLabel(entry)
        if entry.piece.kind == "cable" then
            wireNumber = wireNumber + 1
            label = label .. " " .. wireNumber .. " / " .. (registry:getRunName(entry.id) or "Loose wire")
        end
        for _, port in ipairs(placement.freePorts(entry)) do
            local name = port and port ~= "signal" and label .. " (" .. portLabel(entry, port) .. ")" or label
            ends[#ends + 1] = { entry = entry, port = port, label = name }
        end
    end
    return ends
end

local function connectionChoices(placement, registry, anchor, port, square)
    local choices = {}
    if not anchor then return choices end
    for _, target in ipairs(openEnds(placement, registry, square)) do
        local entry = target.entry
        if placement.canJoin(registry.network, anchor, port, entry, target.port) then
            choices[#choices + 1] = target
        end
    end
    return choices
end

local function cursorTarget(cursor, square, run)
    local player = cursor.character
    if not square or not run or runBusy(player, run)
        or (run.choice and run.choice:isVisible()) then return end
    local placement = ZedComm.PlayerPlacement
    local registry = placement.getRegistry()
    if not registry or registry.network ~= run.network then return end
    if run.item and not carries(player, run.item) then return end
    if run.id then
        local anchor = run.item and resolveAnchor(run) or reachableAnchor(player, run)
        if not anchor then return end
        local item = run.item or player:getInventory():getFirstType(placement.WIRE_TYPE)
        if item and placement.canLay(anchor, run.port, square) then return run, item end
        if #connectionChoices(placement, registry, anchor, run.port, square) > 0 then return run end
    elseif placement.canPlace(square, run.item:getFullType())
        or (run.item:getFullType() == placement.WIRE_TYPE and #openEnds(placement, registry, square) > 0) then
        return run, run.item
    end
end

function Cursor:target(square)
    local run = runs[self.character]
    if run and run.cursor == self then return cursorTarget(self, square, run) end
end

function Cursor:isValid(square)
    local run = self:target(square)
    if run and run.item and run.item:getFullType() == ZedComm.NetworkSwitch.ID then
        self.zedcommSwitchSquare = square
        local sprite = ZedComm.PlayerPlacement.previewSprite(square, run.item, self.zedcommMount)
        if sprite ~= self.previewSprite then
            self:setSprite(sprite)
            self.previewSprite = sprite
        end
    end
    return run ~= nil
end

function Cursor:rotateKey(key)
    local run = runs[self.character]
    if self.zedcommSwitchSquare and run and run.item and run.item:getFullType() == ZedComm.NetworkSwitch.ID
        and getCore():isKey(KeybindId.ROTATE_BUILDING, key) then
        local square = self.zedcommSwitchSquare
        local current = ZedComm.PlayerPlacement.switchMount(square, run.item, self.zedcommMount)
        self.zedcommMount = ZedComm.NetworkSwitch.nextMount(square, current)
        self:isValid(square)
        return
    end
    ISBuildingObject.rotateKey(self, key)
end

local function drawInvalidTile(x, y, z)
    renderIsoRect(x + 1, y + 1, z, 1, 1, 0.12, 0.15, 1, 3)
end

function Cursor:render(x, y, z)
    if not self.canBeBuild then
        drawInvalidTile(x, y, z)
        return
    end
    local color = getCore():getGoodHighlitedColor()
    self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, color:getR(), color:getG(), color:getB(), 0.8)
end

local function placeFromCursor(player, run, item, square, anchorId, port)
    local mount
    if item:getFullType() == ZedComm.NetworkSwitch.ID then
        mount = ZedComm.PlayerPlacement.switchMount(square, item, run.cursor.zedcommMount)
    end
    queue(player, {
        kind = anchorId and "lay" or "place", item = item, square = square,
        network = run.network, anchorId = anchorId, anchorPort = port, run = run, mount = mount,
    }, true)
end

function Cursor:tryBuild(x, y, z)
    local square = getCell():getGridSquare(x, y, z)
    local run, item = self:target(square)
    if run then Cursor.placeSelected(self, run, item, square) end
end

function Cursor:deactivate()
    local run = runs[self.character]
    if run and run.cursor == self then
        -- The native right-click menu deactivates the cursor before filling
        -- its options. Keep the exact end available for an explicit join.
        runs[self.character] = run.id and { network = run.network, id = run.id, port = run.port } or nil
    end
end

function Cursor:new(character, sprite)
    -- The client menu loads before the server building scripts at startup.
    if not ISBuildingObject then return nil end
    setmetatable(self, { __index = ISBuildingObject })
    local cursor = setmetatable({}, self)
    self.__index = self
    cursor:init()
    cursor.character = character
    cursor.player = character:getPlayerNum()
    cursor:setSprite(sprite)
    -- IsoCell calls the instance field directly when replacing a drag tool.
    cursor.deactivate = Cursor.deactivate
    return cursor
end

local function selectEnd(player, network, entry, port, label)
    local placement = ZedComm.PlayerPlacement
    if not placement.canReach(player, entry.square) then
        say(player, "Move onto or next to the free end.")
        return
    end
    local run = { network = network, id = entry.id, port = port }
    if not reachableAnchor(player, run) then
        say(player, "That free end is no longer available.")
        return
    end
    local cursor = Cursor:new(player, placement.getSpec(placement.WIRE_TYPE).sprite)
    run.cursor = cursor
    runs[player] = run
    if cursor then
        getCell():setDrag(cursor, player:getPlayerNum())
        say(player, "Selected " .. label .. ". Left-click to lay wire. Right-click to stop or connect.")
    else
        say(player, "Selected " .. label .. ". Use the menu to lay wire or connect.")
    end
end

local function cancelRun(player)
    stopRun(player)
    say(player, "Wire run paused. Select a free end to resume.")
end

local function readDisplay(player, object)
    local runtime = ZedComm.DeviceRuntime
    if not runtime then return end
    local value, lit, attached, packet = runtime.getDisplay(object)
    if not attached then
        say(player, "Display unattached or awaiting update.")
    elseif packet and packet.type == "signal.advanced" then
        say(player, "Display: " .. tostring(packet.value.amount) .. " " .. packet.value.unit)
    elseif value == nil then
        say(player, "Display: no signal.")
    else
        say(player, "Display: " .. tostring(value) .. (lit and " (indicator on)" or " (indicator off)"))
    end
end

local function wireDetails(player, registry, id, label)
    local network = registry.network
    local wire = network.pieces[id]
    if not wire then
        say(player, "That wire is no longer on the tile.")
        return
    end
    local directions = {}
    for otherId, port in pairs(wire.links) do
        local other = network.pieces[otherId]
        if other then
            local direction = "same tile"
            if other.x > wire.x then direction = "east"
            elseif other.x < wire.x then direction = "west"
            elseif other.y > wire.y then direction = "south"
            elseif other.y < wire.y then direction = "north" end
            if port ~= true then direction = direction .. " device port" end
            directions[#directions + 1] = direction
        end
    end
    table.sort(directions)
    local route = #directions > 0 and table.concat(directions, " / ") or "no links"
    local runName = registry:getRunName(id) or "Loose wire"
    say(player, label .. " / " .. runName .. ": " .. route .. " (" .. (2 - #directions) .. " free ends)")
end

local function editSetting(player, registry, target, title, initial, apply)
    require "ISUI/ISTextBox"
    local modal
    local function confirm(_, button)
        if button.internal ~= "OK" then return end
        local placement = ZedComm.PlayerPlacement
        local entry = placement.getRegistry() == registry and placement.resolve(registry, target.id)
        if not entry or entry.object ~= target.object or not placement.canReach(player, entry.square) then
            say(player, "That object is no longer within reach.")
            return
        end
        say(player, apply(modal.entry:getText()))
    end
    modal = ISTextBox:new(0, 0, 320, 160, title, initial, player, confirm, player:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
end

local function renameRun(player, registry, target)
    local label, custom = registry:getRunName(target.id)
    if not label then return end
    editSetting(player, registry, target, "Rename " .. label .. " (blank resets)", custom or "", function(value)
        local ok, result = registry:renameRun(target.id, value)
        return ok and ("Run name updated to " .. result .. ".") or result
    end)
end

local function renameFixture(player, registry, target, label)
    local state = target.piece.state
    editSetting(player, registry, target, label .. " (blank resets)",
        state and state.fixtureName or "", function(value)
            local ok, result = registry:renameFixture(target.id, value)
            if not ok then return result end
            return result and ("Fixture named " .. result .. ".") or "Fixture name reset."
        end)
end

local function configurePressurePlate(player, registry, target)
    local runtime = ZedComm.DeviceRuntime
    local initial = tostring(runtime.getPressureOutput(target.piece))
    editSetting(player, registry, target, "Pressure plate output when occupied (1-255)", initial, function(value)
        local ok, reason = runtime.setPressureOutput(registry, target.id, value)
        if not ok then return reason end
        return "Pressure plate output set to " .. runtime.getPressureOutput(target.piece) .. "."
    end)
end

local function clickedSquare(worldObjects)
    for _, object in ipairs(worldObjects) do
        local square = object:getSquare()
        if square then return square end
    end
end

local function restoreHighlight(playerNum, state)
    if not state.object then return end
    local color = ColorInfo.new()
    color:setABGR(state.outlineColor)
    state.object:setOutlineHighlightCol(playerNum, color)
    state.object:setOutlineHighlight(playerNum, state.outlined)
    state.object = nil
end

local function highlightWire(option, menu, enabled, object)
    local playerNum = menu.player
    local state = wireHover[playerNum]
    if enabled then
        if not state then
            state = { hovered = {} }
            wireHover[playerNum] = state
        end
        hoverOrder = hoverOrder + 1
        state.hovered[option] = { object = object, order = hoverOrder }
    elseif state then
        state.hovered[option] = nil
    else
        return
    end

    -- Parent and child options can both be active. Keep the most recent
    -- hover so leaving an old submenu cannot clear a different wire.
    local latest
    for _, entry in pairs(state.hovered) do
        if entry.object:getSquare() and (not latest or entry.order > latest.order) then latest = entry end
    end
    local nextObject = latest and latest.object or nil
    if state.object ~= nextObject then
        restoreHighlight(playerNum, state)
        if nextObject then
            state.object = nextObject
            state.outlineColor = nextObject:getOutlineHighlightCol(playerNum)
            state.outlined = nextObject:isOutlineHighlight(playerNum)
            nextObject:setOutlineHighlightCol(playerNum, 0.15, 1, 1, 1)
            nextObject:setOutlineHighlight(playerNum, true)
        end
    end
    if not latest then wireHover[playerNum] = nil end
end

local function showPlacementChoice(cursor, run)
    local context = ISContextMenu.get(cursor.player, getMouseX(), getMouseY())
    run.choice = context
    return context
end

local function extendOrConnect(cursor, run, item, square)
    local player, placement = cursor.character, ZedComm.PlayerPlacement
    local registry, anchor = placement.getRegistry(), resolveAnchor(run)
    local ends = connectionChoices(placement, registry, anchor, run.port, square)
    if #ends == 0 then
        if item then placeFromCursor(player, run, item, square, run.id, run.port) end
        return
    end
    local context = showPlacementChoice(cursor, run)
    if item then
        context:addOption("Lay wire here", player, function()
            run.choice = nil
            placeFromCursor(player, run, item, square, run.id, run.port)
        end)
    end
    -- A fixture on furniture can be reached from the existing wire's tile.
    local approach = placement.canPlace(square, placement.WIRE_TYPE) and square or anchor.square
    for _, target in ipairs(ends) do
        local entry, port = target.entry, target.port
        local option = context:addOption("Connect to " .. target.label, player, function()
            if runs[player] ~= run then return end
            run.choice = nil
            queue(player, { kind = "join", run = run, network = run.network, square = square,
                walkSquare = approach, anchorId = run.id, anchorPort = run.port,
                targetId = entry.id, object = entry.object, port = port }, true)
        end)
        if entry.piece.kind == "cable" then
            option.onHighlight = highlightWire
            option.onHighlightParams = { entry.object }
        end
    end
end

function Cursor.placeSelected(cursor, run, item, square)
    local player, placement = cursor.character, ZedComm.PlayerPlacement
    if run.id then
        extendOrConnect(cursor, run, item, square)
        return
    end
    if item:getFullType() ~= placement.WIRE_TYPE then
        placeFromCursor(player, run, item, square)
        return
    end
    local ends = openEnds(placement, placement.getRegistry(), square)
    if #ends == 0 then
        placeFromCursor(player, run, item, square)
        return
    end
    local context = showPlacementChoice(cursor, run)
    if placement.canPlace(square, item:getFullType()) then
        context:addOption("Place wire loose", player, function()
            run.choice = nil
            placeFromCursor(player, run, item, square)
        end)
    end
    for _, target in ipairs(ends) do
        local entry, port = target.entry, target.port
        local sameTile = placement.canLay(entry, port, square)
        local label = "Connect to " .. target.label
        if not sameTile then label = label .. " from an adjacent tile" end
        local option = context:addOption(label, player, function()
            if runs[player] ~= run then return end
            run.choice = nil
            local registry = placement.getRegistry()
            local anchor = registry and registry.network == run.network and placement.resolve(registry, entry.id)
            if not placement.hasFreeEnd(anchor, port) or anchor.object ~= entry.object then
                say(player, "That free end is no longer available.")
                return
            end
            if sameTile then
                placeFromCursor(player, run, item, square, entry.id, port)
            else
                run.id, run.port = entry.id, port
                if run.native then run.cursor:clearCache() end
                say(player, "Choose a neighboring floor tile to lay the wire.")
            end
        end)
        if entry.piece.kind == "cable" then
            option.onHighlight = highlightWire
            option.onHighlightParams = { entry.object }
        end
    end
end

local function nativeRun(cursor)
    local run = runs[cursor.character]
    if run and run.native and run.cursor == cursor then return run end
end

local function nativeItemRun(cursor, item)
    return { network = ZedComm.PlayerPlacement.getRegistry().network, item = item, cursor = cursor, native = true }
end

local Native = {}

function Native.canPlace(cursor, item, square)
    local run = nativeRun(cursor) or nativeItemRun(cursor, item)
    return cursorTarget(cursor, square, run) ~= nil
end

function Native.place(cursor, item, square)
    local run, available = cursorTarget(cursor, square, nativeRun(cursor) or nativeItemRun(cursor, item))
    if not run then return end
    runs[cursor.character] = run
    Cursor.placeSelected(cursor, run, available, square)
end

function Native.activeWireItem(cursor)
    local run = nativeRun(cursor)
    return run and run.lastWire
end

function Native.activeWireLabel(cursor)
    local run = nativeRun(cursor)
    local registry = ZedComm.PlayerPlacement.getRegistry()
    if run and run.id and registry and registry.network == run.network then
        return registry:getRunName(run.id) or "Loose wire"
    end
end

function Native.drawInvalidTile(cursor, x, y, z)
    local run = nativeRun(cursor)
    if not run or (not runBusy(cursor.character, run) and not (run.choice and run.choice:isVisible())) then
        drawInvalidTile(x, y, z)
    end
end

function Native.canPickUp(cursor, entry, square)
    local placement = ZedComm.PlayerPlacement
    local registry = placement.getRegistry()
    local run = nativeRun(cursor)
    if not registry or (run and runBusy(cursor.character, run)) then return false end
    local target = placement.resolve(registry, entry.id)
    return target and target.object == entry.object and target.square == square
end

function Native.pickUp(cursor, entry, square)
    if not Native.canPickUp(cursor, entry, square) then return end
    local player = cursor.character
    local network = ZedComm.PlayerPlacement.getRegistry().network
    local run = { network = network, cursor = cursor, native = true }
    runs[player] = run
    queue(player, { kind = "pickup", targetId = entry.id, object = entry.object,
        square = square, network = network, run = run }, true)
end

function Native.previewPickup(cursor, object)
    if cursor.zedcommPickupWire == object then return end
    cursor.zedcommPickupWire = object
    highlightWire(cursor, cursor, object ~= nil, object)
end

function Native.changeSelection(cursor)
    Native.previewPickup(cursor)
    if nativeRun(cursor) then runs[cursor.character] = nil end
end

ZedComm = ZedComm or {}
ZedComm.NativePlacementActions = Native

local function placeInventoryItem(player, item)
    local placement = ZedComm.PlayerPlacement
    local registry = placement.getRegistry()
    local spec = placement.getSpec(item:getFullType())
    if not registry or not spec or not carries(player, item) then return end
    local cursor = Cursor:new(player, spec.sprite)
    if not cursor then
        say(player, "The placement cursor is unavailable.")
        return
    end
    runs[player] = { network = registry.network, item = item, cursor = cursor }
    getCell():setDrag(cursor, player:getPlayerNum())
end

local function onFillInventoryMenu(playerNum, context, items)
    local player, placement = getSpecificPlayer(playerNum), ZedComm.PlayerPlacement
    if not player or not placement or not placement.getRegistry() then return end
    local selected = ISInventoryPane.getActualItems(items)
    local first = selected[1]
    if not first then return end
    local itemType = first:getFullType()
    if not placement.getSpec(itemType) then return end
    for _, item in ipairs(selected) do
        if item:getFullType() ~= itemType or not carries(player, item) then return end
    end
    context:addOption("Place with ZedComm cursor", player, placeInventoryItem, first)
end

local function addOptions(menu, options, player, wire)
    for _, entry in ipairs(options) do
        local object = entry.wire or wire
        local option
        if entry.children then
            option = menu:addOption(entry[1], nil, nil)
            local child = ISContextMenu:getNew(menu)
            menu:addSubMenu(option, child)
            addOptions(child, entry.children, player, object)
        else
            option = menu:addOption(entry[1], player, entry[2], unpack(entry, 3))
        end
        if option and object then
            option.onHighlight = highlightWire
            option.onHighlightParams = { object }
        end
    end
end

local function onFillMenu(playerNum, context, worldObjects, test)
    if test then return end
    local placement = ZedComm and ZedComm.PlayerPlacement
    local registry = placement and placement.getRegistry()
    local square = clickedSquare(worldObjects)
    local player = getSpecificPlayer(playerNum)
    if not registry or not square or not player then return end
    local network = registry.network
    local run = runs[player]
    local anchor = run and reachableAnchor(player, run)
    if run and not anchor then
        stopRun(player)
        run = nil
    end
    -- Saved IDs keep exact wire options in the same order on reload.
    local targets = orderedPieces(placement, registry, square)
    local wireCount = 0
    for _, entry in ipairs(targets) do
        if entry.piece.kind == "cable" then wireCount = wireCount + 1 end
    end
    local inventory = player:getInventory()
    local items = inventory:getItems()
    local options = {}
    local fixtureActions, fixtureMenuNames = {}, {}
    local wire
    local function addTo(list, label, callback, ...)
        list[#list + 1] = { label, callback, ... }
    end
    local function action(label, command, list)
        command.network, command.square = network, square
        addTo(list or options, label, queue, command)
    end
    local function fixtureMenu(label)
        local title, suffix = label, 2
        while fixtureMenuNames[title] do
            title = label .. " (" .. suffix .. ")"
            suffix = suffix + 1
        end
        fixtureMenuNames[title] = true
        local children = {}
        options[#options + 1] = { title, children = children }
        return children
    end

    local counts, placements = {}, {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local spec = placement.getSpec(item:getFullType())
        if spec and spec.kind == "cable" and not wire then wire = item end
        if spec and spec.kind == "endpoint" then
            local count = (counts[spec.itemType] or 0) + 1
            counts[spec.itemType] = count
            local label = "Place " .. spec.name
            if count > 1 then label = label .. " (" .. count .. ")" end
            local mounts = spec.definitionId == ZedComm.NetworkSwitch.ID and ZedComm.NetworkSwitch.mounts(square)
            if mounts and #mounts > 1 then
                local walls = {}
                placements[#placements + 1] = { label, children = walls }
                for _, mount in ipairs(mounts) do
                    action("Mount on " .. mount .. " wall", { kind = "place", item = item, mount = mount }, walls)
                end
            else
                action(label, { kind = "place", item = item }, placements)
            end
        end
    end
    if #placements == 1 then
        options[#options + 1] = placements[1]
    elseif #placements > 1 then
        options[#options + 1] = { "Place device", children = placements }
    end

    if run then
        addTo(options, "Pause wire run", cancelRun)
        if wire and placement.canLay(anchor, run.port, square) then
            local label = "Lay wire here"
            if wireCount > 0 then label = "Lay another wire here (" .. wireCount .. " present)" end
            action(label, { kind = "lay", item = wire, anchorId = run.id, anchorPort = run.port, run = run })
        end
    end

    local adapter = inventory:getFirstType(ZedComm.InternalCircuit.ADVANCED_ADAPTER_ITEM)
    local wireNumber = 0
    for _, entry in ipairs(targets) do
        local name = fixtureLabel(entry)
        local group, groupedWire
        if entry.piece.kind == "cable" then
            wireNumber = wireNumber + 1
            if wireCount > 1 then
                local number = wireNumber .. " of " .. wireCount
                name = "wire " .. number
                group = {}
                groupedWire = true
                options[#options + 1] = { "Wire " .. number, children = group, wire = entry.object }
            end
            addTo(group or options, group and "Inspect" or "Inspect wire", wireDetails, registry, entry.id, name)
            if registry:getRunName(entry.id) then
                addTo(group or options, "Rename run", renameRun, registry, entry)
            end
        else
            local label = entry.spec.fixtureType
            group = fixtureMenu(fixtureLabel(entry, label))
            fixtureActions[entry.object] = group
            if not entry.piece.definitionUnavailable then
                local rename = "Rename " .. label
                addTo(group, rename, renameFixture, registry, entry, rename)
            end
        end
        local actions = group or options
        local function addDevice(label, callback, ...)
            addTo(actions, label, callback, ...)
        end
        local ports = placement.freePorts(entry)
        for _, port in ipairs(ports) do
            local label = name
            if port and (#ports > 1 or port ~= "signal") then label = label .. " (" .. portLabel(entry, port) .. ")" end
            addDevice(groupedWire and "Select free end" or "Select " .. label .. " free end",
                selectEnd, network, entry, port, label)
            if run and placement.canJoin(network, anchor, run.port, entry, port) then
                action(groupedWire and "Connect selected run" or "Connect wire to " .. label, {
                    kind = "join", targetId = entry.id, object = entry.object, port = port,
                    anchorId = run.id, anchorPort = run.port, run = run,
                }, group)
            end
        end
        if entry.piece.definitionId == "ZedComm.NumericDisplay" then
            addDevice("Read numeric display", readDisplay, entry.object)
        elseif entry.piece.definitionId == "ZedComm.AdvancedDisplay" then
            addDevice("Read full signal", readDisplay, entry.object)
        elseif entry.spec.itemType == "ZedComm.PressurePlate" and ZedComm.DeviceRuntime then
            local value = ZedComm.DeviceRuntime.getPressureOutput(entry.piece)
            addDevice("Set pressure plate output (" .. value .. ")", configurePressurePlate, registry, entry)
        elseif entry.piece.definitionId == ZedComm.NetworkSwitch.ID then
            local on = not (entry.piece.state and entry.piece.state.on)
            action(on and "Turn network switch on" or "Turn network switch off", {
                kind = "set-network-switch", targetId = entry.id, object = entry.object, on = on,
            }, group)
        end
        if ZedComm.AdapterEditor then ZedComm.AdapterEditor.addOptions(addDevice, registry, entry) end
        if entry.piece.board then
            if entry.piece.definitionId == ZedComm.InternalCircuit.CABINET_ID and entry.spec.adapter == "basic" and adapter then
                action("Upgrade cabinet with Advanced Adapter", {
                    kind = "upgrade-cabinet", targetId = entry.id, object = entry.object, item = adapter,
                }, group)
            end
            local ports, labels = {}, {}
            for port in pairs(entry.piece.ports) do ports[#ports + 1] = port end
            table.sort(ports)
            local editor = ZedComm.AdapterEditor
            local cabinet = entry.piece.definitionId == ZedComm.InternalCircuit.CABINET_ID
            if editor then group[#group + 1] = { cabinet and "Label cabinet jack" or "Label door jack", children = labels } end
            for _, port in ipairs(ports) do
                local label, cable = portLabel(entry, port), entry.piece.ports[port]
                if editor then addTo(labels, label, editor.renameJack, registry, entry, port) end
                if cable then
                    action((cabinet and "Disconnect cabinet jack (" or "Disconnect door jack (") .. label .. ")", {
                        kind = "disconnect-port", targetId = entry.id, object = entry.object,
                        port = port, cableId = cable,
                    }, group)
                end
            end
        end
        if entry.spec.nativePickup then
            if entry.piece.definitionId == ZedComm.InternalCircuit.DOOR_ID then
                action("Remove door adapters", { kind = "remove-door-adapters", targetId = entry.id, object = entry.object }, group)
            elseif entry.piece.ports.signal then
                action("Disconnect relay wire", { kind = "disconnect-relay", targetId = entry.id, object = entry.object }, group)
            end
        else
            action(groupedWire and "Pick up" or "Pick up " .. name,
                { kind = "pickup", targetId = entry.id, object = entry.object }, group)
        end
    end

    for _, door in ipairs(placement.doorCandidates(square)) do
        local group = fixtureMenu("Door")
        for _, tier in ipairs({ "basic", "advanced" }) do
            if ZedComm.DoorInstallation.materials(player, tier) then
                action(tier == "basic" and "Install two Basic Adapters" or "Install two Advanced Adapters",
                    { kind = "install-door", object = door, tier = tier }, group)
            end
        end
    end

    for _, lamp in ipairs(placement.relayCandidates(square)) do
        local group = fixtureMenu("Lamp")
        action("Install test relay", { kind = "install-relay", object = lamp }, group)
        if adapter then
            action("Install Advanced Adapter", { kind = "install-advanced-adapter", object = lamp, item = adapter }, group)
        end
    end
    if getDebug() and ZedComm.DebugCircuits then
        options[#options + 1] = { "Debug", children = ZedComm.DebugCircuits.optionsAt(registry, square, fixtureActions) }
    end
    if #options == 0 then return end
    local root = context:addOption("ZedComm", nil, nil)
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(root, submenu)
    addOptions(submenu, options, player)
end

Events.SetDragItem.Add(function(nextCursor, playerNum)
    local cell = getCell()
    local current = cell and cell:getDrag(playerNum)
    if current and current ~= nextCursor then Native.previewPickup(current) end
    local player = getSpecificPlayer(playerNum)
    local run = player and runs[player]
    if run and run.native and nextCursor ~= run.cursor then Cursor.deactivate(run.cursor) end
end)
Events.OnFillWorldObjectContextMenu.Add(onFillMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryMenu)
Events.OnObjectLeftMouseButtonDown.Add(function(object)
    local previous = lastCabinetClick
    lastCabinetClick = nil
    if not object or not object:hasModData() then return end
    local tag = object:getModData().zedcomm
    if type(tag) ~= "table" then return end
    local cabinet = tag.definitionId == ZedComm.InternalCircuit.CABINET_ID
    if not cabinet and tag.definitionId ~= ZedComm.NetworkSwitch.ID then return end
    local player, cell = getSpecificPlayer(0), getCell()
    if not player or not cell or cell:getDrag(0) or player:isDead() or player:isAiming()
        or player:isIgnoreContextKey() or player:isClimbingLadder() or player:isClimbingDownLadder() then return end
    local speed = UIManager.getSpeedControls()
    if speed and speed:getCurrentGameSpeed() == 0 then return end
    local placement = ZedComm.PlayerPlacement
    local registry = placement.getRegistry()
    local entry = registry and placement.resolve(registry, tag.id)
    if not entry or entry.object ~= object then return end
    if cabinet then
        local editor = ZedComm.AdapterEditor
        if not editor or not placement.canView(player, entry.square) then return end
        local now = getTimestampMs()
        if previous and previous.object == object and previous.registry == registry
            and now > previous.time and now - previous.time <= cabinetDoubleClickMs then
            editor.open(player, registry, entry)
        else
            lastCabinetClick = { object = object, registry = registry, time = now }
        end
    elseif placement.canReach(player, entry.square) then
        queue(player, { kind = "toggle-network-switch", targetId = entry.id, object = object,
            square = entry.square, network = registry.network })
    end
end)
Events.OnTick.Add(function()
    for player, run in pairs(runs) do
        if run.item and not carries(player, run.item) then
            stopRun(player)
        elseif run.id and (not resolveAnchor(run)
            or (not run.item and not actionQueued(player, run.walk) and not reachableAnchor(player, run))) then
            stopRun(player)
        end
    end
end)
