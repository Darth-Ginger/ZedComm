-- ZedComm shared simulation entry point (ADR-305, ADR-302).
--
-- Events only mark a network as needing an update; one pass per game tick
-- recomputes each marked network once and hands the result to a dispatch
-- adapter. The same pass runs in singleplayer and on a multiplayer server;
-- only the adapter differs. The network model and sensor sampling arrive with
-- later cards: until then the recompute step is a function they register.
--
-- Kahlua (Lua 5.1): no goto, no integer division, no io/os.

ZedComm = ZedComm or {}

local Simulation = {}

local pending = {}      -- network id -> true, waiting for the next pass
local recompute = nil   -- function(networkId) -> byte (0-255) or nil
local adapter = nil     -- { name = string, deliver = function(networkId, value) }

Simulation.passes = 0   -- passes run, for logs and tests
Simulation.processed = 0 -- networks recomputed, for logs and tests

function Simulation.setRecompute(fn) recompute = fn end
function Simulation.setAdapter(a) adapter = a end
function Simulation.getAdapter() return adapter end

-- Called by event handlers. Never recomputes here (ADR-305, step 1).
function Simulation.markDirty(networkId)
    if networkId ~= nil then pending[networkId] = true end
end

function Simulation.hasPending()
    -- PZ Kahlua does not reliably expose the standard Lua next global.
    for _ in pairs(pending) do return true end
    return false
end

-- The per-tick pass (ADR-305, step 2). Returns how many networks it updated.
-- A tick with nothing marked returns at once and allocates nothing. Marks made
-- while the pass runs land in the fresh set and wait for the next tick, so a
-- network is recomputed at most once per pass.
function Simulation.tick()
    Simulation.passes = Simulation.passes + 1
    if not Simulation.hasPending() then return 0 end

    local batch = pending
    pending = {}
    local count = 0
    for networkId in pairs(batch) do
        local value = nil
        if recompute then value = recompute(networkId) end
        if adapter then adapter.deliver(networkId, value) end
        count = count + 1
    end
    Simulation.processed = Simulation.processed + count
    return count
end

-- For tests only: forget all state.
function Simulation.reset()
    pending = {}
    recompute = nil
    adapter = nil
    Simulation.passes = 0
    Simulation.processed = 0
end

ZedComm.Simulation = Simulation
return Simulation
