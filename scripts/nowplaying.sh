#!/usr/bin/env bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
if [ -f "$SCRIPT_DIR/helpers.sh" ]; then
    source "$SCRIPT_DIR/helpers.sh"
else
    echo "Error: helpers.sh not found" >&2
    exit 1
fi

# Get user options
PLAYING_ICON="$(tmux show-option -gqv "@nowplaying_playing_icon")"
PAUSED_ICON="$(tmux show-option -gqv "@nowplaying_paused_icon")"
STOPPED_ICON="$(tmux show-option -gqv "@nowplaying_stopped_icon")"

# Default icons if not set
PLAYING_ICON="${PLAYING_ICON:-♪ }"
PAUSED_ICON="${PAUSED_ICON:-}"
STOPPED_ICON="${STOPPED_ICON:-}"

# Get scrolling options
SCROLLING_ENABLED="$(get_tmux_option "@nowplaying_scrolling_enabled" "no")"
SCROLLABLE_THRESHOLD="$(get_tmux_option "@nowplaying_scrollable_threshold" "30")"

# Validate threshold
if [ "$SCROLLABLE_THRESHOLD" -lt 1 ]; then
    SCROLLABLE_THRESHOLD=30
fi

# Store original interval if not already stored (only if scrolling is enabled)
if [ "$SCROLLING_ENABLED" == "yes" ]; then
    ORIGINAL_INTERVAL="$(get_tmux_option "@nowplaying_original_interval" "")"
    if [ -z "$ORIGINAL_INTERVAL" ]; then
        CURRENT_INTERVAL="$(tmux show-option -gqv status-interval)"
        if [ -n "$CURRENT_INTERVAL" ]; then
            tmux set-option -gq "@nowplaying_original_interval" "$CURRENT_INTERVAL"
            ORIGINAL_INTERVAL="$CURRENT_INTERVAL"
        else
            ORIGINAL_INTERVAL="15"  # tmux default
        fi
    fi
fi

# Get now playing info from Swift script
output="$("$SCRIPT_DIR/nowplaying_mediaremote.swift" 2>/dev/null)"

# Handle auto-interval adjustment
AUTO_INTERVAL="$(get_tmux_option "@nowplaying_auto_interval" "no")"

# If we got output, process and display it
if [ -n "$output" ]; then
    # Check if scrolling is needed
    output_length="${#output}"
    
    # Only manage intervals if scrolling is enabled
    if [ "$SCROLLING_ENABLED" == "yes" ] && [ "$AUTO_INTERVAL" == "yes" ]; then
        if [ "$output_length" -gt "$SCROLLABLE_THRESHOLD" ]; then
            # Set faster interval for scrolling
            PLAYING_INTERVAL="$(get_tmux_option "@nowplaying_playing_interval" "1")"
            tmux set-option -g status-interval "$PLAYING_INTERVAL"
        else
            # Restore original interval when not scrolling
            tmux set-option -g status-interval "$ORIGINAL_INTERVAL"
        fi
    fi
    
    if [ "$SCROLLING_ENABLED" == "yes" ] && [ "$output_length" -gt "$SCROLLABLE_THRESHOLD" ]; then
        # Get scroll offset based on current time
        offset="$(get_scroll_offset)"
        scrolled_output="$(scrolling_text "$output" "$SCROLLABLE_THRESHOLD" "$offset")"
        echo "${PLAYING_ICON}${scrolled_output}"
    else
        echo "${PLAYING_ICON}${output}"
    fi
else
    # No music playing - restore original interval
    if [ "$SCROLLING_ENABLED" == "yes" ] && [ "$AUTO_INTERVAL" == "yes" ]; then
        tmux set-option -g status-interval "$ORIGINAL_INTERVAL"
    fi
fi