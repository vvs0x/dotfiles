#!/bin/bash
#
# finder-shortcuts.sh — registers the Finder App Shortcuts that the Karabiner
# rules rely on.
#
# Why this detour exists: Finder's "Back" is bound to ⌘[. Karabiner sends
# hardware key codes, and macOS turns those into characters via the active
# layout — on Swiss German "[" sits on ⌥5, so a synthesized ⌘+open_bracket
# arrives as ⌘ü and never matches the menu item. A macOS App Shortcut binds to
# the menu item's *title* instead, which is layout independent. Karabiner
# sends the chord below, Finder resolves it through the title.
#
#   ./finder-shortcuts.sh            apply the shortcuts
#   ./finder-shortcuts.sh --remove   drop them again
#   ./finder-shortcuts.sh --show     print what is currently registered
#
# Add --no-restart to keep your open Finder windows; the setting is only read
# at launch, so it takes effect after the next restart either way.
#
# Modifier prefixes in the value: @ = command, ^ = control, ~ = option,
# $ = shift. "@^~b" is therefore ⌘⌃⌥B — which is also caps_lock+b, since
# caps_lock is remapped to ⌘⌃⌥.

set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

CHORD_BACK="@^~b"

# The title has to match Finder's menu exactly, so the entry is written for
# every UI language this machine might run in. An entry whose title no Finder
# menu carries is simply ignored, so the extras cost nothing.
TITLES_BACK="Back Zurück Retour Indietro"

RESTART=1
ACTION="apply"

for arg in "$@"; do
    case "$arg" in
        --remove)     ACTION="remove" ;;
        --show)       ACTION="show" ;;
        --no-restart) RESTART=0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

show() {
    echo "Finder App Shortcuts (com.apple.finder NSUserKeyEquivalents):"
    defaults read com.apple.finder NSUserKeyEquivalents 2>/dev/null \
        || echo "  (none registered)"
}

case "$ACTION" in
    show)
        show
        exit 0
        ;;
    apply)
        for title in $TITLES_BACK; do
            defaults write com.apple.finder NSUserKeyEquivalents \
                -dict-add "$title" "$CHORD_BACK" || exit 1
        done
        echo "registered: Back -> ⌘⌃⌥B"
        ;;
    remove)
        for title in $TITLES_BACK; do
            defaults delete com.apple.finder NSUserKeyEquivalents "$title" 2>/dev/null
        done
        # An empty dictionary would keep sitting in the plist for no reason.
        if [ -z "$(defaults read com.apple.finder NSUserKeyEquivalents 2>/dev/null | sed -n '2p')" ]; then
            defaults delete com.apple.finder NSUserKeyEquivalents 2>/dev/null
        fi
        echo "removed"
        ;;
esac

if [ "$RESTART" -eq 1 ]; then
    echo "restarting Finder so it picks the setting up ..."
    killall Finder 2>/dev/null
else
    echo "Finder not restarted — the change applies after its next launch."
fi
