#!/usr/bin/env bash
# Runs every tests/*_test.lua with a Lua 5.1 interpreter. tools/build.sh calls
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
status=0
checks=0
failures=0
suites=0
failed_suites=0
skipped=()
for t in tests/*_test.lua; do
    echo "== $t"
    if output=$("$lua" "$t" 2>&1); then
        result=0
    else
        result=$?
        status=1
        failed_suites=$((failed_suites + 1))
    fi
    printf '%s\n' "$output"
    if [[ "$output" == SKIP\ * ]] && [ "$result" -eq 0 ]; then
        skipped+=("$t")
        continue
    fi
    suites=$((suites + 1))
    read -r suite_checks suite_failures < <(
        printf '%s\n' "$output" | awk '/^[0-9]+ checks, [0-9]+ failed/ { checks += $1; failures += $3 }
            END { print checks + 0, failures + 0 }'
    )
    checks=$((checks + suite_checks))
    failures=$((failures + suite_failures))
done
printf 'Total %d checks, %d failed, %d suites run, %d suites failed, %d skipped\n' \
    "$checks" "$failures" "$suites" "$failed_suites" "${#skipped[@]}"
if [ "${#skipped[@]}" -gt 0 ]; then
    printf 'Skipped %s\n' "${skipped[@]}"
fi
exit $status
