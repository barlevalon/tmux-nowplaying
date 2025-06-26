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