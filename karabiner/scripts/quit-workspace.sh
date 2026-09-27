#!/bin/bash
#
# quit-workspace.sh — closes every window on one AeroSpace workspace
# (the focused one unless told otherwise) and quits the apps behind them.
#
# Each window goes through `aerospace close --quit-if-last-window`, so an app
# only quits once its final window is gone. Two things follow from that, both
# deliberate:
#
#   * An app that also has windows on OTHER workspaces keeps running — only its
#     windows here disappear. Quitting it outright would take the other
#     workspaces down with it.
#   * Closing goes through the app itself, so unsaved work raises the usual
#     save dialog instead of being thrown away. A window left standing behind
#     such a dialog is reported as stuck, not silently forgotten.
#
#   --workspace <name>  act on that workspace instead of the focused one
#   --dry-run           list what would happen, change nothing
#   --force             SIGTERM whatever is still alive afterwards (DATA LOSS)
#   --doctor            environment check
#
# Written for bash 3.2 (/bin/bash on macOS), so no associative arrays.

set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

if [ -z "${HOME:-}" ]; then
    HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    [ -n "$HOME" ] || HOME="/tmp"
    export HOME
fi

LOG_FILE="${QUIT_WORKSPACE_LOG:-$HOME/.local/state/quit-workspace/quit-workspace.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
: >>"$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/quit-workspace.log"

# Finder relaunches itself instantly, and quitting the window manager mid-run
# would strand everything else.
EXCLUDE="${QUIT_WORKSPACE_EXCLUDE:-com.apple.finder bobko.aerospace}"
LOCK_DIR="/tmp/quit-workspace.lock"
STAMP_FILE="/tmp/quit-workspace.last"
MAX_ROUNDS=200

DRY_RUN=0
FORCE=0
WORKSPACE=""
TRIED=""

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null
    [ -t 1 ] && printf '%s\n' "$*"
    return 0
}

cleanup() {
    [ -n "$TRIED" ] && [ -f "$TRIED" ] && rm -f "$TRIED"
    [ -d "$LOCK_DIR" ] && rmdir "$LOCK_DIR" 2>/dev/null
    return 0
}

acquire_lock() {
    mkdir "$LOCK_DIR" 2>/dev/null && return 0
    if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null
        mkdir "$LOCK_DIR" 2>/dev/null && return 0
    fi
    return 1
}

is_excluded() {
    local bid="$1" e
    for e in $EXCLUDE; do
        [ "$bid" = "$e" ] && return 0
    done
    return 1
}

# app-name sits last on purpose: should a name ever contain the separator, it
# cannot corrupt the fields in front of it.
windows_on() {
    aerospace list-windows --workspace "$1" \
        --format '%{window-id}|%{app-pid}|%{app-bundle-id}|%{app-name}' 2>>"$LOG_FILE"
}

live_pids() {
    aerospace list-windows --all --format '%{app-pid}' 2>/dev/null | sort -u
}

doctor() {
    echo "quit-workspace — self test"
    echo "  script:    $0"
    echo "  log:       $LOG_FILE"
    echo "  excluded:  $EXCLUDE"
    printf '  aerospace: %s\n' "$(command -v aerospace || echo MISSING)"
    if command -v aerospace >/dev/null 2>&1; then
        echo "  focused workspace: $(aerospace list-workspaces --focused 2>&1)"
        echo "  windows there:"
        windows_on focused | sed 's/^/    /'
    fi
}

main() {
    local now prev ws lines line wid pid bid name rounds closed skipped stuck
    local before after gone left

    # No arguments = invoked by keypress. Karabiner runs shell_commands
    # serially, so detach and release the keyboard queue right away.
    if [ "$#" -eq 0 ] && [ "${QUIT_WORKSPACE_CHILD:-0}" != "1" ]; then
        now="$(date +%s)"
        prev=0
        [ -f "$STAMP_FILE" ] && prev="$(cat "$STAMP_FILE" 2>/dev/null)"
        case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
        # A held key repeats; without this, one press quits a workspace twice.
        [ "$((now - prev))" -lt 2 ] && exit 0
        printf '%s' "$now" >"$STAMP_FILE" 2>/dev/null
        export QUIT_WORKSPACE_CHILD=1
        nohup "$0" >>"$LOG_FILE" 2>&1 &
        exit 0
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --doctor)    doctor; exit 0 ;;
            --dry-run)   DRY_RUN=1; shift ;;
            --force)     FORCE=1; shift ;;
            --workspace) WORKSPACE="${2:-}"; shift 2 ;;
            *)           log "unknown argument: $1"; exit 2 ;;
        esac
    done

    command -v aerospace >/dev/null 2>&1 || {
        log "aerospace not found in PATH"
        exit 1
    }

    acquire_lock || { log "already running — keypress ignored"; exit 0; }
    trap cleanup EXIT INT TERM

    ws="$WORKSPACE"
    [ -n "$ws" ] || ws="$(aerospace list-workspaces --focused 2>/dev/null)"
    [ -n "$ws" ] || { log "cannot determine workspace"; exit 1; }

    log "--- start (workspace $ws, pid $$) ---"

    lines="$(windows_on "$ws")"
    if [ -z "$lines" ]; then
        log "no windows on workspace $ws"
        exit 0
    fi

    before="$(live_pids)"
    TRIED="$(mktemp -t quitws)" || { log "cannot create temp file"; exit 1; }
    closed=0; skipped=0; stuck=0

    # The target list is taken ONCE, up front. Anything that appears later is a
    # dialog the close itself raised — a "Save changes?" sheet above all — and
    # closing that would throw away exactly the work this script promises to
    # protect. Only ids from this snapshot are ever touched.
    printf '%s\n' "$lines" >"$TRIED"

    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue

        wid="${line%%|*}"
        n="${line#*|}"; pid="${n%%|*}"
        n="${n#*|}";    bid="${n%%|*}"
        name="${n#*|}"

        if is_excluded "$bid"; then
            log "  skip (excluded): $name [$bid]"
            skipped=$((skipped + 1))
            continue
        fi

        if [ "$DRY_RUN" -eq 1 ]; then
            log "  [dry-run] would close window $wid — $name [$bid] pid $pid"
            closed=$((closed + 1))
            continue
        fi

        # Quitting one app can take several of its windows with it, so a window
        # from the snapshot may already be gone. That is success, not failure.
        if ! aerospace list-windows --all --format '%{window-id}' 2>/dev/null \
             | grep -qx "$wid"; then
            log "  window $wid already gone — $name"
            closed=$((closed + 1))
            continue
        fi

        if aerospace close --window-id "$wid" --quit-if-last-window 2>>"$LOG_FILE"; then
            log "  closed window $wid — $name"
            closed=$((closed + 1))
        else
            log "  STUCK window $wid — $name"
            stuck=$((stuck + 1))
        fi
    done <<EOF
$lines
EOF

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] $closed window(s) would close, $skipped skipped"
        exit 0
    fi

    # Apps need a moment to act on the close before the tally is meaningful.
    sleep 1
    after="$(live_pids)"
    gone="$(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -c .)"

    # Count only windows from the snapshot that are still standing. A save
    # dialog the close raised is new, belongs to the user, and is none of our
    # business — counting it would turn a correct refusal into a fake failure.
    left=0
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        wid="${line%%|*}"
        n="${line#*|}"; n="${n#*|}"; bid="${n%%|*}"
        # An excluded window was never a target, so it is not a leftover.
        is_excluded "$bid" && continue
        aerospace list-windows --all --format '%{window-id}' 2>/dev/null \
            | grep -qx "$wid" && left=$((left + 1))
    done <<EOF
$lines
EOF

    if [ "$FORCE" -eq 1 ] && [ "$left" -gt 0 ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -n "$line" ] || continue
            wid="${line%%|*}"
            n="${line#*|}"; pid="${n%%|*}"
            aerospace list-windows --all --format '%{window-id}' 2>/dev/null \
                | grep -qx "$wid" || continue
            log "  FORCE: SIGTERM pid $pid"
            kill -TERM "$pid" 2>/dev/null
        done <<EOF
$lines
EOF
        sleep 1
    fi

    log "result: $closed closed, $gone app(s) quit, $skipped skipped, $stuck stuck, $left window(s) left"
    exit 0
}

main "$@"
