#!/usr/bin/env bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "$SCRIPT_DIR/helpers.sh"

# Get user options
PLAYING_ICON="$(tmux show-option -gqv "@nowplaying_playing_icon")"
PAUSED_ICON="$(tmux show-option -gqv "@nowplaying_paused_icon")"
STOPPED_ICON="$(tmux show-option -gqv "@nowplaying_stopped_icon")"

# Default icons if not set
PLAYING_ICON="${PLAYING_ICON:-♪ }"
PAUSED_ICON="${PAUSED_ICON:-}"
STOPPED_ICON="${STOPPED_ICON:-}"

# Get scrolling options
SCROLLABLE_THRESHOLD="$(get_tmux_option "@nowplaying_scrollable_threshold" "30")"
SCROLLABLE_FORMAT="$(get_tmux_option "@nowplaying_scrollable_format" "{artist} - {title}")"

# Get now playing info from Swift script
output="$("$SCRIPT_DIR/nowplaying_mediaremote.swift" 2>/dev/null)"

# If we got output, process and display it
if [ -n "$output" ]; then
    # Check if scrolling is needed
    output_length="${#output}"
    
    if [ "$output_length" -gt "$SCROLLABLE_THRESHOLD" ]; then
        # Get scroll offset based on current time
        offset="$(get_scroll_offset)"
        scrolled_output="$(scrolling_text "$output" "$SCROLLABLE_THRESHOLD" "$offset")"
        echo "${PLAYING_ICON}${scrolled_output}"
    else
        echo "${PLAYING_ICON}${output}"
    fi
fi