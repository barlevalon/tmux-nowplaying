#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source helper functions
source "$CURRENT_DIR/scripts/helpers.sh"

# Default options
tmux set-option -gq "@nowplaying_playing_icon" "♪ "
tmux set-option -gq "@nowplaying_paused_icon" ""
tmux set-option -gq "@nowplaying_stopped_icon" ""

# Default scrolling options
tmux set-option -gq "@nowplaying_scrollable_threshold" "30"
tmux set-option -gq "@nowplaying_scrollable_format" "{artist} - {title}"
tmux set-option -gq "@nowplaying_scroll_speed" "1"
tmux set-option -gq "@nowplaying_scroll_padding" "   "
tmux set-option -gq "@nowplaying_auto_interval" "yes"
tmux set-option -gq "@nowplaying_playing_interval" "1"

# Create the interpolation function
nowplaying_interpolation() {
    local string="$1"
    local nowplaying_cmd="#($CURRENT_DIR/scripts/nowplaying.sh)"
    
    # Use | as delimiter instead of / to avoid conflicts with file paths
    echo "$string" | sed "s|#{nowplaying}|${nowplaying_cmd}|g"
}

# Update status-right
status_right_value="$(tmux show-option -gqv status-right)"
# Only update if it contains the interpolation string and doesn't already have our script
if [[ "$status_right_value" == *"#{nowplaying}"* ]] && [[ "$status_right_value" != *"nowplaying.sh"* ]]; then
    new_status_right="$(nowplaying_interpolation "$status_right_value")"
    tmux set-option -g status-right "$new_status_right"
fi

# Update status-left  
status_left_value="$(tmux show-option -gqv status-left)"
# Only update if it contains the interpolation string and doesn't already have our script
if [[ "$status_left_value" == *"#{nowplaying}"* ]] && [[ "$status_left_value" != *"nowplaying.sh"* ]]; then
    new_status_left="$(nowplaying_interpolation "$status_left_value")"
    tmux set-option -g status-left "$new_status_left"
fi

# Set up automatic interval adjustment if enabled
if [[ "$(get_tmux_option "@nowplaying_auto_interval" "no")" == "yes" ]]; then
    # Check if music is playing and if text needs scrolling
    output="$("$CURRENT_DIR/scripts/nowplaying_mediaremote.swift" 2>/dev/null)"
    if [ -n "$output" ]; then
        output_length="${#output}"
        threshold="$(get_tmux_option "@nowplaying_scrollable_threshold" "30")"
        
        if [ "$output_length" -gt "$threshold" ]; then
            # Set faster interval for scrolling
            interval="$(get_tmux_option "@nowplaying_playing_interval" "1")"
            tmux set-option -g status-interval "$interval"
        fi
    fi
fi