#!/usr/bin/env bash
# Runs the simulation tests with a Lua 5.1 interpreter. tools/build.sh calls
# this. Without an interpreter it skips with a warning, so a build on a machine
# with no Lua still works; CI sets ZEDCOMM_REQUIRE_LUA=1 so a skip there fails.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
lua=""
for candidate in lua5.1 luajit lua; do
    if command -v "$candidate" >/dev/null 2>&1; then lua=$candidate; break; fi
done
if [ -z "$lua" ]; then
    if [ "${ZEDCOMM_REQUIRE_LUA:-0}" = 1 ]; then
        echo "tests: no Lua 5.1 interpreter found (lua5.1, luajit or lua)" >&2
        exit 1
    fi
    echo "tests skipped: no Lua 5.1 interpreter (install lua5.1 to run them)" >&2
    exit 0
fi
"$lua" tests/simulation_test.lua
