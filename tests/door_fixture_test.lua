local test = dofile("tests/support/pz_harness.lua")()
local makeDoor = dofile("tests/support/door_fixture.lua")(test.worldObject)
local Door, Modules = ZedComm.Door, ZedComm.SignalModules
local check = test.check
instanceof = function(object, class) return object.class == class end
getSpecificPlayer = function() return {} end
triggerEvent = test.fire

for _, class in ipairs({ "IsoDoor", "IsoThumpable" }) do
    local door = makeDoor(test.square(10, 10, 0), class)
    check(Door.isEligible(door), class .. " single door is eligible")
    local controller = Door.bindFixture(door)
    local lock = assert(Modules.newReceiver(Modules.ON_OFF, controller:adapter("lockAction")))
    local open = assert(Modules.newReceiver(Modules.ON_OFF, controller:adapter("openAction")))
    local function tick(l, o)
        if l == "detach" then lock:detach() else lock:receive(l) end
        if o == "detach" then open:detach() else open:receive(o) end
        controller:flush()
        lock:reconcile(); open:reconcile()
    end
    tick(0, 255)
    check(door.open and not door.locked, class .. " positive Open opens once")
    tick(0, 255)
    check(door.toggles == 1, class .. " held ON does not toggle repeatedly")
    tick(255, 255)
    check(door.open and not door.locked and lock.result == "unavailable", class .. " lock waits for open door")
    tick(255, 0)
    check(not door.open and door.locked and door.silentCloses == 1, class .. " network closure skips swing animation and applies pending lock")
    tick(255, 255)
    check(not door.open and open.result == "unavailable", class .. " lock blocks opener")
    door.open = true
    controller:flush()
    check(not door.open, class .. " native lock bypass is corrected")
    tick(nil, 255)
    check(door.open and not door.locked and not door.keyed, class .. " missing lock signal unlocks")
    tick(0, nil)
    check(not door.open, class .. " missing Open signal closes while connected")
    tick("detach", "detach")
    door.open = true
    controller:flush()
    check(door.open, class .. " unwired actuators return manual control")
    tick(0, 0)
    door.obstructed = true
    tick(0, 255)
    check(not door.open and open.result == "unavailable", class .. " obstruction defers opening")
    door.obstructed = false
    controller:flush(); open:reconcile()
    check(door.open and open.result == "applied", class .. " obstruction removal retries latest request")
    door.barricaded = true
    tick(0, 0)
    check(door.open, class .. " barricade prevents movement")
    door.barricaded = false
    tick(0, 0)
    door.rejectToggle = true
    tick(0, 255)
    check(open.result == "unavailable" and not door.open, class .. " native state is verified after toggle")
    door.rejectToggle = false
    lock:detach(); open:detach(); controller:release()
    door.locked, door.keyed = true, true
    tick(0, "detach")
    check(not door.locked, class .. " owned OFF unlocks preexisting lock")
    lock:detach(); open:detach(); controller:release()
    check(door.locked and door.keyed, class .. " removing adapter restores native lock flags")
    door.locked, door.keyed = true, false
    local nativeLock = Door.bindFixture(door, nil, { locked = true, keyed = false })
    nativeLock:adapter("lockAction"):apply(true)
    nativeLock:flush(); nativeLock:release()
    check(door.locked and not door.keyed, class .. " restoring a non-keyed native lock survives setter coupling")
    door.destroyed = true
    controller:flush()
    check(not Door.isEligible(door), class .. " destroyed door is ineligible")
end
local door = makeDoor(test.square(11, 10, 0), "IsoThumpable")
door.doorFlag = false
check(not Door.isEligible(door), "ordinary thumpable is not a door")
door.doorFlag, door.doubleIndex = true, 1
check(not Door.isEligible(door), "grouped double door is outside the single-panel contract")
door.doubleIndex, door.garageIndex = nil, 0
check(not Door.isEligible(door), "garage door is outside the single-panel contract")
test.finish()
