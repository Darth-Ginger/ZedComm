#!/usr/bin/env bash
# Links the game's Workshop folder to the repo for day-to-day testing. Bash
# twin of link-dev.ps1, for Linux and for Git Bash on Windows.
#
# Creates <Workshop>/ZedComm pointing at workshop/ZedComm in this repo: a
# directory junction on Windows, a symlink on Linux. The game then loads the mod
# straight from the working copy, and only that folder is reachable through it.
#
#   tools/link-dev.sh                     create the link
#   tools/link-dev.sh --remove            delete the link only
#   tools/link-dev.sh --workshop-dir <dir>   default: ~/Zomboid/Workshop
#                                            (%USERPROFILE%\Zomboid\Workshop on Windows)
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$repo/workshop/ZedComm"
. "$repo/tools/lib.sh"

remove=0 workshop_dir=$(default_workshop_dir)
while [ $# -gt 0 ]; do
    case "$1" in
        --remove) remove=1 ;;
        --workshop-dir) workshop_dir=$2; shift ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
target="$workshop_dir/ZedComm"

if [ $remove -eq 1 ]; then
    if [ ! -e "$target" ] && ! is_link "$target"; then echo "Nothing at $target."; exit 0; fi
    is_link "$target" || { echo "$target is a real folder, not the dev link. Not removing it." >&2; exit 1; }
    remove_link "$target"
    echo "Removed link $target"
    exit 0
fi

if [ -e "$target" ] || is_link "$target"; then
    if is_link "$target" && [ "$(link_target "$target")" = "$(cd "$source_dir" && pwd -P)" ]; then
        echo "Already linked: $target -> $source_dir"
        exit 0
    fi
    echo "$target already exists. Move it aside, or run tools/link-dev.sh --remove if it is an old link, then rerun." >&2
    exit 1
fi

mkdir -p "$workshop_dir"
make_link "$target" "$source_dir"
echo "Linked $target -> $source_dir"
