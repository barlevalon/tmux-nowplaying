#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source helper functions
if [ -f "$CURRENT_DIR/scripts/helpers.sh" ]; then
    source "$CURRENT_DIR/scripts/helpers.sh"
else
    echo "Error: helpers.sh not found" >&2
    exit 1
fi

nowplaying_command="#(\"${CURRENT_DIR}/scripts/nowplaying.sh\")"

for status_option in status-left status-right; do
    status_value="$(tmux show-option -gqv "$status_option")"
    if [[ "$status_value" == *'#{nowplaying}'* ]]; then
        updated_value="${status_value//\#\{nowplaying\}/$nowplaying_command}"
        tmux set-option -g "$status_option" "$updated_value"
    fi
done
