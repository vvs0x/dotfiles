#!/bin/bash
#
# finder-back.sh — navigates the front Finder window back one step.
#
# Why a script instead of just sending ⌘[: Karabiner sends hardware key codes,
# macOS turns those into characters via the active layout. On Swiss German "["
# sits on ⌥5, so a synthesized ⌘+open_bracket arrives as ⌘ü and never matches
# the menu item. Clicking the menu item itself sidesteps the layout entirely.
#
# Needs Accessibility permission for whoever runs it (Karabiner, or the
# terminal when testing). Without it macOS refuses the click — the script says
# so in the log instead of failing silently.
#
#   --doctor   reports whether the permission is in place

set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

if [ -z "${HOME:-}" ]; then
    HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    [ -n "$HOME" ] || HOME="/tmp"
    export HOME
fi

LOG_FILE="${FINDER_BACK_LOG:-$HOME/.local/state/finder-back/finder-back.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
: >>"$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/finder-back.log"

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null
    [ -t 1 ] && printf '%s\n' "$*"
    return 0
}

# The Go menu is addressed by name where possible and by position otherwise,
# so the script survives both a UI language switch and a renamed menu.
click_back() {
    osascript <<'OSA' 2>&1
on run
    tell application "System Events"
        tell process "Finder"
            set goMenu to missing value
            repeat with candidate in {"Go", "Gehe zu", "Aller", "Vai"}
                try
                    set goMenu to menu bar item candidate of menu bar 1
                    exit repeat
                end try
            end repeat
            if goMenu is missing value then
                set goMenu to menu bar item 6 of menu bar 1
            end if
            click menu item 1 of menu 1 of goMenu
        end tell
    end tell
    return "clicked"
end run
OSA
}

case "${1:-}" in
    --doctor)
        printf 'Accessibility for this process: '
        osascript -e 'tell application "System Events" to return UI elements enabled' 2>&1
        echo "Log: $LOG_FILE"
        ;;
esac

out="$(click_back)"
rc=$?
if [ "$rc" -ne 0 ] || [ "$out" != "clicked" ]; then
    log "FAILED (exit $rc): $out"
    exit 1
fi
log "back"
exit 0
