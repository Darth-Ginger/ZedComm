---
project: zedcomm
created_date: "Saturday, October 24th 2026, 10:47:52 pm"
last_update: "Saturday, November 21st 2026, 5:25:51 pm"
adr-status: accepted
adr_domain: Architecture
adr_number: 304
aliases: []
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_topic: "Retain Equipment Modules and Leave Cables on Relocation"
decision_date: 2026-10-24
fileClass: adr
related-adr: []
related-cards:
tags:
  - zedcomm
  - architecture
---

# ADR-304: Retain Equipment Modules and Leave Cables on Relocation

## Context

Players will eventually place devices and cabinets, install modules through context-menu actions and attach laid cable ends explicitly. Relocating equipment should preserve assembly work without requiring every cable to be relaid.

Source: Design discussion. Darth-Ginger approved this record during the decision review. Implementation and validation have not yet occurred.

## Decision

Connect cable ends explicitly to equipment ports. When equipment is picked up, retain its installed modules, their condition and configuration with the equipment; detach external connections and leave the cable runs placed and recoverable. Placing the equipment elsewhere requires reconnecting the affected ends. Permit future extension of existing runs by explicit coupler-style connections, rather than forcing replacement of a whole run. Picking up a housing and removing one module are separate operations. Cabinet/module/coupler implementation is future scope, not a condition for the first sensor-display prototype. Exact terminal ownership and cable-recovery granularity remain open.

Native Place, Move, and Pickup own equipment placement and relocation. The ZedComm context menu selects an existing free end and hands off to native Place with Signal Wire selected.

## Consequences

### Positive

- Preserves player investment in assembled equipment.
- Makes placed cabling reusable after relocation.
- Gives physical connections clear player-controlled meaning.

### Negative

- Requires preserving per-item module state when those features are implemented.
- Leaves disconnected cable ends that future UI must make identifiable.
- Couplers and module installation add later implementation work.

## Related

- Design and MVP
- Decision index

```dataview
TABLE file.folder AS "Folder", adr-status AS "Status", adr_domain AS "Domain", decision_topic AS "Topic", last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
