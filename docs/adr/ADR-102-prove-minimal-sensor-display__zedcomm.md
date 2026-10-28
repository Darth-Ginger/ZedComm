---
project: zedcomm
created_date: "Saturday, October 24th 2026, 10:47:44 pm"
last_update: "Saturday, October 24th 2026, 10:47:44 pm"
adr-status: accepted
adr_domain: General
adr_number: 102
aliases: []
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_topic: "Prove a Minimal Sensor to Display MVP"
decision_date: 2026-10-24
fileClass: adr
related-adr: []
related-cards:
tags:
  - zedcomm
  - scope
---

# ADR-102: Prove a Minimal Sensor to Display MVP

## Context

The broader concept includes modular cabinets, automation, addressed networks and sabotage. Building these before a working signal slice would obscure whether the core simulation is practical.

Source: Design discussion. Darth-Ginger approved this record during the decision review. Implementation and validation have not yet occurred.

## Decision

First prove one pressure sensor, physical cable connectivity and one display. The sensor outputs 255 while at least one player or zombie occupies its tile and 0 otherwise. The display exposes the received byte; any indicator is OFF for zero and ON for nonzero. Use a development source to exercise mixed bit patterns. Do not impose an artificial cable-run length cap in initial development. Cabinets/modules, couplers, switching, graph-to-graph forwarding, automation, wear and snooping are outside the first slice. A manual source is a test aid, not a replacement for the agreed pressure sensor.

## Consequences

### Positive

- Creates a small, observable proof of bit-style signaling.
- Keeps future gameplay from expanding the first deliverable.
- Allows mixed-byte testing before adding numeric sensors.

### Negative

- The first prototype does not deliver the full modular-network vision.
- No artificial length cap is not a guarantee of unlimited performance; scale still requires measurement.

## Related

- Design and MVP
- Decision index

```dataview
TABLE file.folder AS "Folder", adr-status AS "Status", adr_domain AS "Domain", decision_topic AS "Topic", last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
