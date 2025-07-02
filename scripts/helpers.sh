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
    
    # Extract the visible portion efficiently
    # If we can get the whole substring without wrapping
    if [ $((start_pos + max_width)) -le "$padded_length" ]; then
        printf "%.*s\n" "$max_width" "${padded_text:$start_pos}"
    else
        # Need to wrap around - get first part and second part
        local first_part_len=$((padded_length - start_pos))
        local second_part_len=$((max_width - first_part_len))
        printf "%s%.*s\n" "${padded_text:$start_pos}" "$second_part_len" "$padded_text"
    fi
}

# Get current time in seconds for scrolling offset
get_scroll_offset() {
    local speed="$(get_tmux_option "@nowplaying_scroll_speed" "1")"
    # Bound speed between 1 and 10 to prevent overflow
    if [ "$speed" -lt 1 ]; then
        speed=1
    elif [ "$speed" -gt 10 ]; then
        speed=10
    fi
    # Use current seconds as base, multiply by speed for faster/slower scrolling
    echo $(($(date +%s) * speed))
}