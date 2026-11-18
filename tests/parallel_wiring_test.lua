local testState = dofile("tests/support/menu_harness.lua")()
local LUA = testState.LUA
local check = testState.check
local square = testState.square
local save = testState.save
local start = testState.start
local loaded = testState.loaded
local placement = testState.placement
local carried = testState.carried
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local placedReading = testState.placedReading
local join = testState.join
local menu = testState.menu
local menuAt = testState.menuAt
local optionsAt = testState.optionsAt

dofile(testState.LUA .. "client/ZedComm/WireVisuals.lua")

-- Two player-built circuits share a square and stay independently selectable.
do
    testState.registry, testState.java = start()
    local center = floorTile(70, 70)
    local west, east = floorTile(69, 70), floorTile(71, 70)
    local north, south = floorTile(70, 69), floorTile(70, 71)

    local function placeDevice(tile, itemType)
        local ok, id = runPlacement(tile, { kind = "place", item = give(itemType) })
        assert(ok, id)
        return id
    end
    local westId = placeDevice(west, "ZedComm.PressurePlate")
    local eastId = placeDevice(east, "ZedComm.NumericDisplay")
    local northId = placeDevice(north, "ZedComm.PressurePlate")
    local southId = placeDevice(south, "ZedComm.NumericDisplay")
    give("ZedComm.SignalWire")
    give("ZedComm.SignalWire")

    local function choose(tile, label, group)
        local options = optionsAt(tile, group)
        assert(options[label], "missing option: " .. label)
        testState.queued = nil
        options[label]()
        if testState.queued then
            assert(testState.queued:isValid())
            assert(testState.queued:complete())
        end
    end

    choose(west, "Select pressure plate free end")
    choose(center, "Lay wire here")
    local wireA = testState.registry.network.pieces[westId].ports.signal
    choose(north, "Select pressure plate free end")
    local units = #carried
    choose(center, "Lay another wire here (1 present)")
    local wireB = testState.registry.network.pieces[northId].ports.signal
    check(wireA ~= wireB and #carried == units - 1 and #placement.piecesAt(testState.registry, center) == 2,
        "laying a second wire on the tile creates one distinct segment and consumes one unit")
    check(testState.registry.network:networkOf(wireA) ~= testState.registry.network:networkOf(wireB),
        "two wires on one tile do not join their networks")

    local nameA, nameB = "Wire 1 of 2", "Wire 2 of 2"
    if wireB < wireA then nameA, nameB = nameB, nameA end
    local menu = menuAt(center)
    local first, second = menu.children[nameA].options, menu.children[nameB].options
    check(first["Select free end"] and second["Select free end"]
        and first["Pick up"] and second["Pick up"] and first["Inspect"] and second["Inspect"],
        "both shared wires expose actions in their own submenus")
    check(not menu.options["Select free end"] and not menu.options["Pick up"]
        and not menu.options["Pick up wire 1 of 2"] and not menu.options["Inspect wire 2 of 2"],
        "shared wire actions do not clutter the ZedComm parent menu")
    local objectA = placement.resolve(testState.registry, wireA).object
    local objectB = placement.resolve(testState.registry, wireB).object
    local childA, childB = menu.children[nameA], menu.children[nameB]
    local function hover(context, label, enabled)
        local option = context.entries[label]
        option:onHighlight(context, enabled, unpack(option.onHighlightParams))
    end
    local previousColor = ColorInfo.new()
    previousColor:setABGR(0xFF123456)
    objectA:setOutlineHighlightCol(0, previousColor)
    hover(menu, nameA, true)
    check(objectA:isOutlineHighlight(0) and objectA:getOutlineHighlightCol(0) == 0xFFFFFF26
        and not objectB:isOutlineHighlight(0), "hovering a wire branch gives only that wire a cyan outline")
    hover(childA, "Select free end", true)
    hover(menu, nameA, false)
    check(objectA:isOutlineHighlight(0) and not objectB:isOutlineHighlight(0),
        "moving into a wire action keeps its sprite outlined")
    hover(menu, nameB, true)
    hover(childA, "Select free end", false)
    check(not objectA:isOutlineHighlight(0) and objectB:isOutlineHighlight(0)
        and objectA:getOutlineHighlightCol(0) == 0xFF123456,
        "switching wires restores the first sprite even when its old action leaves late")
    hover(childB, "Inspect", true)
    hover(childB, "Inspect", false)
    check(objectB:isOutlineHighlight(0), "leaving the child retains the parent wire outline")
    hover(menu, nameB, false)
    check(not objectB:isOutlineHighlight(0) and objectB:getOutlineHighlightCol(0) == -1,
        "closing the menu clears the outline and restores its original color")
    objectB:setOutlineHighlight(0, true)
    hover(menu, nameB, true)
    hover(menu, nameB, false)
    check(objectB:isOutlineHighlight(0) and objectB:getOutlineHighlightCol(0) == -1,
        "closing the menu preserves a pre-existing outline")
    objectB:setOutlineHighlight(0, false)

    choose(center, "Select free end", nameA)
    choose(east, "Connect wire to numeric display")
    choose(south, "Select numeric display free end")
    choose(center, "Connect selected run", nameB)
    check(testState.registry.network.pieces[eastId].ports.signal == wireA
        and testState.registry.network.pieces[southId].ports.signal == wireB,
        "menu selection and joining both target the intended wire ID")

    local spoken
    function player.Say(_, message) spoken = message end
    do
        local oldBox, oldLoader = ISTextBox, package.preload["ISUI/ISTextBox"]
        local modal, confirmed, initial, input
        package.preload["ISUI/ISTextBox"] = function()
            ISTextBox = {
                new = function(_, _, _, _, _, _, default, owner, confirm)
                    initial = default
                    confirmed = function() confirm(owner, { internal = "OK" }) end
                    modal = {
                        entry = { getText = function() return input end },
                        initialise = function() end,
                        addToUIManager = function() end,
                    }
                    return modal
                end,
            }
        end
        input = "  West loop  "
        choose(center, "Rename run", nameA)
        assert(initial == "")
        confirmed()
        check(testState.registry:getRunName(wireA) == "Run 1 (West loop)"
            and testState.registry:getRunName(wireB) == "Run 2", "renaming a wire changes only its connected run")
        input = "77"
        choose(west, "Set pressure plate output (1)")
        confirmed()
        check(initial == "1" and optionsAt(west)["Set pressure plate output (77)"]
            and optionsAt(north)["Set pressure plate output (1)"],
            "the context menu edits only the chosen pressure plate and shows its current output")
        ISTextBox, package.preload["ISUI/ISTextBox"] = oldBox, oldLoader
        package.loaded["ISUI/ISTextBox"] = nil
    end
    choose(center, "Inspect", nameA)
    check(string.find(spoken, "east device port", 1, true) and string.find(spoken, "west device port", 1, true),
        "wire inspection distinguishes the east-west route")
    choose(center, "Inspect", nameB)
    check(string.find(spoken, "north device port", 1, true) and string.find(spoken, "south device port", 1, true),
        "wire inspection distinguishes the north-south route")

    west.actors, north.actors = { { class = "IsoPlayer" } }, {}
    check(placedReading(eastId) == 77 and placedReading(southId) == 0,
        "first source drives only its own circuit across the shared tile")
    west.actors, north.actors = {}, { { class = "IsoPlayer" } }
    check(placedReading(eastId) == 0 and placedReading(southId) == 1,
        "second source drives only its own circuit across the shared tile")

    testState.registry, testState.java = start(save(testState.java))
    center.objects[1], center.objects[2] = center.objects[2], center.objects[1]
    check(#placement.piecesAt(testState.registry, center) == 2 and placedReading(southId) == 1,
        "both wire IDs, links, and isolated signals survive registry reload")
    choose(center, "Inspect", nameA)
    check(string.find(spoken, "west device port", 1, true) and string.find(spoken, "Run 1 (West loop)", 1, true),
        "wire numbering and the custom name survive reload and tile object reordering")
    units = #carried
    choose(center, "Pick up", nameA)
    check(not testState.registry.network.pieces[wireA] and testState.registry.network.pieces[wireB]
        and #placement.piecesAt(testState.registry, center) == 1 and #carried == units + 1,
        "numbered pickup removes only the selected wire and recovers one unit")
    local value, _, attached = placedReading(eastId)
    check(value == nil and not attached and placedReading(southId) == 1,
        "removing one wire leaves the other shared-tile circuit working")
end

testState.finish()
