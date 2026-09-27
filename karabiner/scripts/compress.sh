#!/bin/bash
#
# compress.sh — compresses the items selected in Finder into a ZIP.
#
# Mirrors what Finder's own "Compress" does:
#   1 item    -> <full name>.zip   (report.pdf -> report.pdf.zip, Docs -> Docs.zip)
#   n items   -> Archive.zip next to them
#   collision -> Archive-2.zip, Archive-3.zip ... (never overwrites anything)
#
# Invoked via Karabiner (Hyper+C) or directly from the terminal.
#   --doctor   self-test: paths, permissions, tools
#   --dry-run  only shows what would happen
#
# Deliberately bash-3.2 compatible (/bin/bash on macOS) so the script does
# not depend on Homebrew.

set -uo pipefail

# Karabiner starts scripts with a minimal environment -> set PATH ourselves.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
export LC_ALL="en_US.UTF-8"

ARCHIVE_NAME="${COMPRESS_ARCHIVE_NAME:-Archive}"  # name for multi-item archives
REVEAL="${COMPRESS_REVEAL:-1}"                    # select the result in Finder
LOCK_DIR="/tmp/compress-finder.lock"
STAMP_FILE="/tmp/compress-finder.last"

DRY_RUN=0
PARTIAL=""   # archive currently being written -> removed if we are interrupted

# Under launchd, HOME is not guaranteed — with set -u a missing $HOME would
# mean an immediate, completely silent abort.
if [ -z "${HOME:-}" ]; then
    HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    [ -n "$HOME" ] || HOME="/tmp"
    export HOME
fi

LOG_FILE="${COMPRESS_LOG:-$HOME/.local/state/compress/compress.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
# Not writable? Better to log to /tmp than to run blind.
if ! : >>"$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/compress.log"
fi

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null
    [ -t 1 ] && printf '%s\n' "$*"
    return 0
}

cleanup() {
    # A half-written ZIP is worse than none: Finder would show it as a valid
    # archive.
    [ -n "$PARTIAL" ] && [ -e "$PARTIAL" ] && rm -f "$PARTIAL"
    [ -d "$LOCK_DIR" ] && rmdir "$LOCK_DIR" 2>/dev/null
    return 0
}

# Never overwrite an existing path: foo.zip, foo-2.zip, foo-3.zip ...
# The counter sits before the extension so the file stays openable.
unique_path() {
    local p="$1" d n stem ext i=2
    if [ ! -e "$p" ]; then printf '%s' "$p"; return 0; fi
    d="$(dirname "$p")"
    n="$(basename "$p")"
    case "$n" in
        ?*.*) stem="${n%.*}"; ext=".${n##*.}" ;;
        *)    stem="$n";      ext="" ;;
    esac
    while [ -e "$d/$stem-$i$ext" ]; do i=$((i + 1)); done
    printf '%s' "$d/$stem-$i$ext"
}

reveal() {
    [ "$REVEAL" -eq 1 ] || return 0
    osascript - "$1" <<'OSA' >/dev/null 2>&1
on run argv
    tell application "Finder" to select (POSIX file (item 1 of argv) as alias)
end run
OSA
    return 0
}

# ------------------------------------------------------------- Archiving
# One item goes through ditto — that is what Finder itself uses, so resource
# forks and xattrs survive (as __MACOSX entries). ditto treats a folder and a
# file differently: --keepParent on a *file* would pull the enclosing folder
# into the archive, so it is only correct for folders.
compress_single() {
    local src="$1" out="$2"
    if [ -d "$src" ]; then
        ditto -c -k --sequesterRsrc --keepParent "$src" "$out" </dev/null 2>>"$LOG_FILE"
    else
        ditto -c -k --sequesterRsrc "$src" "$out" </dev/null 2>>"$LOG_FILE"
    fi
}

# Several items land in one archive with all of them at the top level. ditto
# cannot do that (single source only), so zip does it — run from the shared
# parent folder, with relative names, so no absolute paths end up inside.
# -y keeps symlinks as symlinks instead of copying their target in.
compress_multi() {
    local dir="$1" out="$2"
    shift 2
    ( cd "$dir" && zip -r -q -y "$out" -- "$@" ) </dev/null 2>>"$LOG_FILE"
}

# --------------------------------------------------------------- Main routine

# Reads the paths to be archived from "$@", writes the archive next to them.
process() {
    local dir out base names=() n rc
    dir="$(dirname "$1")"

    for n in "$@"; do
        if [ ! -e "$n" ]; then
            log "does not exist: $n"
            return 1
        fi
        names+=("$(basename "$n")")
    done

    if [ ! -w "$dir" ]; then
        log "folder not writable: $dir"
        return 1
    fi

    if [ "$#" -eq 1 ]; then
        # Finder keeps the full name including its extension: a.txt -> a.txt.zip
        base="${names[0]}"
    else
        base="$ARCHIVE_NAME"
    fi
    out="$(unique_path "$dir/$base.zip")"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would compress $# item(s) -> $out"
        return 0
    fi

    log "compressing $# item(s) -> $out"
    PARTIAL="$out"
    if [ "$#" -eq 1 ]; then
        compress_single "$1" "$out"
    else
        compress_multi "$dir" "$out" "${names[@]}"
    fi
    rc=$?
    PARTIAL=""

    if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then
        rm -f "$out"
        log "failed (exit $rc): $out"
        return 1
    fi

    log "done: $out ($(du -h "$out" 2>/dev/null | cut -f1 | tr -d ' '))"
    reveal "$out"
    return 0
}

# The AppleScript source deliberately lives in its own function: bash 3.2
# (/bin/bash on macOS) cannot parse a heredoc inside a command substitution —
# inline, the script would die with a syntax error when run.
finder_selection_source() {
    cat <<'OSA'
on run
    tell application "Finder"
        set sel to selection
        if sel is {} then return ""
        set out to {}
        repeat with itm in sel
            set end of out to POSIX path of (itm as alias)
        end repeat
        set AppleScript's text item delimiters to linefeed
        return out as text
    end tell
end run
OSA
}

finder_selection() {
    local out rc try n
    # On the very first run macOS shows the automation dialog. That pulls focus
    # away from Finder, and the selection then comes back empty. So try again.
    for try in 1 2 3; do
        out="$(finder_selection_source | osascript - 2>>"$LOG_FILE")"
        rc=$?
        if [ "$rc" -ne 0 ]; then
            log "osascript failed (exit $rc) — is Finder automation access missing?"
            return "$rc"
        fi
        [ -n "$out" ] && break
        [ "$try" -lt 3 ] && sleep 1
    done
    n="$(printf '%s\n' "$out" | grep -c . )"
    log "Finder reports $n selected item(s)"
    # The trailing newline is mandatory: without it a 'read' loop discards the
    # last line.
    printf '%s\n' "$out"
}

doctor() {
    echo "Compress — self-test"
    echo "  Script:     $0"
    echo "  Log:        $LOG_FILE"
    echo "  PATH:       $PATH"
    echo
    echo "  Tools:"
    for t in ditto zip osascript; do
        printf "    %-9s %s\n" "$t" "$(command -v "$t" || echo 'MISSING')"
    done
    echo
    printf "  Finder automation: "
    if osascript -e 'tell application "Finder" to return name of startup disk' >/dev/null 2>&1; then
        echo "OK"
    else
        echo "BLOCKED — System Settings > Privacy & Security > Automation"
    fi
    echo
    echo "  Current Finder selection:"
    finder_selection | sed 's/^/    /'
}

# mkdir is atomic — more reliable as a lock than a file holding a PID.
acquire_lock() {
    mkdir "$LOCK_DIR" 2>/dev/null && return 0
    # Collect a stale lock from a crashed instance (older than 1 h).
    if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null
        mkdir "$LOCK_DIR" 2>/dev/null && return 0
    fi
    return 1
}

main() {
    local now prev

    # No arguments = invoked by keypress. Karabiner processes shell_commands
    # serially; a large folder would block the keyboard queue. So detach
    # immediately and release the caller.
    if [ "$#" -eq 0 ] && [ "${COMPRESS_CHILD:-0}" != "1" ]; then
        # A held key repeats — without debouncing, dozens of instances start up.
        now="$(date +%s)"
        prev=0
        [ -f "$STAMP_FILE" ] && prev="$(cat "$STAMP_FILE" 2>/dev/null)"
        case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
        if [ "$((now - prev))" -lt 2 ]; then
            exit 0
        fi
        printf '%s' "$now" >"$STAMP_FILE" 2>/dev/null
        export COMPRESS_CHILD=1
        nohup "$0" >>"$LOG_FILE" 2>&1 &
        exit 0
    fi

    log "--- start (pid $$, user $(id -un), home $HOME) ---"

    case "${1:-}" in
        --doctor) doctor; exit 0 ;;
        --dry-run) DRY_RUN=1; shift ;;
    esac

    acquire_lock || { log "already running — keypress ignored"; exit 0; }
    trap cleanup EXIT INT TERM

    local targets=() sel="" dir="" same=1 ok=0 fail=0 i=0

    if [ "$#" -gt 0 ]; then
        for sel in "$@"; do targets+=("${sel%/}"); done
    else
        # '|| [ -n "$sel" ]' additionally catches a last line without newline.
        while IFS= read -r sel || [ -n "$sel" ]; do
            [ -n "$sel" ] && targets+=("${sel%/}")
            sel=""
        done < <(finder_selection)
    fi

    if [ "${#targets[@]}" -eq 0 ]; then
        log "nothing selected — was the file actually clicked in Finder?"
        exit 0
    fi

    # One archive only makes sense for items sharing a folder. A selection
    # spanning several folders (search results, "Recents") instead gets one
    # archive per item — better than an archive full of absolute paths.
    dir="$(dirname "${targets[0]}")"
    i=0
    while [ "$i" -lt "${#targets[@]}" ]; do
        [ "$(dirname "${targets[$i]}")" = "$dir" ] || same=0
        i=$((i + 1))
    done

    if [ "$same" -eq 1 ]; then
        process "${targets[@]}" && ok=1 || fail=1
    else
        log "selection spans several folders — one archive per item"
        i=0
        while [ "$i" -lt "${#targets[@]}" ]; do
            if process "${targets[$i]}"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
            i=$((i + 1))
        done
    fi

    log "result: $ok succeeded, $fail failed"
    # Exit code matters when called from the terminal; Karabiner ignores it.
    [ "$fail" -gt 0 ] && exit 1
    exit 0
}

main "$@"
