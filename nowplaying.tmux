#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source helper functions
if [ -f "$CURRENT_DIR/scripts/helpers.sh" ]; then
    source "$CURRENT_DIR/scripts/helpers.sh"
else
    echo "Error: helpers.sh not found" >&2
    exit 1
fi

# Default options (only set if not already defined)
if [ -z "$(tmux show-option -gqv "@nowplaying_playing_icon")" ]; then
    tmux set-option -g "@nowplaying_playing_icon" "♪ "
fi
if [ -z "$(tmux show-option -gqv "@nowplaying_paused_icon")" ]; then
    tmux set-option -g "@nowplaying_paused_icon" ""
fi
if [ -z "$(tmux show-option -gqv "@nowplaying_stopped_icon")" ]; then
    tmux set-option -g "@nowplaying_stopped_icon" ""
fi

# Default scrolling options (only set if not already defined)
if [ -z "$(tmux show-option -gqv "@nowplaying_scrolling_enabled")" ]; then
    tmux set-option -g "@nowplaying_scrolling_enabled" "no"
fi
if [ -z "$(tmux show-option -gqv "@nowplaying_scrollable_threshold")" ]; then
    tmux set-option -g "@nowplaying_scrollable_threshold" "30"
fi
if [ -z "$(tmux show-option -gqv "@nowplaying_scroll_speed")" ]; then
    tmux set-option -g "@nowplaying_scroll_speed" "1"
fi
if [ -z "$(tmux show-option -gqv "@nowplaying_scroll_padding")" ]; then
    tmux set-option -g "@nowplaying_scroll_padding" "   "
fi
if [ -z "$(tmux show-option -gqv "@nowplaying_auto_interval")" ]; then
    tmux set-option -g "@nowplaying_auto_interval" "no"
fi
if [ -z "$(tmux show-option -gqv "@nowplaying_playing_interval")" ]; then
    tmux set-option -g "@nowplaying_playing_interval" "1"
fi

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