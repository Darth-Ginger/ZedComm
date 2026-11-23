---
adr-status: accepted
authors:
  - Codex
deciders:
  - Darth-Ginger
decision_date: 2026-11-21
---

# ADR-311: Define Networked Door Control

## Context

A wired door can control both access and movement. Separate inputs let players automate either function and combine them with circuit modules. Door hardware and normal game interactions still govern what the door can physically do.

## Decision

Fit two matched adapters to a supported native door. The shared board has fixed Lock and Open inputs and separate local actuator outputs. The Basic board has fixed direct paths. The Advanced board can run internal modules.

| Input | Valid ON | Valid OFF (0) | Connected, no signal | Physically detached |
| --- | --- | --- | --- | --- |
| Lock | Prevent new openings. Lock a closed door or wait for an open door to close. | Unlock. | Unlock. | Restore the native lock and keyed flags captured at installation. |
| Open | Open when network and native locks allow it. | Close when native obstruction and barricade checks allow it. | Release movement to native control at the current position. | Release movement to native control. |

Lock takes precedence over a request to open. Closing an already-open door requires an Open OFF request or a manual close. The retrofit respects independent native locks and physical obstructions.

The optional Door Contact is an independent sender. A closed door publishes 255, an open door publishes 0, and an unavailable host produces no signal. Players can fit the contact separately from the actuators.

## Consequences

### Positive

- Lock-only and movement-only circuits can coexist with native controls.
- A single door can report its state while other circuits control it.

### Negative

- Door bindings must distinguish zero, signal loss and detach for each action.
- A circuit that needs an already-open door to close before it locks must supply a separate close request.

## Related

- [ADR-303](ADR-303-unacknowledged-state-fail-off__zedcomm.md)
- [ADR-308](ADR-308-modify-existing-objects-in-place__zedcomm.md)
- [ADR-309](ADR-309-maintained-signal-packets__zedcomm.md)
- [ADR-310](ADR-310-board-signal-boundaries__zedcomm.md)
