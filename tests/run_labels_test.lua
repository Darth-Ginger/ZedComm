local testState = dofile("tests/support/placement_harness.lua")()
local check = testState.check
local worldObject = testState.worldObject
local save = testState.save
local fire = testState.fire
local start = testState.start
local floorTile = testState.floorTile


-- Labels keep a saved anchor through topology changes and allocate numbers per save.
do
    local registry, java = start()
    local function cable(x, id)
        fire("OnObjectAdded", worldObject(floorTile(x, 120), { id = id, kind = "cable" }))
    end
    cable(101, "b")
    cable(102, "c")
    cable(103, "d")
    cable(104, "e")
    check(registry:getRunName("b") == nil, "unlinked cable has no run name")
    assert(registry:link("b", "c"))
    assert(registry:link("d", "e"))
    check(registry:getRunName("b") == "Run 1" and registry:getRunName("e") == "Run 2",
        "connected runs receive sequential names")
    check(not registry:renameRun("b", "Bad\nname"), "a run name must be a single line")
    assert(registry:renameRun("d", "Tail"))
    assert(registry:link("c", "d"))
    check(registry:getRunName("b") == "Run 2 (Tail)", "a custom name survives a merge with a default name")
    cable(100, "a")
    assert(registry:link("a", "b"))
    check(registry:getRunName("a") == "Run 2 (Tail)", "extension keeps the run name across an electrical network ID change")
    assert(registry:unlink("c", "d"))
    check(registry:getRunName("c") == "Run 3" and registry:getRunName("e") == "Run 2 (Tail)",
        "after a split the saved anchor keeps its name and the other run gets the next number")
    cable(105, "f")
    assert(registry:link("e", "f"))
    assert(registry:removePiece("d"))
    registry = start(save(java))
    check(registry:getRunName("f") == "Run 2 (Tail)" and registry:getRunName("a") == "Run 3",
        "removing the name anchor preserves the name on a surviving run across reload")
    assert(registry:renameRun("f", "   "))
    check(registry:getRunName("e") == "Run 2", "a blank custom name restores the numbered default")
end

testState.finish()
