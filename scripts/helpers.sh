#!/usr/bin/env bash

# Helper functions for tmux-nowplaying

# Get tmux option with default value
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value="$(tmux show-option -qv "$option")"
    if [ -z "$option_value" ]; then
        option_value="$(tmux show-option -gqv "$option")"
    fi
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# Print the built-in default for a nowplaying tmux option.
get_nowplaying_default_option() {
    case "$1" in
        "@nowplaying_playing_icon") printf '%s\n' "♪ " ;;
        "@nowplaying_paused_icon") printf '%s\n' "" ;;
        "@nowplaying_stopped_icon") printf '%s\n' "" ;;
        "@nowplaying_scrolling_enabled") printf '%s\n' "no" ;;
        "@nowplaying_scrollable_threshold") printf '%s\n' "50" ;;
        "@nowplaying_scroll_speed") printf '%s\n' "1" ;;
        "@nowplaying_scroll_padding") printf '%s\n' "   " ;;
        "@nowplaying_auto_interval") printf '%s\n' "no" ;;
        "@nowplaying_playing_interval") printf '%s\n' "1" ;;
        *) return 1 ;;
    esac
}

# Set every nowplaying tmux option default without overriding user values.
set_nowplaying_default_options() {
    local option
    for option in \
        "@nowplaying_playing_icon" \
        "@nowplaying_paused_icon" \
        "@nowplaying_stopped_icon" \
        "@nowplaying_scrolling_enabled" \
        "@nowplaying_scrollable_threshold" \
        "@nowplaying_scroll_speed" \
        "@nowplaying_scroll_padding" \
        "@nowplaying_auto_interval" \
        "@nowplaying_playing_interval"
    do
        if [ -z "$(tmux show-option -gqv "$option")" ]; then
            tmux set-option -g "$option" "$(get_nowplaying_default_option "$option")"
        fi
    done
}

# Get a nowplaying tmux option with its built-in default.
get_nowplaying_option() {
    local option="$1"
    local default_value

    default_value="$(get_nowplaying_default_option "$option")" || default_value=""
    get_tmux_option "$option" "$default_value"
}

# Get integer tmux option, clamped to optional min/max bounds.
get_tmux_integer_option() {
    local option="$1"
    local default_value="$2"
    local min_value="${3:-}"
    local max_value="${4:-}"
    local option_value

    option_value="$(get_tmux_option "$option" "$default_value")"

    if [[ ! "$option_value" =~ ^[0-9]+$ ]]; then
        option_value="$default_value"
    fi
    if [[ -n "$min_value" && "$option_value" -lt "$min_value" ]]; then
        option_value="$min_value"
    fi
    if [[ -n "$max_value" && "$option_value" -gt "$max_value" ]]; then
        option_value="$max_value"
    fi

    echo "$option_value"
}

# Get integer nowplaying option with its built-in default.
get_nowplaying_integer_option() {
    local option="$1"
    local min_value="${2:-}"
    local max_value="${3:-}"

    get_tmux_integer_option "$option" "$(get_nowplaying_option "$option")" "$min_value" "$max_value"
}

# Get the tmux status interval to restore after temporary scrolling changes.
get_nowplaying_original_interval() {
    local original_interval
    local current_interval

    original_interval="$(get_tmux_option "@nowplaying_original_interval" "")"
    if [ -n "$original_interval" ]; then
        echo "$original_interval"
        return
    fi

    current_interval="$(tmux show-option -gqv status-interval)"
    if [ -n "$current_interval" ]; then
        tmux set-option -gq "@nowplaying_original_interval" "$current_interval" >/dev/null
        echo "$current_interval"
    else
        echo "15"
    fi
}

# Temporarily lower status-interval for scrolling output, or restore it.
update_nowplaying_status_interval() {
    local output_length="$1"
    local scrollable_threshold="$2"
    local scrolling_enabled
    local auto_interval
    local original_interval
    local playing_interval

    scrolling_enabled="$(get_nowplaying_option "@nowplaying_scrolling_enabled")"
    auto_interval="$(get_nowplaying_option "@nowplaying_auto_interval")"

    if [ "$scrolling_enabled" != "yes" ] || [ "$auto_interval" != "yes" ]; then
        return
    fi

    original_interval="$(get_nowplaying_original_interval)"

    if [ "$output_length" -gt "$scrollable_threshold" ]; then
        playing_interval="$(get_nowplaying_integer_option "@nowplaying_playing_interval" "1")"
        tmux set-option -g status-interval "$playing_interval"
    else
        tmux set-option -g status-interval "$original_interval"
    fi
}

# Restore status-interval when there is no renderable track.
restore_nowplaying_status_interval() {
    update_nowplaying_status_interval 0 1
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
    local padding
    padding="$(get_nowplaying_option "@nowplaying_scroll_padding")"
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
    local speed
    speed="$(get_nowplaying_integer_option "@nowplaying_scroll_speed" "1" "10")"
    # Use current seconds as base, multiply by speed for faster/slower scrolling
    echo $(($(date +%s) * speed))
}
