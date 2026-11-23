---
adr-status: superseded
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_date: 2026-10-24
---

# ADR-301: Use Parallel Straight Through Byte Signals

> Superseded by [ADR-309](ADR-309-maintained-signal-packets__zedcomm.md).

## Context

Earlier exploration considered serial packets, framing and eight-conductor cables. The selected MVP needs persistent on/off sensing and a simple route to mixed values without a serial protocol.

## Decision

Represent the cable as eight simultaneous logical bit lanes forming an unsigned byte. Connect each lane straight through: bit n reaches bit n. Use 11111111 (255) for occupied pressure sensor and 00000000 (0) for clear. Mixed patterns are valid byte states. Straight-through wiring is the general design, not merely an MVP limitation: do not plan crossovers, remapping or lane-specific damage. Do not simulate distance-based cable latency. Any future latency simulation belongs to the network simulation and would likely be introduced through intermediary infrastructure devices such as switches, hubs or routers. Infrastructure devices have a different simulation role and must be distinct from the endpoint class. Infrastructure devices and latency simulation are outside the MVP; this decision does not specify their implementation or exact delay behavior. Internal packed-byte storage is compatible with this model; no per-bit object representation is mandated.

## Consequences

### Positive

- Preserves the intended bit-style behavior while keeping cable semantics simple.
- Supports on/off and numeric values through one maintained-state model.
- Avoids serial clocks, packet framing and distance-delay simulation for this slice.

### Negative

- Does not model serial communications or electrical waveforms.
- Eight lanes bound a single maintained value to 0–255; future wider values need a separate decision.

## Related

- [ADR-309](ADR-309-maintained-signal-packets__zedcomm.md)
