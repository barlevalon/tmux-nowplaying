#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source helper functions
if [ -f "$CURRENT_DIR/scripts/helpers.sh" ]; then
    source "$CURRENT_DIR/scripts/helpers.sh"
else
    echo "Error: helpers.sh not found" >&2
    exit 1
fi

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

# The interval management is now handled entirely in nowplaying.sh
# This ensures we properly track and restore the user's original interval