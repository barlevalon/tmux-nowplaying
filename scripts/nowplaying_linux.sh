#!/usr/bin/env bash

# Get now playing info using playerctl (MPRIS)
# This works with any Linux media player that supports MPRIS:
# Spotify, spotify-player, VLC, Firefox, Chrome, Rhythmbox, etc.

# Check if playerctl is available
if ! command -v playerctl &> /dev/null; then
    exit 0
fi

# Get the first player that is actually playing
# This handles multiple players and picks the active one
playing_player=""
for player in $(playerctl -l 2>/dev/null); do
    status=$(playerctl -p "$player" status 2>/dev/null)
    if [ "$status" = "Playing" ]; then
        playing_player="$player"
        break
    fi
done

# If we found a playing player, get its metadata
if [ -n "$playing_player" ]; then
    # Get metadata
    artist=$(playerctl -p "$playing_player" metadata artist 2>/dev/null)
    title=$(playerctl -p "$playing_player" metadata title 2>/dev/null)
    
    # Only output if we have both artist and title
    if [ -n "$artist" ] && [ -n "$title" ]; then
        echo "$artist - $title"
    elif [ -n "$title" ]; then
        # Some players only provide title
        echo "$title"
    fi
fi