---
project: zedcomm
created_date: "Wednesday, October 28th 2026, 12:48:00 pm"
last_update: "Wednesday, October 28th 2026, 12:48:00 pm"
adr-status: accepted
adr_domain: Infrastructure
adr_number: 401
aliases: []
authors:
  - Claude
deciders:
  - Darth-Ginger
decision_topic: "Keep the Workshop item in its own repo folder"
decision_date: 2026-10-28
fileClass: adr
related-adr:
related-cards:
tags:
  - zedcomm
  - repo
  - build
---

# ADR-401: Keep the Workshop Item in Its Own Repo Folder

## Context

Project Zomboid only loads a mod laid out as a Workshop item: `workshop.txt` and `preview.png` at the item root, then `Contents/mods/ZedComm/` with a `common/` folder and a `42/` version folder holding `mod.info` and `media/`. The Workshop uploader sends that item folder as it is. Darth-Ginger wants the ADRs kept beside the code for his own knowledge tracking, along with tests and tooling, none of which belong in the game or the upload.

Options considered:

- **Repo root is the Workshop item.** Simplest, but ADRs, tests and `.git` would sit inside the folder the uploader reads, and whether the uploader skips them is unverified.
- **Source tree in a different shape, assembled by a build.** Flexible, but every in-game test needs a build first, and the source no longer looks like the mod the wiki and other mods describe.
- **The Workshop item as one folder inside the repo.** The game and the uploader see only that folder; everything else lives beside it.

## Decision

The repo keeps the Workshop item, exactly as the game expects it, in `workshop/ZedComm/`. Documentation and ADRs live in `docs/`, tests in `tests/`, and scripts in `tools/`, all outside that folder.

For day-to-day testing, `tools/link-dev.ps1` creates a directory junction from `%USERPROFILE%\Zomboid\Workshop\ZedComm` to `workshop/ZedComm/` on the Windows PC that runs the game, so edits load without a build. For releases, `tools/build.ps1` copies the item to `dist/ZedComm/` (gitignored), leaving out `.gitkeep` files, and stops if the item holds a file type the game does not use, if `mod.info` lacks `name`, `id` or `versionMin`, or if `tests/run.ps1` fails. `-Zip` adds an archive and `-Deploy` copies the build into the game's Workshop folder, refusing while the dev link is in place. The in-game uploader lists items from the game's Workshop folder, so a release is built with `-Deploy` and uploaded from that checked copy.



## Consequences

### Positive

- Nothing outside `workshop/ZedComm/` can reach the game or a Workshop upload, so ADRs, tests and tools can change freely.
- In-game testing reads the working copy directly; no build step between an edit and a reload.
- A release is a clean, checked snapshot that can be matched to a git tag.
- The pure-Lua simulation core in `media/lua/shared/ZedComm/` (ADR-302) can be tested from `tests/` outside the game.

### Negative

- Two ways of feeding the game (link or deploy) must not be mixed; the deploy guard enforces this but it is still something to know.
- Two versions of each tool must be kept in step; CI runs both so a drift shows up as a failing job.

## Related

```dataview
TABLE 
    file.folder AS "Folder",
    adr-status AS "Status",
    adr_domain AS "Domain",
    decision_topic AS "Topic",
    last_update as "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
