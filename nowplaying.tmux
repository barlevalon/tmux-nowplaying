#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default options
tmux set-option -gq "@nowplaying_playing_icon" "♪ "
tmux set-option -gq "@nowplaying_paused_icon" ""
tmux set-option -gq "@nowplaying_stopped_icon" ""

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