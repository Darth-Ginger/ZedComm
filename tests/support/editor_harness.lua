return function()
    local testState = dofile("tests/support/menu_harness.lua")()
    local start, menu, LUA = testState.start, testState.menu, testState.LUA
    local runPlacement, give, lay, join = testState.runPlacement, testState.give, testState.lay, testState.join
    testState.registry, testState.java = start()
    testState.mouseX, testState.mouseY = 0, 0
    getMouseX, getMouseY = function() return testState.mouseX end, function() return testState.mouseY end
    testState.rotateKey = 99 -- rebound from the default
    getDebug = function() return true end
    getCore = function()
        return {
            getScreenWidth = function() return 1200 end, getScreenHeight = function() return 800 end,
            isKey = function(_, binding, key) return binding == "rotate" and key == testState.rotateKey end,
            getKey = function(_, binding) if binding == "rotate" then return testState.rotateKey end end,
        }
    end
    ISPanel = {}
    function ISPanel:derive() return setmetatable({}, { __index = self }) end
    function ISPanel:new() return setmetatable({}, { __index = self }) end
    function ISPanel:initialise() end
    function ISPanel:addChild() end
    function ISPanel:addToUIManager() testState.panel = self; self:createChildren() end
    function ISPanel:removeFromUIManager() testState.panel = nil end
    function ISPanel:setVisible() end
    function ISPanel:setWantKeyEvents(value) self.wantKeyEvents = value end
    function ISPanel:setCapture(value) self.captured = value end
    function ISPanel:bringToTop() end
    function ISPanel:getMouseX() return testState.mouseX end
    function ISPanel:getMouseY() return testState.mouseY end
    function ISPanel:onMouseUpOutside() end
    function ISPanel:setStencilRect() end
    function ISPanel:clearStencilRect() end
    function ISPanel:drawText() end
    function ISPanel:drawTextCentre() end
    function ISPanel:drawRect() end
    function ISPanel:drawRectBorder() end
    function ISPanel:drawTextureScaled() end
    ISButton = { new = function(_, _, _, _, _, _, target, action)
        return { initialise = function() end, setEnable = function() end, click = function() action(target) end }
    end }
    ISTextBox = { new = function(_, _, _, _, _, _, _, _, action)
        local entry = { getText = function() return testState.input end }
        return { entry = entry, initialise = function() end, addToUIManager = function()
            testState.confirm = function()
                action(nil, { internal = "OK", parent = { entry = entry } })
            end
        end }
    end }
    package.loaded["ISUI/ISPanel"] = true
    package.loaded["ISUI/ISButton"] = true
    package.loaded["ISUI/ISContextMenu"] = true
    package.loaded["ISUI/ISTextBox"] = true
    ISContextMenu.get = function()
        testState.jackMenu = menu()
        return testState.jackMenu
    end
    getTexture = function() return {} end
    UIFont, ISMouseDrag = { Small = 1, Medium = 2 }, {}
    KeybindId, Keyboard = { ROTATE_BUILDING = "rotate" }, { getKeyName = tostring }
    dofile(LUA .. "client/ZedComm/AdapterEditor.lua")
    local function clickPalette(kind, group)
        assert(testState.panel:refresh())
        for i, entry in ipairs(testState.panel.paletteEntries) do
            if (kind and entry.kind == kind) or (group and entry.group == group) then
                testState.panel.paletteOffset = math.max(0, math.min(i - 1, #testState.panel.paletteEntries - 8))
                testState.panel:onMouseDown(testState.panel.carriedX + 30, 84 + (i - testState.panel.paletteOffset - 1) * 34)
                return
            end
        end
        error("Missing palette entry " .. tostring(kind or group))
    end
    local function dragCarried(kind) clickPalette(kind) end
    local function grabCarried() dragCarried("threshold") end
    local function click(x, y)
        testState.panel:onMouseDown(x, y)
        testState.panel:onMouseUp(x, y)
    end
    local function placeTestItem(tile, itemType)
        local ok, id = runPlacement(tile, { kind = "place", item = give(itemType) })
        assert(ok, id)
        return id
    end

    local function runTestWire(tile, source, from, targetTile, receiver, port)
        local ok, wire = lay(tile, give("ZedComm.SignalWire"), source, from)
        assert(ok and join(targetTile, wire, false, receiver, port))
        return wire
    end

    testState.clickPalette = clickPalette
    testState.dragCarried = dragCarried
    testState.grabCarried = grabCarried
    testState.click = click
    testState.placeTestItem = placeTestItem
    testState.runTestWire = runTestWire
    dofile(LUA .. "client/ZedComm/WireVisuals.lua")
    dofile(LUA .. "client/ZedComm/DisplayReadout.lua")
    return testState
end
