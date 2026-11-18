return function()
    local testState = dofile("tests/support/placement_harness.lua")()
    local player, inventory, fire, LUA = testState.player, testState.inventory, testState.fire, testState.LUA
    package.loaded["TimedActions/ISInventoryTransferUtil"] = true
    package.loaded["TimedActions/ISBaseTimedAction"] = true
    package.loaded["TimedActions/ISTimedActionQueue"] = true
    ISBaseTimedAction = {}
    function ISBaseTimedAction:derive()
        local class = {}
        class.__index = class
        return class
    end
    function ISBaseTimedAction.new(class, character)
        return setmetatable({ character = character }, class)
    end
    local testQueue = { indexOf = function(_, action)
        if action == testState.queuedWalk then return 1 end
        return action == testState.queued and 2 or -1
    end }
    ISTimedActionQueue = {
        add = function(action)
            if action.location then testState.queuedWalk = action else testState.queued = action end
        end,
        getTimedActionQueue = function() return testQueue end,
    }
    local function menu()
        return {
            player = 0,
            options = {},
            children = {},
            entries = {},
            isVisible = function(self) return self.visible ~= false end,
            addOption = function(self, label, object, callback, ...)
                local params = { ... }
                if callback then self.options[label] = function() return callback(object, unpack(params)) end end
                local entry = { label = label }
                self.entries[label] = entry
                return entry
            end,
            addSubMenu = function(self, option, submenu)
                self.children[option.label] = submenu
            end,
        }
    end
    ISContextMenu = { getNew = menu }
    dofile(LUA .. "client/ZedComm/PlacementMenu.lua")
    local function menuAt(tile)
        player.tile = tile
        getCell():setDrag(nil, 0)
        local contextMenu = menu()
        fire("OnFillWorldObjectContextMenu", 0, contextMenu, { { getSquare = function() return tile end } }, false)
        return contextMenu.children.ZedComm or menu()
    end
    local function optionsAt(tile, group)
        local root = menuAt(tile)
        if group then return assert(root.children[group], "missing submenu: " .. group).options end
        for _, child in pairs(root.children) do
            for label, callback in pairs(child.options) do root.options[label] = root.options[label] or callback end
        end
        return root.options
    end

    testState.menu = menu
    testState.menuAt = menuAt
    testState.optionsAt = optionsAt
    player.isDead = function() return false end
    player.isAiming, player.isIgnoreContextKey = player.isDead, player.isDead
    player.isClimbingLadder, player.isClimbingDownLadder = player.isDead, player.isDead
    return testState
end
