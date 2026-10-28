# Shared helpers for build.sh and link-dev.sh. Sourced, not run.
#
# On Windows these scripts run under Git Bash, where ln -s copies instead of
# linking unless developer mode is on, so links are made as directory junctions
# through cmd. Git Bash reports a junction as a symlink, so test -L sees both.

on_windows() {
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

native_path() {
    if on_windows; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}

default_workshop_dir() {
    if on_windows; then
        printf '%s/Zomboid/Workshop\n' "$(cygpath -u "$USERPROFILE")"
    else
        printf '%s/Zomboid/Workshop\n' "$HOME"
    fi
}

is_link() {
    [ -L "$1" ]
}

link_target() {
    if on_windows; then
        # Resolve through the junction; readlink is unreliable on junctions.
        (cd "$1" && pwd -P)
    else
        readlink -f "$1"
    fi
}

make_link() {  # make_link <link path> <target dir>
    if on_windows; then
        cmd //c mklink //J "$(native_path "$1")" "$(native_path "$2")" >/dev/null
    else
        ln -s "$2" "$1"
    fi
}

remove_link() {  # removes the link only, never the folder it points at
    if on_windows; then
        cmd //c rmdir "$(native_path "$1")"
    else
        rm "$1"
    fi
}
