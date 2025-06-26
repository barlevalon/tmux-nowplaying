#!/usr/bin/env bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get user options
PLAYING_ICON="$(tmux show-option -gqv "@nowplaying_playing_icon")"
PAUSED_ICON="$(tmux show-option -gqv "@nowplaying_paused_icon")"
STOPPED_ICON="$(tmux show-option -gqv "@nowplaying_stopped_icon")"

# Default icons if not set
PLAYING_ICON="${PLAYING_ICON:-♪ }"
PAUSED_ICON="${PAUSED_ICON:-}"
STOPPED_ICON="${STOPPED_ICON:-}"

# Get now playing info from Swift script
output="$("$SCRIPT_DIR/nowplaying_mediaremote.swift" 2>/dev/null)"

# If we got output, display it with the playing icon
if [ -n "$output" ]; then
    echo "${PLAYING_ICON}${output}"
fi