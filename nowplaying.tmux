#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default options
tmux set-option -gq "@nowplaying_playing_icon" "♪ "
tmux set-option -gq "@nowplaying_paused_icon" ""
tmux set-option -gq "@nowplaying_stopped_icon" ""

# This is a simplified approach - we'll just create a command alias
# that tmux can use directly
nowplaying_cmd="#($CURRENT_DIR/scripts/nowplaying.sh)"

# Get current status-right value
status_right_value="$(tmux show-option -gqv status-right)"

# Replace #{nowplaying} with the actual command
if [[ "$status_right_value" == *"#{nowplaying}"* ]]; then
    new_status_right="${status_right_value//\#{nowplaying}/$nowplaying_cmd}"
    tmux set-option -g status-right "$new_status_right"
fi

# Get current status-left value
status_left_value="$(tmux show-option -gqv status-left)"

# Replace #{nowplaying} with the actual command
if [[ "$status_left_value" == *"#{nowplaying}"* ]]; then
    new_status_left="${status_left_value//\#{nowplaying}/$nowplaying_cmd}"
    tmux set-option -g status-left "$new_status_left"
fi