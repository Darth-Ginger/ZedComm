---
project: zedcomm
created_date: "Saturday, October 24th 2026, 10:47:41 pm"
last_update: "Saturday, October 24th 2026, 10:47:41 pm"
adr-status: accepted
adr_domain: General
adr_number: 101
aliases: []
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_topic: "Target Project Zomboid B42 Stable"
decision_date: 2026-10-24
fileClass: adr
related-adr: []
related-cards:
tags:
  - zedcomm
  - scope
---

# ADR-101: Target Project Zomboid B42 Stable

## Context

ZedComm needs a concrete compatibility baseline before its first implementation. Supporting multiple major builds or following unstable builds would enlarge the validation and maintenance surface.

Source: Design discussion. Darth-Ginger approved this record during the decision review. Implementation and validation have not yet occurred.

## Decision

Target the Project Zomboid B42 stable release line for initial development and validation. Record the exact installed game version with implementation/test evidence. B41 and unstable-branch compatibility are not MVP commitments; this record does not pin an unverified current patch number.

## Consequences

### Positive

- Provides one compatibility baseline for solo and hosted-multiplayer validation.
- Avoids speculative compatibility work before the signal simulation is proven.

### Negative

- B42 updates may still require compatibility fixes.
- Players on other release lines are outside the initial support target.

## Related

- Design and MVP
- Decision index

```dataview
TABLE file.folder AS "Folder", adr-status AS "Status", adr_domain AS "Domain", decision_topic AS "Topic", last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
