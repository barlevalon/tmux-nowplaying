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

artist="$(playerctl -p "$selected_player" metadata artist 2>/dev/null)"
title="$(playerctl -p "$selected_player" metadata title 2>/dev/null)"

if [ -n "$artist" ] || [ -n "$title" ]; then
    printf '%s\t%s\t%s\n' "$selected_status" "$artist" "$title"
fi
