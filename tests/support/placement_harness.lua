return function()
    local testState = dofile("tests/support/pz_harness.lua")()
    local MEDIA, LUA = testState.MEDIA, testState.LUA
    local list, square, worldObject, takeOff = testState.list, testState.square, testState.worldObject, testState.takeOff
    local fire, start = testState.fire, testState.start
    instanceof = function(object, class)
        return object.class == class or (class == "IsoPlayer" and object.class == "IsoAnimal")
    end
    require "ZedComm/SimulationRunner"
    local runtime = ZedComm.DeviceRuntime
    testState.runtime, testState.simulation = runtime, ZedComm.Simulation
    require "ZedComm/PlayerPlacement"
    local placement = ZedComm.PlayerPlacement
    testState.worldTime = 1000
    getTimestampMs = function() return testState.worldTime end
    local registeredSprites = {}
    getSprite = function(name)
        local index = tonumber(string.match(name, "^zedcomm_devices_01_(%d+)$"))
        local displayIndex = tonumber(string.match(name, "^zedcomm_display_01_(%d+)$"))
        local switchIndex = tonumber(string.match(name, "^zedcomm_switch_01_(%d+)$"))
        local switchFloor = tonumber(string.match(name, "^zedcomm_switch_floor_01_(%d+)$"))
        local weightGlyph = tonumber(string.match(name, "^zedcomm_weight_face_01_(%d+)$"))
        if (index and index <= 474) or (displayIndex and displayIndex < 257) or (switchIndex and switchIndex < 40)
            or (switchFloor and switchFloor < 20) or (weightGlyph and weightGlyph < 62) then
            if not registeredSprites[name] then
                local floorOverlay = displayIndex ~= nil
                    or (index and ((index >= 20 and index <= 25) or (index >= 419 and index <= 431)))
                local properties = { has = function(_, flag) return floorOverlay and flag == IsoFlagType.FloorOverlay end }
                registeredSprites[name] = { getName = function() return name end, getProperties = function() return properties end }
            end
            return registeredSprites[name]
        end
    end
    triggerEvent = fire
    ColorInfo = {
        new = function() return { setABGR = function(self, packed) self.packed = packed end } end,
    }
    IsoObject = {
        new = function(tile, sprite)
            local object = worldObject(tile, nil)
            takeOff(tile, object)
            object.sprite = sprite
            function object.getSprite()
                local current = object.spriteInstance
                if current and current:getName() == object.sprite then return current end
                return getSprite(object.sprite)
            end
            function object.setSprite(_, sprite)
                object.sprite, object.spriteInstance = sprite:getName(), sprite
            end
            function object:invalidateRenderChunkLevel(flag) self.chunkDirty = flag end
            local attachments = {}
            function object.getAttachedAnimSprite() return #attachments > 0 and list(attachments) or nil end
            function object:addAttachedAnimSprite(sprite)
                attachments[#attachments + 1] = { getParentSprite = function() return sprite end }
            end
            function object:RemoveAttachedAnim(index) table.remove(attachments, index + 1) end
            object.outlineColors = {}
            object.outlined = {}
            function object.getOutlineHighlightCol(_, index) return object.outlineColors[index] or -1 end
            function object.setOutlineHighlightCol(_, index, r, g, b, a)
                if type(r) == "table" then
                    object.outlineColors[index] = assert(r.packed)
                else
                    object.outlineColors[index] = math.floor(r * 255) + math.floor(g * 255) * 256
                        + math.floor(b * 255) * 65536 + math.floor(a * 255) * 16777216
                end
            end
            function object.isOutlineHighlight(_, index) return object.outlined[index] == true end
            function object.setOutlineHighlight(_, index, enabled) object.outlined[index] = enabled end
            return object
        end,
    }

    local function floorTile(x, y)
        local tile = square(x, y, 0)
        function tile.TreatAsSolidFloor() return true end
        function tile.isSolid() return false end
        function tile.isSolidTrans() return false end
        function tile.isBlockedTo(_, other) return tile.blocked == other end
        function tile.getMovingObjects() return list(tile.actors or {}) end
        function tile.AddTileObject(_, object) tile.objects[#tile.objects + 1] = object end
        function tile.transmitRemoveItemFromSquare(_, object)
            if tile.refuseRemoval then return end
            fire("OnObjectAboutToBeRemoved", object)
            takeOff(tile, object)
        end
        return tile
    end

    local carried = {}
    local inventory = {}
    function inventory.getItems() return list(carried) end
    function inventory.getFirstType(_, fullType)
        for _, item in ipairs(carried) do
            if item:getFullType() == fullType then return item end
        end
    end
    function inventory.contains(_, item) return item.container == inventory end
    function inventory.hasRoomFor() return not inventory.full end
    function inventory.AddItem(_, item)
        carried[#carried + 1] = item
        item.container = inventory
        return item
    end
    function inventory.Remove(_, item)
        for i = #carried, 1, -1 do
            if carried[i] == item then
                table.remove(carried, i)
                item.container = nil
                return
            end
        end
    end
    local itemTags = {}
    do
        local file = assert(io.open(MEDIA .. "scripts/ZedComm_Items.txt", "r"))
        local script = file:read("*a")
        file:close()
        for name, block in script:gmatch("    item (%w+)%s*{([^}]+)}") do
            local tags = {}
            for tag in (block:match("Tags%s*=%s*([^,]+)") or ""):gmatch("[^;%s]+") do tags[tag] = true end
            itemTags["ZedComm." .. name] = tags
        end
    end

    instanceItem = function(itemType)
        local item = { data = {} }
        function item.getFullType() return itemType end
        function item.getName() return itemType end
        function item.getContainer() return item.container end
        function item.getModData() return item.data end
        function item:hasTag(tag) return itemTags[itemType] and itemTags[itemType][tag] == true end
        function item:getCurrentUsesFloat() return self.charge or 1 end
        function item:setUsedDelta(charge) self.charge = charge end
        return item
    end
    local player = { tile = nil }
    function player.getInventory() return inventory end
    function player.getPlayerNum() return 0 end
    function player.isBuildButtonDown() return false end
    function player.isBuildButtonReleased() return player.buildReleased == true end
    function player.getCurrentSquare() return player.tile end
    function player.isTimedActionInstant() return true end
    function player.Say() end
    getSpecificPlayer = function() return player end
    local function give(itemType) return inventory:AddItem(instanceItem(itemType)) end
    local function runPlacement(tile, command, from)
        command.square, command.network = tile, testState.registry.network
        player.tile = from or tile
        return placement.perform(player, command)
    end
    local function target(tile, id, kind, fields)
        local entry = assert(placement.resolve(testState.registry, id))
        local command = fields or {}
        command.kind, command.targetId, command.object = kind, id, entry.object
        return runPlacement(tile, command)
    end
    local function placedReading(id)
        fire("OnTick")
        return runtime.getDisplay(placement.resolve(testState.registry, id).object)
    end
    local function lay(tile, item, id, port)
        return runPlacement(tile, { kind = "lay", item = item, anchorId = id, anchorPort = port })
    end
    local function join(tile, first, firstPort, second, secondPort)
        return target(tile, second, "join", { anchorId = first, anchorPort = firstPort, port = secondPort })
    end
    local function floorFixture(tile, flags, container, height, class)
        local object = worldObject(tile, nil)
        local props = {
            has = function(_, key) return flags[key] ~= nil end,
            get = function(_, key) return flags[key] end,
        }
        function object.getProperties() return props end
        object.containers = {}
        if container then
            object.containers[1] = { getContentsWeight = function(self) return self.weight or 0 end }
        end
        function object.getContainerCount() return #object.containers end
        function object.getContainerByIndex(_, index) return object.containers[index + 1] end
        function object.getRenderYOffset() return height or 0 end
        object.class = class
        return object
    end

    local function droppedItem(weight)
        return { getItem = function()
            return { getUnequippedWeight = function() return weight end }
        end }
    end

    local function spriteOf(id) return placement.resolve(testState.registry, id).object.sprite end
    testState.definitions = ZedComm.DeviceDefinitions

    testState.placement = placement
    testState.inventory = inventory
    testState.carried = carried
    testState.player = player
    testState.give = give
    testState.floorTile = floorTile
    testState.runPlacement = runPlacement
    testState.target = target
    testState.placedReading = placedReading
    testState.lay = lay
    testState.join = join
    testState.floorFixture = floorFixture
    testState.droppedItem = droppedItem
    testState.spriteOf = spriteOf
    testState.registry, testState.java = start()
    return testState
end
