return function()
    local testState = dofile("tests/support/menu_harness.lua")()
    if not testState.GAME then return testState end
    local player, fire, menu = testState.player, testState.fire, testState.menu
    require "BuildingObjects/ISBuildingObject"
    dofile(testState.PZ .. "/client/TimedActions/WalkToTimedAction.lua")
    local floorColor = { getR = function() return 0 end, getG = function() return 1 end,
        getB = function() return 0 end }
    renderIsoRect = function(x, y, z, radius, r, g, b, a, width)
        testState.preview = { x - 1, y - 1 }
        testState.invalidOutline = { x = x, y = y, z = z, radius = radius, r = r, g = g, b = b, a = a, width = width }
    end
    JoypadState = { players = {} }
    IsoSprite = { new = function()
        return { LoadSingleTexture = function() end, RenderGhostTileColor = function(_, x, y) testState.preview = { x, y } end }
    end }
    getCore = function() return {
        getGoodHighlitedColor = function() return floorColor end,
        getBadHighlitedColor = function() return floorColor end,
    } end

    local function click(tile)
        local x, y, z = tile:getX(), tile:getY(), tile:getZ()
        fire("OnDoTileBuilding2", testState.cursor, true, x, y, z, tile)
        player.buildReleased = true
        fire("OnDoTileBuilding2", testState.cursor, false, x, y, z, tile)
        player.buildReleased = false
    end

    local function finishWalk()
        local walking = testState.queuedWalk
        testState.queuedWalk = nil
        if walking then walking.onCompleteFunc() end
    end

    local function arrive()
        if testState.queuedWalk then player.tile = testState.queuedWalk.location end
        finishWalk()
        return testState.queued
    end

        ISInventoryPane = { getActualItems = function(items) return items end }
    ISContextMenu.get = function() testState.choice = menu(); return testState.choice end
    getMouseX, getMouseY = function() return 0 end, function() return 0 end

    testState.click, testState.arrive, testState.finishWalk = click, arrive, finishWalk
    return testState
end
