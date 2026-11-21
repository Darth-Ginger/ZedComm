---
project: zedcomm
created_date: "Saturday, November 21st 2026, 5:25:51 pm"
last_update: "Saturday, November 21st 2026, 5:25:51 pm"
adr-status: accepted
adr_domain: Architecture
adr_number: 310
aliases: []
authors:
  - Codex
deciders:
  - Darth-Ginger
decision_topic: "Define Circuit Board Signal Boundaries"
decision_date: 2026-11-21
fileClass: adr
related-adr:
related-cards:
tags:
  - zedcomm
  - architecture
  - signals
  - circuit-boards
---

# ADR-310: Define Circuit Board Signal Boundaries

## Context

Simple circuits need predictable on/off behavior. Weight and other readings also need a way through a board at their original precision. ADR-309 defines packets on the wire. The board needs its own rules for processing them.

## Decision

An adapter provides a fixture's network connection. Modules installed in a board perform the logic. A door board can also drive local actuator outputs. An external splitter forwards one input to separate output jacks, each feeding its own wire run.

- Boolean gates and thresholds emit Basic 0 or 255 when their inputs are available. A direct input-to-output link also normalizes its input to 0 or 255.
- Cache forwards the current data packet while enabled, or continuously in Always mode. It retains no sample after its data disappears.
- Arithmetic defaults to bytes. In Full Reading mode, supported operators can use typed weight operands and emit a typed weight result with a byte fallback. Multiplication uses a Basic factor.
- A Basic cabinet reduces incoming packets to their Basic representation. A Basic output publishes a byte where a valid byte or fallback exists. An Advanced output on an Advanced cabinet can preserve the packet it receives. An Advanced receiver treats a Basic byte as a byte, with no inferred measurement or unit.

## Consequences

### Positive

- Simple automation uses the same on/off values across boards.
- Players can forward a reading or do arithmetic on it where they need the original precision.

### Negative

- Full readings require a compatible path from sender through any board to receiver. Players must choose Cache or a compatible arithmetic module when the full value matters.

## Related

```dataview
TABLE
    file.folder AS "Folder",
    adr-status AS "Status",
    adr_domain AS "Domain",
    decision_topic AS "Topic",
    last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
