#!/usr/bin/env bash

# Get now playing info using playerctl (MPRIS).
# Adapter output format: status<TAB>artist<TAB>title.

if ! command -v playerctl >/dev/null 2>&1; then
    exit 0
fi

selected_player=""
selected_status=""

# Prefer an actively playing player, then fall back to paused/stopped players
# that still expose metadata.
while IFS= read -r player; do
    status="$(playerctl -p "$player" status 2>/dev/null)"
    case "$status" in
        Playing)
            selected_player="$player"
            selected_status="$status"
            break
            ;;
        Paused)
            if [ -z "$selected_player" ] || [ "$selected_status" = "Stopped" ]; then
                selected_player="$player"
                selected_status="$status"
            fi
            ;;
        Stopped)
            if [ -z "$selected_player" ]; then
                selected_player="$player"
                selected_status="$status"
            fi
            ;;
    esac
done < <(playerctl -l 2>/dev/null)

if [ -z "$selected_player" ]; then
    exit 0
fi

separator=$'\034'
snapshot="$(playerctl -p "$selected_player" metadata --format "{{status}}${separator}{{artist}}${separator}{{title}}" 2>/dev/null)" || exit 0

if [[ "$snapshot" != *"$separator"* ]]; then
    exit 0
fi
status="${snapshot%%"$separator"*}"
remainder="${snapshot#*"$separator"}"
if [[ "$remainder" != *"$separator"* ]]; then
    exit 0
fi
artist="${remainder%%"$separator"*}"
title="${remainder#*"$separator"}"
if [[ "$title" == *"$separator"* ]]; then
    exit 0
fi

case "$status" in
    Playing|Paused|Stopped) ;;
    *) exit 0 ;;
esac

artist="${artist//$'\t'/ }"
artist="${artist//$'\r'/ }"
artist="${artist//$'\n'/ }"
title="${title//$'\t'/ }"
title="${title//$'\r'/ }"
title="${title//$'\n'/ }"

if [ -n "$artist" ] || [ -n "$title" ]; then
    printf '%s\t%s\t%s\n' "$status" "$artist" "$title"
fi
