---
project: zedcomm
created_date: "Saturday, October 24th 2026, 10:47:48 pm"
last_update: "Saturday, October 24th 2026, 10:47:48 pm"
adr-status: accepted
adr_domain: Architecture
adr_number: 302
aliases: []
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_topic: "Separate Communications Framework and Endpoint Behavior"
decision_date: 2026-10-24
fileClass: adr
related-adr: []
related-cards:
tags:
  - zedcomm
  - architecture
---

# ADR-302: Separate Communications Framework and Endpoint Behavior

## Context

Sensors, player actions and automated devices have different triggers but should not each implement cable traversal or multiplayer synchronization. ZedComm should support third-party endpoints while shipping useful native devices.

Source: Design discussion. Darth-Ginger approved this record during the decision review. Implementation and validation have not yet occurred.

## Decision

Ship a communications framework and native endpoints together, with an extensible common endpoint contract. The framework owns connection rules and signal delivery; endpoints own sensing, player interaction, automation and effects of received states. Network infrastructure devices, such as switches, hubs and routers, have a separate simulation role and must be distinct from the endpoint class. Their forwarding and any future latency behavior belongs to the network simulation. Infrastructure-device implementation remains outside the MVP. Simple, on-demand and automated describe activation behavior, not separate transport protocols. Reuse one simulation core for single player and multiplayer, allowing a small dispatch adapter. Define the extension seam without committing here to inheritance, registration callbacks, exact class names or a full public SDK. Native endpoint behavior should exercise the same seam intended for extensions.

## Consequences

### Positive

- Keeps native and extension devices consistent.
- Avoids duplicating network simulation for solo, multiplayer or each device type.
- Lets automated endpoints build on the same signaling operations later.

### Negative

- Requires a small, explicit endpoint contract even in the prototype.
- A stable external API and compatibility policy still need later validation and design.

## Related

- Design and MVP
- Decision index

```dataview
TABLE file.folder AS "Folder", adr-status AS "Status", adr_domain AS "Domain", decision_topic AS "Topic", last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
