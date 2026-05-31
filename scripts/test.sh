#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$actual" != "$expected" ]]; then
        printf 'not ok - %s\nexpected: <%s>\nactual:   <%s>\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi

    printf 'ok - %s\n' "$message"
}

write_tmux_mock() {
    cat > "${TMP_DIR}/tmux" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "show-option" ]]; then
    option="${@: -1}"
    case "$option" in
        @nowplaying_playing_icon) printf '♪ ' ;;
        @nowplaying_paused_icon) printf '⏸ ' ;;
        @nowplaying_stopped_icon) printf '⏹ ' ;;
        @nowplaying_scrolling_enabled) printf 'no' ;;
        @nowplaying_scrollable_threshold) printf '50' ;;
        @nowplaying_scroll_speed) printf '1' ;;
        @nowplaying_scroll_padding) printf '   ' ;;
        @nowplaying_auto_interval) printf 'no' ;;
        @nowplaying_playing_interval) printf '1' ;;
        @bad_integer) printf 'abc' ;;
        @high_integer) printf '99' ;;
        @low_integer) printf '0' ;;
    esac
elif [[ "$1 $2" == "set-option -g" || "$1 $2" == "set-option -gq" ]]; then
    :
fi
MOCK
    chmod +x "${TMP_DIR}/tmux"
}

write_uname_mock() {
    cat > "${TMP_DIR}/uname" <<'MOCK'
#!/usr/bin/env bash
printf 'Linux\n'
MOCK
    chmod +x "${TMP_DIR}/uname"
}

write_playerctl_mock() {
    local mode="$1"

    cat > "${TMP_DIR}/playerctl" <<MOCK
#!/usr/bin/env bash
case "\$*" in
MOCK

    case "$mode" in
        playing)
            cat >> "${TMP_DIR}/playerctl" <<'MOCK'
    '-l') printf 'paused
playing
' ;;
    '-p paused status') printf 'Paused
' ;;
    '-p playing status') printf 'Playing
' ;;
    '-p paused metadata artist') printf 'Old
' ;;
    '-p paused metadata title') printf 'Track
' ;;
    '-p playing metadata artist') printf 'Artist
' ;;
    '-p playing metadata title') printf 'Title
' ;;
MOCK
            ;;
        paused)
            cat >> "${TMP_DIR}/playerctl" <<'MOCK'
    '-l') printf 'paused
' ;;
    '-p paused status') printf 'Paused
' ;;
    '-p paused metadata artist') printf 'Old
' ;;
    '-p paused metadata title') printf 'Track
' ;;
MOCK
            ;;
        stopped)
            cat >> "${TMP_DIR}/playerctl" <<'MOCK'
    '-l') printf 'stopped
' ;;
    '-p stopped status') printf 'Stopped
' ;;
    '-p stopped metadata artist') printf 'Done
' ;;
    '-p stopped metadata title') printf 'Song
' ;;
MOCK
            ;;
        empty)
            cat >> "${TMP_DIR}/playerctl" <<'MOCK'
    '-l') printf '' ;;
MOCK
            ;;
        *) fail "unknown playerctl mock mode: ${mode}" ;;
    esac

    cat >> "${TMP_DIR}/playerctl" <<'MOCK'
esac
MOCK
    chmod +x "${TMP_DIR}/playerctl"
}

run_with_mocks() {
    PATH="${TMP_DIR}:${PATH}" "$@"
}

bash -n "${ROOT_DIR}/nowplaying.tmux" "${ROOT_DIR}"/scripts/*.sh
printf 'ok - bash syntax\n'

write_tmux_mock

helper_output="$(PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; printf "%s %s %s\n" "$(get_tmux_integer_option @bad_integer 50 4)" "$(get_tmux_integer_option @low_integer 50 4)" "$(get_tmux_integer_option @high_integer 1 1 10)"' _ "${ROOT_DIR}/scripts/helpers.sh")"
assert_eq "50 4 10" "$helper_output" "integer option validation"

parse_output="$(PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; parse_nowplaying_adapter_output $'"'"'Paused\tArtist\tTitle'"'"'' _ "${ROOT_DIR}/scripts/helpers.sh")"
assert_eq $'Paused\tArtist - Title' "$parse_output" "adapter output parsing"

write_uname_mock

write_playerctl_mock playing
assert_eq $'Playing\tArtist\tTitle' "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh")" "linux adapter prefers playing player"
assert_eq "♪ Artist - Title" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders playing metadata"

write_playerctl_mock paused
assert_eq "⏸ Old - Track" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders paused metadata"

write_playerctl_mock stopped
assert_eq "⏹ Done - Song" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders stopped metadata"

write_playerctl_mock empty
assert_eq "" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders empty output without metadata"

printf 'all tests passed\n'
