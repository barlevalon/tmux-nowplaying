#!/usr/bin/env bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_TARGET="${1:-}"

# Source helper functions
if [ -f "$SCRIPT_DIR/helpers.sh" ]; then
    # shellcheck source=scripts/helpers.sh
    source "$SCRIPT_DIR/helpers.sh"
else
    echo "Error: helpers.sh not found" >&2
    exit 1
fi

# Get scrolling options
SCROLLING_ENABLED="$(get_nowplaying_option "@nowplaying_scrolling_enabled")"
SCROLLABLE_THRESHOLD="$(get_nowplaying_integer_option "@nowplaying_scrollable_threshold" "4")"

# Get now playing info based on OS
case "$(uname -s)" in
    Darwin)
        # macOS - use Swift MediaRemote
        output="$("$SCRIPT_DIR/nowplaying_mediaremote.swift" 2>/dev/null)"
        ;;
    Linux)
        # Linux - use playerctl (MPRIS)
        output="$("$SCRIPT_DIR/nowplaying_linux.sh" 2>/dev/null)"
        ;;
    *)
        # Unsupported OS
        output=""
        ;;
esac

playback_status=""
track_artist=""
track_title=""
track_text=""

# If we got output, process and display it
if [ -n "$output" ] && parse_nowplaying_adapter_output "$output" playback_status track_artist track_title; then
    track_text="$(format_nowplaying_metadata "$track_artist" "$track_title")"
fi

output_length="${#track_text}"

if [ -n "$track_text" ]; then
    status_icon="$(get_nowplaying_status_icon "$playback_status")"

    # Check if scrolling is needed
    if [ "$output_length" -gt "$SCROLLABLE_THRESHOLD" ]; then
        if [ "$SCROLLING_ENABLED" == "yes" ]; then
            if [ -n "$CLIENT_TARGET" ] && [ "$(get_nowplaying_option "@nowplaying_auto_interval")" == "yes" ]; then
                playing_interval="$(get_nowplaying_integer_option "@nowplaying_playing_interval" "1")"
                (sleep "$playing_interval"; tmux refresh-client -t "$CLIENT_TARGET" -S) >/dev/null 2>&1 &
            fi

            # Get scroll offset based on current time
            offset="$(get_scroll_offset)"
            scrolled_output="$(scrolling_text "$track_text" "$SCROLLABLE_THRESHOLD" "$offset")"
            echo "${status_icon}${scrolled_output}"
        else
            # Truncate with ellipsis when scrolling is disabled
            truncated="${track_text:0:$((SCROLLABLE_THRESHOLD - 3))}..."
            echo "${status_icon}${truncated}"
        fi
    else
        echo "${status_icon}${track_text}"
    fi
fi
