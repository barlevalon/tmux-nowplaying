#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

nowplaying_command="#(\"${CURRENT_DIR}/scripts/nowplaying.sh\" \"#{client_name}\")"

for status_option in status-left status-right; do
    status_value="$(tmux show-option -gqv "$status_option")"
    if [[ "$status_value" == *'#{nowplaying}'* ]]; then
        updated_value="${status_value//\#\{nowplaying\}/$nowplaying_command}"
        tmux set-option -g "$status_option" "$updated_value"
    fi
done
