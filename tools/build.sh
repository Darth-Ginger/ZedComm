#!/usr/bin/env bash
# Builds the ZedComm Workshop item into dist/ZedComm. Bash twin of build.ps1,
# for Linux and for Git Bash on Windows.
#
# Copies workshop/ZedComm to dist/ZedComm, leaving out .gitkeep files and
# OS or file-sync droppings (@eaDir, Thumbs.db, desktop.ini, .DS_Store). Stops
# before copying if the mod holds a file type the game does not use, mod.info
# lacks a required key, or tests/run.sh (when present) fails.
#
#   tools/build.sh                 check and build
#   tools/build.sh --zip           also dist/ZedComm-<modversion>.zip
#   tools/build.sh --deploy        also copy into the game's Workshop folder
#   tools/build.sh --workshop-dir <dir>   Workshop folder to deploy into
#
# --deploy refuses when the Workshop folder holds the dev link from
# link-dev.sh, because copying through the link would overwrite the repo.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$repo/workshop/ZedComm"
dist="$repo/dist"
out="$dist/ZedComm"
mod_info="$source_dir/Contents/mods/ZedComm/42/mod.info"
. "$repo/tools/lib.sh"

deploy=0 zip=0 workshop_dir=$(default_workshop_dir)
while [ $# -gt 0 ]; do
    case "$1" in
        --deploy) deploy=1 ;;
        --zip) zip=1 ;;
        --workshop-dir) workshop_dir=$2; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# File types a Project Zomboid mod ships. Anything else is a stray.
# OS and file-sync droppings are skipped rather than reported.
junk=(-name @eaDir -prune -o -name Thumbs.db -o -name desktop.ini -o -name .DS_Store -o -name .gitkeep)
allowed=" lua txt info png ogg wav bank x fbx xml pack tiles json "
problems=()

[ -f "$mod_info" ] || { echo "mod.info not found at $mod_info" >&2; exit 1; }
mod_value() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$mod_info" | tr -d '\r' | head -n1; }
for key in name id versionMin; do
    [ -n "$(mod_value "$key")" ] || problems+=("mod.info is missing $key")
done
modversion=$(mod_value modversion)

count=0
while IFS= read -r -d '' file; do
    rel=${file#"$source_dir"/}
    name=${file##*/}
    ext=${name##*.}
    [ "$ext" = "$name" ] && ext=""
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    case "$allowed" in *" $ext "*) count=$((count + 1)) ;; *) problems+=("not a mod file: $rel") ;; esac
done < <(find "$source_dir" \( "${junk[@]}" \) -o -type f -print0)

[ -f "$source_dir/preview.png" ] || echo "WARNING: workshop/ZedComm/preview.png is missing; the Workshop uploader needs it." >&2

if [ -f "$repo/tests/run.sh" ]; then
    bash "$repo/tests/run.sh" || problems+=("tests failed (exit $?)")
fi

if [ ${#problems[@]} -gt 0 ]; then
    printf '  %s\n' "${problems[@]}" >&2
    echo "Build stopped: ${#problems[@]} problem(s)." >&2
    exit 1
fi

rm -rf "$out"
mkdir -p "$out"
# Folders first, so required empty ones such as common/ survive.
(cd "$source_dir" && find . -name @eaDir -prune -o -type d -print0 | (cd "$out" && xargs -0 mkdir -p))
(cd "$source_dir" && find . \( "${junk[@]}" \) -o -type f -print0 | while IFS= read -r -d '' f; do cp "$f" "$out/$f"; done)
echo "Built $out ($count files, modversion $modversion)"

if [ $zip -eq 1 ]; then
    zip_path="$dist/ZedComm-$modversion.zip"
    rm -f "$zip_path"
    if command -v zip >/dev/null; then
        (cd "$dist" && zip -qr "$zip_path" ZedComm)
    elif command -v powershell.exe >/dev/null; then
        powershell.exe -NoProfile -Command "Compress-Archive -Path '$(native_path "$out")' -DestinationPath '$(native_path "$zip_path")'"
    else
        echo "No zip tool found (zip or powershell.exe)." >&2; exit 1
    fi
    echo "Zipped $zip_path"
fi

if [ $deploy -eq 1 ]; then
    target="$workshop_dir/ZedComm"
    if is_link "$target"; then
        echo "$target is the dev link to the repo. Run tools/link-dev.sh --remove first, then deploy." >&2
        exit 1
    fi
    rm -rf "$target"
    mkdir -p "$workshop_dir"
    cp -R "$out" "$target"
    echo "Deployed to $target"
fi
