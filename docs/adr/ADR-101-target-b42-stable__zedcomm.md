---
adr-status: accepted
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_date: 2026-10-24
---

# ADR-101: Target Project Zomboid B42 Stable

## Context

ZedComm needs a concrete compatibility baseline before its first implementation. Supporting multiple major builds or following unstable builds would enlarge the validation and maintenance surface.

## Decision

Target the Project Zomboid B42 stable release line for initial development and validation. Record the exact installed game version with implementation/test evidence. B41 and unstable-branch compatibility are not MVP commitments; this record does not pin an unverified current patch number.

## Consequences

### Positive

- Provides one compatibility baseline for solo and hosted-multiplayer validation.
- Avoids speculative compatibility work before the signal simulation is proven.

### Negative

- B42 updates may still require compatibility fixes.
- Players on other release lines are outside the initial support target.
