#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
REAL_TMUX=""
TMUX_TEST_SERVER=""

cleanup() {
    if [[ -n "$REAL_TMUX" && -n "$TMUX_TEST_SERVER" ]]; then
        "$REAL_TMUX" -L "$TMUX_TEST_SERVER" kill-server 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

assert_adapter_record() {
    local adapter_output="$1"
    local expected_status="$2"
    local expected_artist="$3"
    local expected_title="$4"
    local message="$5"
    local playback_status="stale"
    local track_artist="stale"
    local track_title="stale"

    if ! parse_nowplaying_adapter_output "$adapter_output" playback_status track_artist track_title; then
        fail "${message} was rejected"
    fi

    assert_eq "$expected_status" "$playback_status" "${message} status"
    assert_eq "$expected_artist" "$track_artist" "${message} artist"
    assert_eq "$expected_title" "$track_title" "${message} title"
}

assert_adapter_rejected() {
    local adapter_output="$1"
    local message="$2"
    local playback_status="stale"
    local track_artist="stale"
    local track_title="stale"

    if parse_nowplaying_adapter_output "$adapter_output" playback_status track_artist track_title; then
        fail "${message} was accepted"
    fi

    assert_eq "" "$playback_status" "${message} clears status"
    assert_eq "" "$track_artist" "${message} clears artist"
    assert_eq "" "$track_title" "${message} clears title"
}

assert_scrolling_text() {
    local expected="$1"
    local text="$2"
    local width="$3"
    local padding="$4"
    local offset="$5"
    local message="$6"
    local actual

    actual="$(bash -c '
        source "$1"
        scroll_padding="$5"
        get_nowplaying_option() { printf "%s" "$scroll_padding"; }
        scrolling_text "$2" "$3" "$4"
    ' _ "${ROOT_DIR}/scripts/helpers.sh" "$text" "$width" "$offset" "$padding")"
    assert_eq "$expected" "$actual" "$message"
}

write_tmux_mock() {
    cat > "${TMP_DIR}/tmux" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "show-option" ]]; then
    option="${@: -1}"
    scope="local"
    if [[ " $* " == *" -gv "* || " $* " == *" -gqv "* ]]; then
        scope="global"
    fi

    case "$scope:$option" in
        global:@nowplaying_playing_icon) printf '♪ ' ;;
        global:@nowplaying_paused_icon) printf '⏸ ' ;;
        global:@nowplaying_stopped_icon) printf '⏹ ' ;;
        global:@nowplaying_scrolling_enabled) printf 'no' ;;
        global:@nowplaying_scrollable_threshold) printf '50' ;;
        global:@nowplaying_scroll_speed) printf '1' ;;
        global:@nowplaying_scroll_padding) printf '   ' ;;
        global:@nowplaying_auto_interval) printf 'no' ;;
        global:@nowplaying_playing_interval) printf '1' ;;
        global:@bad_integer) printf 'abc' ;;
        global:@empty_integer) printf '' ;;
        global:@high_integer) printf '99' ;;
        global:@low_integer) printf '0' ;;
        global:@test_global_empty) printf '' ;;
        global:@test_local_empty) printf 'global value' ;;
        local:@test_local_empty) printf '' ;;
        global:@test_precedence) printf 'global value' ;;
        local:@test_precedence) printf 'local value' ;;
        global:@test_trailing_spaces) printf 'value  ' ;;
        *) exit 1 ;;
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
        title_only)
            cat >> "${TMP_DIR}/playerctl" <<'MOCK'
    '-l') printf 'title-only
' ;;
    '-p title-only status') printf 'Playing
' ;;
    '-p title-only metadata artist') printf '' ;;
    '-p title-only metadata title') printf 'Title
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

resolve_with_mock() {
    PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; get_tmux_option "$2" "$3"' \
        _ "${ROOT_DIR}/scripts/helpers.sh" "$1" "$2"
}

run_real_tmux_tests() {
    local real_bin="${TMP_DIR}/real-tmux-bin"
    local session="nowplaying-test"
    local actual
    local global_options

    REAL_TMUX="$(command -v tmux || true)"
    if [[ -z "$REAL_TMUX" ]]; then
        fail "tmux is required for isolated integration tests"
    fi

    TMUX_TEST_SERVER="nowplaying-test-$$-${RANDOM}"
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" -f /dev/null new-session -d -s "$session"

    mkdir -p "$real_bin"
    export NOWPLAYING_TEST_REAL_TMUX="$REAL_TMUX"
    export NOWPLAYING_TEST_SERVER="$TMUX_TEST_SERVER"
    export NOWPLAYING_TEST_SESSION="$session"
    cat > "${real_bin}/tmux" <<'WRAPPER'
#!/usr/bin/env bash
if [[ "$1" == "show-option" || "$1" == "set-option" ]]; then
    command="$1"
    shift
    exec "$NOWPLAYING_TEST_REAL_TMUX" -L "$NOWPLAYING_TEST_SERVER" "$command" -t "$NOWPLAYING_TEST_SESSION" "$@"
fi
exec "$NOWPLAYING_TEST_REAL_TMUX" -L "$NOWPLAYING_TEST_SERVER" "$@"
WRAPPER
    chmod +x "${real_bin}/tmux"

    real_resolve() {
        PATH="${real_bin}:${PATH}" bash -c 'source "$1"; get_tmux_option "$2" "$3"' \
            _ "${ROOT_DIR}/scripts/helpers.sh" "$1" "$2"
    }
    real_nowplaying_option() {
        PATH="${real_bin}:${PATH}" bash -c 'source "$1"; get_nowplaying_option "$2"' \
            _ "${ROOT_DIR}/scripts/helpers.sh" "$1"
    }

    assert_eq "fallback" "$(real_resolve @test fallback)" "real tmux absent option uses fallback"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @test ""
    assert_eq "" "$(real_resolve @test fallback)" "real tmux empty global option wins"
    if ! "$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -g @test >/dev/null; then
        fail "real tmux empty global option remains present"
    fi
    printf 'ok - real tmux empty global option remains present\n'

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @test "global value"
    assert_eq "global value" "$(real_resolve @test fallback)" "real tmux global option resolves exactly"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -t "$session" @test "local value"
    assert_eq "local value" "$(real_resolve @test fallback)" "real tmux local option wins"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -t "$session" @test ""
    assert_eq "" "$(real_resolve @test fallback)" "real tmux empty local option wins over global"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g -u @nowplaying_playing_icon 2>/dev/null || true
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -t "$session" -u @nowplaying_playing_icon 2>/dev/null || true
    assert_eq "♪ " "$(real_nowplaying_option @nowplaying_playing_icon)" "real tmux playing icon fallback preserves trailing space"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_playing_icon ""
    assert_eq "" "$(real_nowplaying_option @nowplaying_playing_icon)" "real tmux empty playing icon wins"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_scroll_padding ""
    assert_eq "" "$(real_nowplaying_option @nowplaying_scroll_padding)" "real tmux empty scroll padding wins"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g -u @nowplaying_playing_icon
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g -u @nowplaying_scroll_padding
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g status-right 'before#{nowplaying}after'
    PATH="${real_bin}:${PATH}" bash "${ROOT_DIR}/nowplaying.tmux"

    global_options="$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-options -g)"
    if [[ "$global_options" == *"@nowplaying_"* ]]; then
        fail "plugin load created nowplaying default options"
    fi
    printf 'ok - plugin load does not create nowplaying default options\n'

    actual="$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv status-right)"
    assert_eq "before#(${ROOT_DIR}/scripts/nowplaying.sh)after" "$actual" "status interpolation remains active"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_playing_icon ""
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_scroll_padding "pad  "
    PATH="${real_bin}:${PATH}" bash "${ROOT_DIR}/nowplaying.tmux"

    if ! "$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -g @nowplaying_playing_icon >/dev/null; then
        fail "plugin load removed empty override"
    fi
    assert_eq "" "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv @nowplaying_playing_icon)" "plugin load preserves empty override"
    assert_eq "pad  " "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv @nowplaying_scroll_padding)" "plugin load preserves non-empty override exactly"
}

bash -n "${ROOT_DIR}/nowplaying.tmux" "${ROOT_DIR}"/scripts/*.sh
printf 'ok - bash syntax\n'

write_tmux_mock

assert_eq "fallback" "$(resolve_with_mock @test_absent fallback)" "mock absent option uses fallback"
assert_eq "" "$(resolve_with_mock @test_global_empty fallback)" "mock empty global option wins"
assert_eq "" "$(resolve_with_mock @test_local_empty fallback)" "mock empty local option wins over global"
assert_eq "local value" "$(resolve_with_mock @test_precedence fallback)" "mock local option wins over global"
assert_eq "value  " "$(resolve_with_mock @test_trailing_spaces fallback)" "mock option preserves trailing spaces"

helper_output="$(PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; printf "%s %s %s %s\n" "$(get_tmux_integer_option @bad_integer 50 4)" "$(get_tmux_integer_option @empty_integer 50 4)" "$(get_tmux_integer_option @low_integer 50 4)" "$(get_tmux_integer_option @high_integer 1 1 10)"' _ "${ROOT_DIR}/scripts/helpers.sh")"
assert_eq "50 50 4 10" "$helper_output" "integer option validation"

# shellcheck source=scripts/helpers.sh
source "${ROOT_DIR}/scripts/helpers.sh"
assert_adapter_record $'Paused\tArtist\tTitle' "Paused" "Artist" "Title" "complete adapter record"
assert_adapter_record $'Playing\t\tTitle' "Playing" "" "Title" "title-only adapter record"
assert_adapter_record $'Paused\tArtist\t' "Paused" "Artist" "" "artist-only adapter record"
assert_adapter_record $'Stopped\t\t' "Stopped" "" "" "empty metadata adapter record"
assert_adapter_rejected "plain text" "plain-text adapter output"
assert_adapter_rejected $'Playing\tTitle' "one-tab adapter output"
assert_adapter_rejected $'Playing\tArtist\tTitle\tExtra' "extra-tab adapter output"
assert_adapter_rejected $'\tArtist\tTitle' "empty-status adapter output"
assert_adapter_rejected $'Playing\tArtist\tTitle\nSecond' "multiline adapter output"
assert_adapter_rejected $'Playing\tArtist\tTitle\r' "carriage-return adapter output"

assert_scrolling_text "abcde" "abcde" 5 "::" 99 "scrolling returns text that exactly fits"
assert_scrolling_text "abcd" "abcde" 4 "::" 0 "scrolling starts at first position"
assert_scrolling_text "e::a" "abcde" 4 "::" 4 "scrolling crosses into padding"
assert_scrolling_text "::ab" "abcde" 4 "::" 5 "scrolling starts at padding"
assert_scrolling_text ":abc" "abcde" 4 "::" 6 "scrolling starts at last cycle offset"
assert_scrolling_text "abcd" "abcde" 4 "::" 7 "scrolling wraps at cycle length"
assert_scrolling_text ":abc" "abcde" 4 "::" 13 "scrolling normalizes large offsets"
assert_scrolling_text "eabc" "abcde" 4 "" 4 "scrolling crosses empty-padding boundary"

write_uname_mock

write_playerctl_mock playing
assert_eq $'Playing\tArtist\tTitle' "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh")" "linux adapter prefers playing player"
assert_eq "♪ Artist - Title" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders playing metadata"

write_playerctl_mock paused
assert_eq "⏸ Old - Track" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders paused metadata"

write_playerctl_mock title_only
assert_eq $'Playing\t\tTitle' "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh")" "linux adapter preserves empty artist"
assert_eq "♪ Title" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders title-only metadata"

write_playerctl_mock stopped
assert_eq "⏹ Done - Song" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders stopped metadata"

write_playerctl_mock empty
assert_eq "" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders empty output without metadata"

run_real_tmux_tests

printf 'all tests passed\n'
