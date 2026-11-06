---
project: zedcomm
created_date: "Friday, November 6th 2026, 3:59:00 pm"
last_update: "Friday, November 6th 2026, 3:59:00 pm"
adr-status: accepted
adr_domain: Architecture
adr_number: 308
aliases: []
authors:
  - Claude
  - Darth-Ginger
deciders:
  - Darth-Ginger
decision_topic: "Existing objects join ZedComm by in-place modification"
decision_date: 2026-11-06
fileClass: adr
related-adr:
related-cards:
tags:
  - zedcomm
  - devices
  - extensibility
---

# ADR-308: Existing Objects Join ZedComm by In-Place Modification

## Context

ZedComm should let existing game objects take a network role (ADR-307), so that a submod can, for example, make every vanilla lamp a possible receiver by registering a definition and its responses rather than writing a new device. ADR-302 called for this extension seam without fixing its shape.

Three ways were weighed on 2026-11-06:

- **Adopt automatically** when a cable is connected to a matching object. Cheapest, but the player never chooses it and nothing gates it.
- **New crafted items** such as a "Network Lamp". Safe identity, but each device needs its own item scripts and sprite set, fixed fixtures such as ceiling lights cannot be crafted, and removing the mod breaks the crafted items.
- **Modify in place**, the way vanilla turns a lamp into a battery lamp: a timed action, gated by Electricity skill and consuming an Electronics Scrap, sets a flag on the same lamp object (`setUseBattery`), and the game carries the lamp's custom settings through pickup and placement (`ISLightActions.lua`, `ISMoveableSpriteProps.lua` in B42).

## Decision

Existing objects join ZedComm by in-place modification, modelled on vanilla lamp modification.

1. **Definitions say what can be modified.** A device definition registers a match (which objects qualify), a role, ports and the responses to signals. Native ZedComm devices register the same way (ADR-302). A submod adds a definition; it does not patch objects.
2. **Modifying is a player action.** "Install network receiver" (or sender) is a timed action with a skill requirement and parts. It writes the ZedComm tag onto the object. Only modifying needs the skill.
3. **The modification stays with the object.** Picking up a modified object keeps its ZedComm attribute on the inventory item, and placing it again restores it, like any installed module (ADR-304). Placing needs no skill. Cable links do not travel with it; they detach on pickup as ADR-304 already requires.
4. **A modified object is still the original object.** A modified lamp with no cable attached is an ordinary lamp: it turns on and off normally, and it simply also has a port a cable can be attached to.
5. **Connected behaviour belongs to the definition.** Once a cable is attached, the definition's responses apply, including ADR-303's OFF default when the attached network has no source. Not attached is not the same as disconnected: only an attached port fails OFF.
6. **ZedComm's own devices are crafted items.** The pressure sensor and display are new items with their own definitions; in-place modification is for objects that already exist in the game.

## Consequences

### Positive

- The player chooses which objects join the network, behind a skill and parts gate that matches vanilla's own modification.
- No new art or item scripts per adopted object type, and fixed fixtures can be modified where they stand.
- Removing ZedComm leaves only harmless data on modified objects.
- A lamp submod stays small: register a definition with a match and responses.

### Negative

- The game's own pickup code copies only vanilla light settings and copies the item before ZedComm's removal hook runs, so keeping the attribute through pickup needs ZedComm's own handling. This needs a spike before modification is built.
- Each definition must decide how a connected object treats its own controls, such as a lamp's switch, while a cable is attached. Not yet decided.
- Matching on object classes and sprites ties definitions to game internals that can change between builds.

## Related

- Design and MVP
- Decision index

```dataview
TABLE file.folder AS "Folder", adr-status AS "Status", adr_domain AS "Domain", decision_topic AS "Topic", last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
