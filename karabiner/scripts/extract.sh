#!/bin/bash
#
# extract.sh — extracts the archives selected in Finder.
#
# Takes care of the two things that make unpacking by hand tedious:
#   1. Nested archives (ZIP inside ZIP inside ZIP) are extracted recursively.
#   2. Redundant folder levels (foo/foo/foo/files) are collapsed.
#
# Invoked via Karabiner (Hyper+E) or directly from the terminal.
#   --doctor   self-test: paths, permissions, tools
#   --dry-run  only shows what would happen
#
# Deliberately bash-3.2 compatible (/bin/bash on macOS) so the script does
# not depend on Homebrew.

set -uo pipefail

# Karabiner starts scripts with a minimal environment -> set PATH ourselves.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
export LC_ALL="en_US.UTF-8"

MAX_DEPTH="${EXTRACT_MAX_DEPTH:-8}"          # max. nesting depth
MAX_ARCHIVES="${EXTRACT_MAX_ARCHIVES:-200}"  # guard against ZIP bombs
TRASH_ORIGINAL="${EXTRACT_TRASH_ORIGINAL:-1}"
# 1 = contents land directly in the archive's folder (no wrapper around them).
# 0 = multi-item archives go into a folder named after the archive.
FLATTEN="${EXTRACT_FLATTEN:-1}"
LOCK_DIR="/tmp/extract-finder.lock"
STAMP_FILE="/tmp/extract-finder.last"

DRY_RUN=0
WORK_DIR=""

# Under launchd, HOME is not guaranteed — with set -u a missing $HOME would
# mean an immediate, completely silent abort.
if [ -z "${HOME:-}" ]; then
    HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    [ -n "$HOME" ] || HOME="/tmp"
    export HOME
fi

LOG_FILE="${EXTRACT_LOG:-$HOME/.local/state/extract/extract.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
# Not writable? Better to log to /tmp than to run blind.
if ! : >>"$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/extract.log"
fi

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null
    [ -t 1 ] && printf '%s\n' "$*"
    return 0
}

cleanup() {
    [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    [ -d "$LOCK_DIR" ] && rmdir "$LOCK_DIR" 2>/dev/null
    return 0
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# -------------------------------------------------------------- Archive types

archive_kind() {
    case "$(lower "${1##*/}")" in
        *.tar.gz|*.tgz|*.tar.bz2|*.tbz|*.tbz2|*.tar.xz|*.txz|*.tar.zst|*.tar) echo tar ;;
        *.zip)          echo zip ;;
        *.gz)           echo gz ;;
        *.bz2)          echo bz2 ;;
        *.xz)           echo xz ;;
        *.zst)          echo zst ;;
        *.7z|*.rar)     echo unar ;;
        *)              echo "" ;;
    esac
}

# Strip the extension — for .tar.gz & friends both parts.
strip_ext() {
    case "$(lower "$1")" in
        *.tar.gz|*.tar.bz2|*.tar.xz|*.tar.zst) echo "${1%.*.*}" ;;
        *) echo "${1%.*}" ;;
    esac
}

# Never overwrite an existing path: foo.txt, foo-2.txt, foo-3.txt ...
# The counter sits before the extension so the file stays openable.
unique_path() {
    local p="$1" d n stem ext i=2
    if [ ! -e "$p" ]; then printf '%s' "$p"; return 0; fi
    d="$(dirname "$p")"
    n="$(basename "$p")"
    case "$n" in
        ?*.*) stem="${n%.*}"; ext=".${n##*.}" ;;   # regular file with extension
        *)    stem="$n";      ext="" ;;            # folder or .hidden
    esac
    while [ -e "$d/$stem-$i$ext" ]; do i=$((i + 1)); done
    printf '%s' "$d/$stem-$i$ext"
}

# Every extractor gets </dev/null: a password-protected archive should fail
# instead of waiting for input that will never come.
extract() {
    local src="$1" dst="$2" base
    case "$(archive_kind "$src")" in
        zip)
            # ditto is the macOS-native way (resource forks, umlauts in
            # Windows ZIPs); unzip only as a fallback.
            ditto -x -k --sequesterRsrc "$src" "$dst" </dev/null 2>>"$LOG_FILE" \
                || unzip -qq -n -O UTF-8 "$src" -d "$dst" </dev/null 2>>"$LOG_FILE"
            ;;
        tar)
            tar -xf "$src" -C "$dst" </dev/null 2>>"$LOG_FILE"
            ;;
        gz|bz2|xz|zst)
            base="$(strip_ext "${src##*/}")"
            [ -n "$base" ] || base="extracted"
            case "$(archive_kind "$src")" in
                gz)  gzip  -dc "$src" ;;
                bz2) bzip2 -dc "$src" ;;
                xz)  xz    -dc "$src" ;;
                zst) zstd  -dc "$src" ;;
            esac >"$dst/$base" 2>>"$LOG_FILE"
            ;;
        unar)
            command -v unar >/dev/null 2>&1 || {
                log "unar missing (brew install unar) — skipped: $src"
                return 3
            }
            unar -quiet -force-overwrite -output-directory "$dst" "$src" \
                </dev/null >>"$LOG_FILE" 2>&1
            ;;
        *)
            return 2
            ;;
    esac
}

# --------------------------------------------------------- Structure clean-up
# Straighten out the structure. Guiding principle: the result should match what
# double-clicking in Finder gives you — only across every level and without the
# redundant repetitions of the archive name.

list_entries() {
    find "$1" -mindepth 1 -maxdepth 1 \
        ! -name '.DS_Store' ! -name '__MACOSX' -print0 2>/dev/null
}

# Dismantles single-folder levels: foo/foo/foo/x -> x.
# With an archive name as $2, only levels repeating exactly that name are
# removed. With an empty $2, every single-folder level goes away — that is
# flatten mode, where the contents are meant to be unwrapped anyway.
collapse_redundant() {
    local dir="$1" base="$2" parent lb entries=() n tmp round=0
    parent="$(dirname "$dir")"
    lb="$(lower "$base")"
    while [ "$round" -lt 10 ]; do
        entries=()
        while IFS= read -r -d '' n; do entries+=("$n"); done < <(list_entries "$dir")
        [ "${#entries[@]}" -eq 1 ] || break
        [ -d "${entries[0]}" ] || break
        if [ -n "$lb" ] && [ "$(lower "$(basename "${entries[0]}")")" != "$lb" ]; then
            break
        fi
        # Detour via a sibling path: never an mv into itself.
        tmp="$parent/.extract-collapse.$$.$round"
        mv "${entries[0]}" "$tmp" 2>/dev/null || break
        rm -rf "$dir"
        mv "$tmp" "$dir" 2>/dev/null || break
        round=$((round + 1))
    done
    return 0
}

# If the folder holds exactly one item, that item moves up one level and the
# wrapper goes away. Prints the new path on success.
promote_single() {
    local dir="$1" parent entries=() n target
    parent="$(dirname "$dir")"
    while IFS= read -r -d '' n; do entries+=("$n"); done < <(list_entries "$dir")
    [ "${#entries[@]}" -eq 1 ] || return 1
    target="$(unique_path "$parent/$(basename "${entries[0]}")")"
    mv "${entries[0]}" "$target" 2>/dev/null || return 1
    rm -rf "$dir"
    printf '%s' "$target"
    return 0
}

# ------------------------------------------------------------ Nested archives
# Recursion: as long as archives sit in the tree, extract those as well. Every
# inner archive is replaced by its contents and then deleted.

NESTED_PATTERNS=( -iname '*.zip' -o -iname '*.tar' -o -iname '*.tar.gz'
                  -o -iname '*.tgz' -o -iname '*.tar.bz2' -o -iname '*.tbz'
                  -o -iname '*.tbz2' -o -iname '*.tar.xz' -o -iname '*.txz'
                  -o -iname '*.tar.zst' -o -iname '*.7z' -o -iname '*.rar' )

unpack_nested() {
    local root="$1" depth=0 done_count=0 found inner target list=() i

    while [ "$depth" -lt "$MAX_DEPTH" ]; do
        # Collect the full list first, then work: paths shift around while
        # extracting, and a running find would trip over that.
        list=()
        while IFS= read -r -d '' inner; do
            list+=("$inner")
        done < <(find "$root" -type f \( "${NESTED_PATTERNS[@]}" \) -print0 2>/dev/null)
        [ "${#list[@]}" -eq 0 ] && break

        found=0
        i=0
        while [ "$i" -lt "${#list[@]}" ]; do
            inner="${list[$i]}"
            i=$((i + 1))
            # May already have been moved during this round.
            [ -f "$inner" ] || continue

            if [ "$done_count" -ge "$MAX_ARCHIVES" ]; then
                log "WARNING: limit of $MAX_ARCHIVES archives reached — recursion stopped"
                return 0
            fi

            target="$(unique_path "$(strip_ext "$inner")")"
            mkdir -p "$target" 2>/dev/null || continue

            if extract "$inner" "$target"; then
                rm -f "$inner"
                collapse_redundant "$target" "$(basename "$target")"
                promote_single "$target" >/dev/null
                found=1
                done_count=$((done_count + 1))
                log "  nested: ${inner#$root/}"
            else
                rmdir "$target" 2>/dev/null
                log "  not extractable, left in place: ${inner#$root/}"
            fi
        done

        [ "$found" -eq 0 ] && break
        depth=$((depth + 1))
    done

    [ "$depth" -ge "$MAX_DEPTH" ] && log "WARNING: max. depth $MAX_DEPTH reached"
    return 0
}

# --------------------------------------------------------------- Main routine

process_archive() {
    local src="$1" dir base target entries=() n i moved=0
    src="${src%/}"

    [ -f "$src" ] || { log "not a file: $src"; return 1; }
    [ -n "$(archive_kind "$src")" ] || { log "not an archive: ${src##*/}"; return 1; }

    dir="$(dirname "$src")"
    base="$(strip_ext "${src##*/}")"
    [ -w "$dir" ] || { log "folder not writable: $dir"; return 1; }

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would extract: $src -> $dir/$base"
        return 0
    fi

    log "extracting: $src"

    # Temp folder deliberately NEXT TO the archive (same volume): the final mv
    # is then a rename instead of a copy across volume boundaries.
    WORK_DIR="$(mktemp -d "$dir/.extract.XXXXXX")" || {
        log "cannot create a work folder in $dir"; return 1
    }

    if ! extract "$src" "$WORK_DIR"; then
        rm -rf "$WORK_DIR"; WORK_DIR=""
        log "extraction failed: ${src##*/}"
        return 1
    fi

    unpack_nested "$WORK_DIR"
    if [ "$FLATTEN" -eq 1 ]; then
        # Every single-folder wrapper goes away so the actual contents remain
        # and can be placed right next to the archive.
        collapse_redundant "$WORK_DIR" ""
    else
        collapse_redundant "$WORK_DIR" "$base"
    fi

    entries=()
    while IFS= read -r -d '' n; do entries+=("$n"); done < <(list_entries "$WORK_DIR")

    if [ "${#entries[@]}" -eq 0 ]; then
        rm -rf "$WORK_DIR"; WORK_DIR=""
        log "archive was empty: ${src##*/}"
        return 1
    fi

    if [ "$FLATTEN" -eq 1 ] || [ "${#entries[@]}" -eq 1 ]; then
        # Everything individually into the archive's folder. unique_path keeps
        # an existing file from being overwritten — this is exactly where the
        # old version silently lost data.
        i=0
        while [ "$i" -lt "${#entries[@]}" ]; do
            n="${entries[$i]}"
            i=$((i + 1))
            target="$(unique_path "$dir/$(basename "$n")")"
            if mv "$n" "$target" 2>/dev/null; then
                moved=$((moved + 1))
                log "  -> $(basename "$target")"
            else
                log "  mv failed: $(basename "$n")"
            fi
        done
        if [ "$moved" -eq 0 ]; then
            log "nothing moved: ${src##*/}"
            return 1
        fi
        rm -rf "$WORK_DIR"
    else
        # Several items -> into a folder named after the archive.
        target="$(unique_path "$dir/$base")"
        mv "$WORK_DIR" "$target" || { log "mv failed"; return 1; }
        chmod 755 "$target" 2>/dev/null
        moved=1
    fi
    WORK_DIR=""

    log "done: ${src##*/} -> $moved item(s) in $dir"

    # The original goes only now — and into the trash, not via rm.
    if [ "$TRASH_ORIGINAL" -eq 1 ]; then
        osascript - "$src" <<'OSA' >/dev/null 2>&1
on run argv
    tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)
end run
OSA
    fi

    # The return value is the number of items placed — the caller sums them up
    # for the notification.
    printf '%s' "$moved"
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
    # away from Finder, and the selection then comes back empty — exactly what
    # happened here. So try again a couple of times.
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
    echo "Extract — self-test"
    echo "  Script:     $0"
    echo "  Log:        $LOG_FILE"
    echo "  PATH:       $PATH"
    echo
    echo "  Extractors:"
    for t in ditto unzip tar gzip bzip2 xz zstd unar; do
        printf "    %-6s %s\n" "$t" "$(command -v "$t" || echo 'MISSING')"
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
    # serially; a large archive would block the keyboard queue. So detach
    # immediately and release the caller.
    if [ "$#" -eq 0 ] && [ "${EXTRACT_CHILD:-0}" != "1" ]; then
        # A held key repeats — without debouncing, dozens of instances start up.
        now="$(date +%s)"
        prev=0
        [ -f "$STAMP_FILE" ] && prev="$(cat "$STAMP_FILE" 2>/dev/null)"
        case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
        if [ "$((now - prev))" -lt 2 ]; then
            exit 0
        fi
        printf '%s' "$now" >"$STAMP_FILE" 2>/dev/null
        export EXTRACT_CHILD=1
        nohup "$0" >>"$LOG_FILE" 2>&1 &
        exit 0
    fi

    log "--- start (pid $$, user $(id -un), home $HOME) ---"

    case "${1:-}" in
        --doctor) doctor; exit 0 ;;
        --dry-run) DRY_RUN=1; shift ;;
    esac

    # Repeated keypresses must not get in each other's way.
    acquire_lock || { log "already running — keypress ignored"; exit 0; }
    trap cleanup EXIT INT TERM

    local targets=() sel="" ok=0 fail=0 items=0 got=""

    if [ "$#" -gt 0 ]; then
        for sel in "$@"; do targets+=("$sel"); done
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

    for sel in "${targets[@]}"; do
        if got="$(process_archive "$sel")"; then
            # Only let digits through: otherwise the arithmetic below breaks.
            case "$got" in ''|*[!0-9]*) got=0 ;; esac
            ok=$((ok + 1))
            items=$((items + got))
        else
            fail=$((fail + 1))
        fi
    done

    log "result: $ok succeeded, $fail failed, $items item(s) placed"
    exit 0
}

main "$@"
