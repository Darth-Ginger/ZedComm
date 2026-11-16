-- Add ZedComm items to the singleplayer Moveable cursor's existing lists.
if isClient() or isServer() then return end

local installedClass

local function propsFor(sprite, name, detail)
    if not sprite then return nil end
    local props = ISMoveableSpriteProps.new(sprite)
    function props:getInfoPanelDescription()
        local lines = ISMoveableSpriteProps.addLineToInfoTable({}, name, 255, 255, 255)
        if detail then ISMoveableSpriteProps.addLineToInfoTable(lines, detail, 255, 255, 255) end
        return lines
    end
    return props
end

local function inventoryKey(item, spec)
    local data = spec.kind == "endpoint" and item:getModData().zedcommPlacement
    if data then return spec.itemType .. ":" .. tostring(item:getID()) end
    return spec.itemType
end

local function addCandidate(cursor, objects, item, spec, key, detail)
    local props = propsFor(getSprite(spec.sprite), item:getName(), detail)
    if not props then return end
    objects[#objects + 1] = { object = item, moveProps = props, zedcommKey = key }
    if cursor.zedcommKey == key then cursor.objectIndex = #objects end
end

local function addInventoryItems(cursor, objects, placement, actions)
    local items = cursor.character:getInventory():getItems()
    local seen = {}
    local wireType = placement.WIRE_TYPE
    local runLabel = actions.activeWireLabel(cursor)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local spec = placement.getSpec(item:getFullType())
        if spec then
            local key = inventoryKey(item, spec)
            if not seen[key] then
                seen[key] = true
                local detail = key == wireType and runLabel
                if spec.definitionId == ZedComm.NetworkSwitch.ID then detail = "Shift + Rotate Building changes wall" end
                addCandidate(cursor, objects, item, spec, key, detail)
            end
        end
    end
    local active = actions.activeWireItem(cursor)
    if active and not seen[wireType] then
        -- Keep the active end selectable so it can be joined with no spare wire.
        addCandidate(cursor, objects, active, placement.getSpec(wireType), wireType, runLabel)
    end
    return objects
end

local function addPlacedPieces(cursor, objects, placement, registry)
    local square = cursor.currentSquare
    if cursor:getMoveableMode() ~= "pickup" or not square then return objects end
    local pieces = placement.piecesAt(registry, square)
    table.sort(pieces, function(a, b) return a.id < b.id end)
    local wireCount, wireNumber = 0, 0
    for _, entry in ipairs(pieces) do
        if entry.piece.kind == "cable" then wireCount = wireCount + 1 end
    end
    for _, entry in ipairs(pieces) do
        if not entry.spec.nativePickup then
            local name = entry.object:getName()
            local detail
            if entry.piece.kind == "cable" then
                detail = registry:getRunName(entry.id) or "Loose wire"
                wireNumber = wireNumber + 1
                if wireCount > 1 then name = "Wire " .. wireNumber .. " of " .. wireCount end
            end
            local props = propsFor(entry.object:getSprite(), name, detail)
            if props and cursor:shouldAddObject(entry.object, props) then
                objects[#objects + 1] = { object = entry.object, moveProps = props, zedcommPickup = entry }
            end
        end
    end
    return objects
end

local function selectedAt(cursor, square)
    local mode = cursor:getMoveableMode()
    if not square or (mode ~= "place" and mode ~= "pickup") then return nil end
    local radial = getPlayerRadialMenu(cursor.player)
    if radial and radial:isReallyVisible() then return nil end

    if cursor.currentSquare ~= square then
        cursor.objectListCache = nil
        if mode == "pickup" then cursor.objectIndex = 1 end
    end
    cursor.currentSquare = square
    cursor.canSeeCurrentSquare = square:isCouldSee(cursor.player)
    local objects = cursor.objectListCache
    if not objects then
        objects = mode == "place" and cursor:getInventoryObjectList() or cursor:getObjectList()
        cursor.objectListCache = objects
    end
    if cursor.objectIndex < 1 or cursor.objectIndex > #objects then cursor.objectIndex = 1 end
    local selected = objects[cursor.objectIndex]
    if selected and (selected.zedcommKey or selected.zedcommPickup) then return selected end
end

local function cancelSelection(cursor, actions)
    cursor.zedcommKey = nil
    cursor.zedcommMount = nil
    actions.changeSelection(cursor)
end

local function install()
    local class = ISMoveableCursor
    local placement = ZedComm and ZedComm.PlayerPlacement
    local actions = ZedComm and ZedComm.NativePlacementActions
    if not class or class == installedClass or not ISMoveableSpriteProps or not placement or not actions then return end
    installedClass = class

    local inventoryList = class.getInventoryObjectList
    function class:getInventoryObjectList()
        local objects = inventoryList(self)
        if placement.getRegistry() then return addInventoryItems(self, objects, placement, actions) end
        return objects
    end

    local objectList = class.getObjectList
    function class:getObjectList()
        local objects = objectList(self)
        local registry = placement.getRegistry()
        if registry then return addPlacedPieces(self, objects, placement, registry) end
        return objects
    end

    local isValid = class.isValid
    function class:isValid(square)
        local selected = placement.getRegistry() and selectedAt(self, square)
        if not selected then
            actions.previewPickup(self)
            if square and self.zedcommKey then cancelSelection(self, actions) end
            return isValid(self, square)
        end
        if self.zedcommKey and self.zedcommKey ~= selected.zedcommKey then cancelSelection(self, actions) end
        self.zedcommKey = selected.zedcommKey

        local props = selected.moveProps
        local pickup = selected.zedcommPickup
        actions.previewPickup(self, pickup and pickup.piece.kind == "cable" and pickup.object or nil)
        if pickup then
            self.canCreate = actions.canPickUp(self, pickup, square)
            self.objectSprite = nil
            self.colorMod = class.normalColor
        else
            self.canCreate = actions.canPlace(self, selected.object, square)
            local name = placement.previewSprite(square, selected.object, self.zedcommMount)
            self.objectSprite = (name and getSprite(name)) or props.sprite
            self.colorMod = self.canCreate and class.normalColor or class.invalidColor
        end
        self.currentMoveProps, self.origMoveProps = props, props
        self.origSpriteName = props.spriteName
        self.cacheInvObjectSprite = nil
        self.yOffset, self.nSprite = 0, 1
        self.isWallLike = false
        self:setInfoPanel(square, selected.object, props)
        return true
    end

    local render = class.render
    function class:render(x, y, z, square)
        render(self, x, y, z, square)
        if square and self.zedcommKey and self:getMoveableMode() == "place" and not self.canCreate then
            actions.drawInvalidTile(self, x, y, z)
        end
    end

    local tryBuild = class.tryBuild
    function class:tryBuild(x, y, z)
        local square = getCell():getGridSquare(x, y, z)
        local selected = placement.getRegistry() and selectedAt(self, square)
        if not selected then return tryBuild(self, x, y, z) end
        if selected.zedcommPickup then
            actions.pickUp(self, selected.zedcommPickup, square)
        else
            actions.place(self, selected.object, square)
        end
    end

    local rotateKey = class.rotateKey
    function class:rotateKey(key, joypad)
        if not joypad and getCore():isKey(KeybindId.ROTATE_BUILDING, key)
            and (isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT)) then
            local selected = selectedAt(self, self.currentSquare)
            if selected and selected.zedcommKey and selected.object:getFullType() == ZedComm.NetworkSwitch.ID then
                local current = placement.switchMount(self.currentSquare, selected.object, self.zedcommMount)
                self.zedcommMount = ZedComm.NetworkSwitch.nextMount(self.currentSquare, current)
                return
            end
        end
        local index = self.objectIndex
        rotateKey(self, key, joypad)
        if self.objectIndex ~= index then cancelSelection(self, actions) end
    end

    local setMode = class.setMoveableMode
    function class:setMoveableMode(mode)
        if self:getMoveableMode() ~= mode then cancelSelection(self, actions) end
        return setMode(self, mode)
    end
end

-- Native server building scripts can load after the client mod at startup.
Events.OnGameStart.Add(install)

