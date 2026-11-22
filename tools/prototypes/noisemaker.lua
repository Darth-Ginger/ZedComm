-- Debugger probe for an existing vanilla Noisemaker in singleplayer.
-- The observer explicitly confirms native playback has ended before a start.
local probe = {}

local function loadedTrap(trap)
    if not trap or not instanceof(trap, "IsoTrap") or trap:getObjectIndex() < 0 then return false end
    local item, square = trap:getItem(), trap:getSquare()
    return item and item:getFullType() == "Base.NoiseTrap" and square
        and getCell():getGridSquare(square:getX(), square:getY(), square:getZ()) == square
end

function probe.attach(trap)
    if not loadedTrap(trap) then return nil, "Select a loaded Base.NoiseTrap." end
    local session = { starts = 0 }
    local function observe(object)
        if object == trap then
            session.starts = session.starts + 1
            print("[Noisemaker probe] native start " .. session.starts .. " at world hour "
                .. getGameTime():getWorldAgeHours())
        end
    end
    Events.OnThrowableExplode.Add(observe)

    function session:sample(signal, confirmedIdle)
        if not loadedTrap(trap) then self:close() return false end
        if type(signal) ~= "number" or signal <= 0 or confirmedIdle ~= true then return false end
        trap:triggerExplosion()
        return true
    end

    function session:close()
        if trap then Events.OnThrowableExplode.Remove(observe) end
        trap = nil
    end
    return session
end

return probe
