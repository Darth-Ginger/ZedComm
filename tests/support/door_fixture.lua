return function(worldObject)
    Perks = Perks or { Electricity = 1 }
    IsoDoor = {
        getDoubleDoorIndex = function(object) return object.doubleIndex or -1 end,
        getGarageDoorIndex = function(object) return object.garageIndex or -1 end,
    }
    return function(square, class)
        local door = worldObject(square)
        door.class, door.open, door.locked, door.keyed = class or "IsoDoor", false, false, false
        door.toggles, door.lockWrites = 0, 0
        function door.getOpenSprite() return door.openSprite end
        function door.isNorth() return door.north ~= false end
        function door.isDoor() return door.doorFlag ~= false end
        function door.isDestroyed() return door.destroyed == true end
        function door.isOpen() return door.open end
        function door.isLocked() return door.locked end
        function door.isLockedByKey() return door.keyed end
        function door.isBarricaded() return door.barricaded == true end
        function door.isObstructed() return door.obstructed == true end
        function door.isLockedByPadlock() return door.padlocked == true end
        function door.getLockedByCode() return door.code or 0 end
        function door.setIsLocked(_, value) door.locked = value; door.lockWrites = door.lockWrites + 1 end
        function door.setLockedByKey(_, value)
            door.keyed, door.locked = value, value
            door.lockWrites = door.lockWrites + 1
        end
        function door.ToggleDoorActual(_, player)
            assert(player, "native door toggle needs a character")
            door.toggles = door.toggles + 1
            if not door.rejectToggle then door.open = not door.open end
            if triggerEvent then triggerEvent("OnContainerUpdate") end
        end
        function door.ToggleDoorSilent()
            door.toggles = door.toggles + 1
            door.silentCloses = (door.silentCloses or 0) + 1
            if not door.rejectToggle then door.open = not door.open end
        end
        square.RecalcAllWithNeighbours = square.RecalcAllWithNeighbours or function() end
        square.setSquareChanged = square.setSquareChanged or function() end
        door.invalidateRenderChunkLevel = door.invalidateRenderChunkLevel or function() end
        return door
    end
end
