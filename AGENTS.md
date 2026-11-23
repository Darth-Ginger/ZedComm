# ZedComm contributor rules

Keep implementation, tests, and documentation aligned with the current Build 42 behavior.

- **Comments.** Explain a contract, an invariant, an engine quirk, or a non-obvious reason the code works this way. Remove comments that repeat the code or describe behavior that changed. Put build history, work-item references, and plans in the changelog, ADRs, or board. An ADR reference is useful when it explains an active constraint.
- **Scope and failure handling.** Reuse the code path that owns the behavior. Keep one implementation of each rule. Check for failures the game or the caller can produce, including stale targets and partial state changes. Give engine-specific workarounds a concrete reason. Add compatibility code only for versions or saves the project supports. Development saves have no compatibility requirement.
- **Physical world actions.** Register install, build, removal, and wiring commands in `PlayerPlacement.lua` and submit them through the shared queue in `PlacementMenu.lua`. The queue walks into reach, and the timed action checks reach and target validity after the walk. Use `walkSquare` only when the interaction requires a specific approach tile.
- **Tests.** Add coverage for behavior that needs proof in the smallest relevant subsystem suite. Put unrelated scenarios in separate `tests/*_test.lua` files with shared fixtures in `tests/support/`. Keep engine-independent tests in the default CI run. Use `PZ_LUA` for checks that require installed game Lua, and report which checks actually ran. Keep live Build 42 results distinct from offline results.
- **Docs.** Review the README, changelog, player instructions, and relevant comments in the same change when behavior or verification status changes. Keep setup steps runnable and status claims tied to observed results. Maintain recipes in `tools/make-recipes.py` and regenerate the item-script blocks, translations, and `docs/recipes.md` together.

At review, check for build narration in shipped files, duplicate rules, unsupported recovery paths, unrelated tests added to large suites, and documentation that disagrees with the current code.
