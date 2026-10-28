# Changelog - ZedComm

## Unreleased

- Repo scaffold: the Workshop item lives in `workshop/ZedComm/`, kept apart from docs, tests and tools (ADR-401).
- `tools/link-dev.ps1` links the game's Workshop folder to the repo for testing; `tools/build.ps1` checks and copies the item to `dist/`, with `-Zip` and `-Deploy`.
- Bash versions of both tools (`build.sh`, `link-dev.sh`, shared `lib.sh`) for Linux and Git Bash, plus `selftest.sh`.
- CI runs the PowerShell and Git Bash tools on Windows and the bash tools on Linux.
- `preview.png` for the Workshop, drawn by `tools/make-preview.py`.
