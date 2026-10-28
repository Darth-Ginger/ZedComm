#!/usr/bin/env bash
# Exercises build.sh and link-dev.sh against a scratch Workshop folder: the
# link, the deploy guard, removal leaving the repo intact, a clean deploy, and
# a stray file stopping the build. Run by CI on Linux and Windows; safe to run
# locally, it never touches the real Workshop folder.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
w=$(mktemp -d)/Workshop
mod=ZedComm/Contents/mods/ZedComm/42/mod.info
fail() { echo "SELFTEST FAILED: $*" >&2; exit 1; }

tools/build.sh --zip
ls dist/ZedComm-*.zip >/dev/null || fail "no zip written"

tools/link-dev.sh --workshop-dir "$w"
[ -f "$w/$mod" ] || fail "the link does not reach the mod"
tools/link-dev.sh --workshop-dir "$w" | grep -q "Already linked" || fail "second link run did not see the link"

if tools/build.sh --deploy --workshop-dir "$w" 2>/dev/null; then fail "deploy did not refuse the dev link"; fi

tools/link-dev.sh --remove --workshop-dir "$w"
[ -f "workshop/$mod" ] || fail "removing the link deleted the repo copy"

tools/build.sh --deploy --workshop-dir "$w"
[ -d "$w/ZedComm/Contents/mods/ZedComm/common" ] || fail "deploy lost the empty common folder"
[ -z "$(find "$w/ZedComm" -name .gitkeep)" ] || fail "deploy shipped .gitkeep files"
if tools/link-dev.sh --remove --workshop-dir "$w" 2>/dev/null; then fail "remove accepted a real folder"; fi

echo stray > workshop/ZedComm/notes.md
if tools/build.sh 2>/dev/null; then rm workshop/ZedComm/notes.md; fail "the build accepted a stray .md file"; fi
rm workshop/ZedComm/notes.md

echo "selftest passed"
