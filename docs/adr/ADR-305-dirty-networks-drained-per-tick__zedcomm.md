---
adr-status: accepted
authors:
  - Claude
deciders:
  - Darth-Ginger
decision_date: 2026-10-29
---

# ADR-305: Mark Changed Networks, Update Them Once per Tick

## Context

The simulation needs one update mechanism before the shared entry point can be written. ADR-301 makes a signal a maintained byte with no clock or framing, and rules out simulated cable latency; ADR-303 makes a receiver fail OFF on disconnect and adopt the current value on reconnect. So the simulation only has to recompute a network when something about it changes, and deliver the new value in the same pass.

Options considered:

- **Recompute every tick.** One loop with a fixed order, so it is predictable and easy to carry to multiplayer later. Its cost grows with the size of every network on every tick, even when nothing changed. The PZ event docs warn that `OnTick` handlers cost frame time and garbage collection.
- **Recompute inside events.** No work while idle and immediate updates. But a handler that changes state can trigger more events, so updates can chain or repeat and their order depends on which event fired first; several changes in one frame each cause a full recompute. Some changes have no event at all: nothing fires when a zombie steps onto a square.
- **Events mark, the tick updates.** Events mark affected networks for the next simulation tick.

Pause behaviour was checked against the PZ event documentation (the B42 Lua events reference, page version 42.0.2, and the older PZwiki event pages, read on 2026-10-29): `OnTickEvenPaused` is "the same as OnTick, but triggered when the game is paused as well", and its tick count is "always zero while paused". `OnTick` therefore does not run while the game is paused.

## Decision

The simulation updates in one pass per game tick, driven by `Events.OnTick`, over a set of networks marked as needing an update.

1. **Events only mark.** Placing, removing or cutting a cable, connecting or disconnecting a port, picking up equipment, and a sensor reading changing add the affected network to the pending set. No recompute runs inside an event handler.
2. **Each tick drains the set.** The pass recomputes only the marked networks, each at most once, and then clears the set. A tick with nothing marked does no network work.
3. **Sensors are sampled in the pass.** Occupancy has no cheap event, so the tick reads each loaded sensor's square and marks its network only when the value actually changes (0 and 255 for the pressure sensor). The MVP samples every tick; sampling every N ticks is an optimisation to make only after measuring cost.
4. **Values arrive in the same pass.** A recomputed network delivers its byte to every connected receiver within the tick that processed it, with no per-segment delay (ADR-301).
5. **Pause freezes the simulation.** The pass runs on `OnTick`, not `OnTickEvenPaused`, so nothing changes while the game is paused and work resumes on the next tick after unpausing. Any change made while paused stays marked until then.
6. **Time acceleration needs nothing special.** Signals are maintained state, not timed pulses, so a faster game clock does not change their meaning; the per-tick sensor sample keeps up with faster-moving occupants. The pass does not assume a fixed tick rate.
7. **One entry point for both modes.** The per-tick pass is the shared simulation entry point (ADR-302). In singleplayer it runs from `OnTick` in the game process. In multiplayer it runs on the server's tick and sends results through the dispatch adapter; that path is validated after the MVP.

## Consequences

### Positive

- Idle networks cost nothing per tick beyond sampling loaded sensors.
- Ten changes to one network in one frame cost one recompute, in a fixed order, so results do not depend on event order.
- Event handlers stay small and cannot trigger chains of recomputes.
- A single per-tick pass is the natural point for multiplayer to send state from later.

### Negative

- A change made by an event shows up on the next tick rather than inside the event, one tick of delay that players should not notice.
- Sensor sampling is polling and costs a little every tick for every loaded sensor; it must stay allocation-free to avoid the garbage collection cost the docs warn about.
- The pending set is extra state to keep correct: anything that changes a network and forgets to mark it will not update until something else marks it.
- Sensors in unloaded chunks are not sampled; what they report is still an open question.

## Related

- [ADR-301](ADR-301-parallel-straight-through-byte-signals__zedcomm.md)
- [ADR-302](ADR-302-separate-framework-endpoint-behavior__zedcomm.md)
- [ADR-303](ADR-303-unacknowledged-state-fail-off__zedcomm.md)
