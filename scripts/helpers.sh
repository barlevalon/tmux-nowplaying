#!/usr/bin/env bash

# Helper functions for tmux-nowplaying

# Get tmux option with default value
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value

    if option_value="$(tmux show-option -v "$option" 2>/dev/null)"; then
        printf '%s\n' "$option_value"
    elif option_value="$(tmux show-option -gv "$option" 2>/dev/null)"; then
        printf '%s\n' "$option_value"
    else
        printf '%s\n' "$default_value"
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
    local default_value

    default_value="$(get_nowplaying_default_option "$option")" || default_value=""
    get_tmux_integer_option "$option" "$default_value" "$min_value" "$max_value"
}

# Format metadata from a platform adapter into display text.
format_nowplaying_metadata() {
    local artist="$1"
    local title="$2"

    if [ -n "$artist" ] && [ -n "$title" ]; then
        printf '%s - %s\n' "$artist" "$title"
    elif [ -n "$artist" ]; then
        printf '%s\n' "$artist"
    elif [ -n "$title" ]; then
        printf '%s\n' "$title"
    fi
}

# Get icon for a playback status.
get_nowplaying_status_icon() {
    case "$1" in
        Paused) get_nowplaying_option "@nowplaying_paused_icon" ;;
        Stopped) get_nowplaying_option "@nowplaying_stopped_icon" ;;
        *) get_nowplaying_option "@nowplaying_playing_icon" ;;
    esac
}

# Parse adapter output.
# Adapter format: status<TAB>artist<TAB>title.
parse_nowplaying_adapter_output() {
    local adapter_output_value="$1"
    local status_output_name="$2"
    local artist_output_name="$3"
    local title_output_name="$4"
    local parsed_status
    local adapter_remainder
    local parsed_artist
    local parsed_title

    printf -v "$status_output_name" '%s' ''
    printf -v "$artist_output_name" '%s' ''
    printf -v "$title_output_name" '%s' ''

    case "$adapter_output_value" in
        *$'\n'*|*$'\r'*) return 1 ;;
    esac

    if [[ "$adapter_output_value" != *$'\t'* ]]; then
        return 1
    fi

    parsed_status="${adapter_output_value%%$'\t'*}"
    adapter_remainder="${adapter_output_value#*$'\t'}"

    case "$parsed_status" in
        Playing|Paused|Stopped) ;;
        *) return 1 ;;
    esac

    if [[ "$adapter_remainder" != *$'\t'* ]]; then
        return 1
    fi

    parsed_artist="${adapter_remainder%%$'\t'*}"
    parsed_title="${adapter_remainder#*$'\t'}"

    if [[ "$parsed_title" == *$'\t'* ]]; then
        return 1
    fi

    printf -v "$status_output_name" '%s' "$parsed_status"
    printf -v "$artist_output_name" '%s' "$parsed_artist"
    printf -v "$title_output_name" '%s' "$parsed_title"
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
    # Duplicating the text handles slices that cross the scroll cycle boundary.
    local padded_text="${text}${padding}${text}"

    # Calculate the starting position based on offset
    local start_pos=$((offset % (text_length + ${#padding})))

    printf '%.*s\n' "$max_width" "${padded_text:$start_pos}"
}

# Get current time in seconds for scrolling offset
get_scroll_offset() {
    local speed
    speed="$(get_nowplaying_integer_option "@nowplaying_scroll_speed" "1" "10")"
    # Use current seconds as base, multiply by speed for faster/slower scrolling
    echo $(($(date +%s) * speed))
}
