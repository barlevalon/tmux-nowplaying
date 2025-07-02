#!/usr/bin/env bash

# Helper functions for tmux-nowplaying-macos plugin

# Get tmux version
_tmux_version() {
    tmux -V | cut -d ' ' -f 2
}

# Check if tmux version is >= 2.9
_tmux_version_ok() {
    [[ "$(_tmux_version)" == 2.9* ]] || [[ "$(_tmux_version)" == 3.* ]]
}

# Get tmux option with default value
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value="$(tmux show-option -qv "$option")"
    if [ -z "$option_value" ]; then
        option_value="$(tmux show-option -gqv "$option")"
    fi
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# Scrolling text function
# Arguments:
#   $1 - text to scroll
#   $2 - maximum width before scrolling
#   $3 - offset for scrolling position
scrolling_text() {
    local text="$1"
    local max_width="$2"
    local offset="$3"
    local text_length="${#text}"
    
    # If text fits within max_width, return as-is
    if [ "$text_length" -le "$max_width" ]; then
        echo "$text"
        return
    fi
    
    # Get padding from tmux option
    local padding="$(get_tmux_option "@nowplaying_scroll_padding" "   ")"
    local padded_text="${text}${padding}${text}"
    local padded_length="${#padded_text}"
    
    # Calculate the starting position based on offset
    local start_pos=$((offset % (text_length + ${#padding})))
    
    # Extract the visible portion
    local visible=""
    local chars_needed="$max_width"
    local pos="$start_pos"
    
    while [ "$chars_needed" -gt 0 ]; do
        if [ "$pos" -ge "$padded_length" ]; then
            pos=0
        fi
        visible="${visible}${padded_text:$pos:1}"
        ((pos++))
        ((chars_needed--))
    done
    
    echo "$visible"
}

# Get current time in seconds for scrolling offset
get_scroll_offset() {
    local speed="$(get_tmux_option "@nowplaying_scroll_speed" "1")"
    # Use current seconds as base, multiply by speed for faster/slower scrolling
    echo $(($(date +%s) * speed))
}