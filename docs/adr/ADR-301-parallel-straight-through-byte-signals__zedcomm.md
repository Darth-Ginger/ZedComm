---
project: zedcomm
created_date: "Saturday, October 24th 2026, 10:47:46 pm"
last_update: "Thursday, November 12th 2026, 2:18:49 pm"
adr-status: superseded
adr_domain: Architecture
adr_number: 301
aliases: []
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_topic: "Use Parallel Straight Through Byte Signals"
decision_date: 2026-10-24
fileClass: adr
related-adr:
related-cards:
tags:
  - zedcomm
  - architecture
---

# ADR-301: Use Parallel Straight Through Byte Signals

> Superseded by ADR-309.

## Context

Earlier exploration considered serial packets, framing and eight-conductor cables. The selected MVP needs persistent on/off sensing and a simple route to mixed values without a serial protocol.

Source: Design discussion. Darth-Ginger approved this record with the infrastructure-device clarification during the decision review. Implementation and validation have not yet occurred.

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

- Design and MVP
- Decision index

```dataview
TABLE file.folder AS "Folder", adr-status AS "Status", adr_domain AS "Domain", decision_topic AS "Topic", last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
