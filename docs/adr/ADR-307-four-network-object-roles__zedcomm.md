---
adr-status: accepted
authors:
  - Claude
  - Darth-Ginger
deciders:
  - Darth-Ginger
decision_date: 2026-11-06
---

# ADR-307: Four Network Object Roles

## Context

ADR-302 separates the communications framework from endpoint behaviour and says infrastructure devices such as switches, hubs and routers have a different simulation role from endpoints. It does not name the full set of roles a ZedComm object can take. With cable runs settled as chains that never branch (ADR-306), every piece of future topology beyond a single run depends on that missing role, so the set needs to be fixed before more device types are designed.

## Decision

Every object in a ZedComm network takes exactly one of four roles:

1. **Source** - an endpoint that drives a byte onto its network, such as the pressure sensor.
2. **Receiver** - an endpoint that reads the byte and acts on it, such as the display.
3. **Cable** - carries the byte along one run, with no behaviour of its own (ADR-301, ADR-306).
4. **Infrastructure** - moves a signal from one network segment to another, such as a hub or switch.

Sources and receivers are endpoints: they own sensing, interaction and effects (ADR-302). Infrastructure is not an endpoint and is never modelled as one. Its purpose is forwarding between segments, so it belongs to the network simulation, not to device behaviour. It is expected to resemble routing in effect, though in practice it may be closer to joining or combining the signals of the segments it connects than to addressed packet routing. Its exact forwarding rules, and any latency it introduces (ADR-301), are left to a later decision.

The MVP ships only sources, receivers and cables. Infrastructure is named here so the model keeps room for it; it is not built.

## Consequences

### Positive

- One vocabulary for designing every future device: each new object is placed in a role first.
- Forwarding logic has one owner, the network simulation, instead of spreading into endpoints or cables.
- Branching and multi-segment networks (ADR-306) have a defined place to grow.

### Negative

- The network model will need segments joined by infrastructure on top of today's single-run networks, a real extension rather than a new device type.
- Devices that both sense and forward would have to be split into an endpoint and an infrastructure part, or this decision revisited.

## Related

- [ADR-301](ADR-301-parallel-straight-through-byte-signals__zedcomm.md)
- [ADR-302](ADR-302-separate-framework-endpoint-behavior__zedcomm.md)
- [ADR-306](ADR-306-cable-runs-as-chains__zedcomm.md)
