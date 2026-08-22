#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TMUX_MOCK_STATE_DIR="${TMP_DIR}/tmux-state"
TMUX_MOCK_LOG="${TMP_DIR}/tmux.log"
REAL_TMUX=""
TMUX_TEST_SERVER=""
export TMUX_MOCK_STATE_DIR TMUX_MOCK_LOG

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
    mkdir -p "$TMUX_MOCK_STATE_DIR/global" "$TMUX_MOCK_STATE_DIR/local"
    cat > "${TMP_DIR}/tmux" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

scope="global"
option_file() {
    local option="$1"
    option="${option//@/_at_}"
    option="${option//\//_slash_}"
    printf '%s/%s/%s\n' "$TMUX_MOCK_STATE_DIR" "$scope" "$option"
}

mkdir -p "$TMUX_MOCK_STATE_DIR/global" "$TMUX_MOCK_STATE_DIR/local"

case "${1:-}" in
    show-option)
        flags="${2:-}"
        option="${@: -1}"
        if [[ "$flags" != *g* ]]; then
            scope="local"
        fi
        file="$(option_file "$option")"
        if [[ -f "$file" ]]; then
            cat "$file"
        else
            exit 1
        fi
        ;;
    set-option)
        flags="${2:-}"
        option="${3:-}"
        if [[ "$flags" != *g* ]]; then
            scope="local"
        fi
        file="$(option_file "$option")"
        if [[ "$flags" == *u* ]]; then
            rm -f "$file"
            printf 'unset %s\n' "$option" >> "$TMUX_MOCK_LOG"
        else
            value="${4:-}"
            if [[ "$scope" == "global" && "$option" == "status-interval" && "${TMUX_MOCK_PAUSE_SET_STATUS:-}" == "yes" ]]; then
                : > "$TMUX_MOCK_STATE_DIR/pause-ready"
                while [[ ! -f "$TMUX_MOCK_STATE_DIR/pause-release" ]]; do
                    sleep 0.01
                done
            fi
            printf '%s' "$value" > "$file"
            printf 'set %s=%s\n' "$option" "$value" >> "$TMUX_MOCK_LOG"
            if [[ "$scope" == "global" && ( "$option" == "status-left" || "$option" == "status-right" ) ]]; then
                printf '%s\t%s\n' "$option" "$value" >> "$TMUX_MOCK_STATE_DIR/status-writes"
            fi
        fi
        ;;
    wait-for)
        operation="${2:-}"
        channel="${3:-}"
        lock_dir="$TMUX_MOCK_STATE_DIR/lock-${channel}"
        if [[ -n "${TMUX_MOCK_CALL_ID:-}" ]]; then
            printf '%s %s %s\n' "$TMUX_MOCK_CALL_ID" "$operation" "$channel" >> "$TMUX_MOCK_LOG"
        fi
        case "$operation" in
            -L)
                while ! mkdir "$lock_dir" 2>/dev/null; do
                    sleep 0.01
                done
                ;;
            -U) rmdir "$lock_dir" ;;
            *)
                printf 'unsupported tmux wait-for operation: %s\n' "$operation" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        printf 'unsupported tmux mock command: %s\n' "$*" >&2
        exit 1
        ;;
esac
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

set_mock_option() {
    run_with_mocks tmux set-option -gq "$1" "$2"
}

set_mock_local_option() {
    run_with_mocks tmux set-option -q "$1" "$2"
}

get_mock_option() {
    run_with_mocks tmux show-option -gqv "$1"
}

clear_tmux_mock_log() {
    : > "$TMUX_MOCK_LOG"
}

wait_for_mock_file() {
    local file="$1"
    local attempt

    for ((attempt = 0; attempt < 500; attempt++)); do
        if [[ -f "$file" ]]; then
            return
        fi
        sleep 0.01
    done

    fail "timed out waiting for mock file: $file"
}

wait_for_mock_log() {
    local pattern="$1"
    local attempt

    for ((attempt = 0; attempt < 500; attempt++)); do
        if grep -Fq "$pattern" "$TMUX_MOCK_LOG"; then
            return
        fi
        sleep 0.01
    done

    fail "timed out waiting for mock log: $pattern"
}

run_interval_update() {
    local output_length="$1"
    local scrollable_threshold="$2"

    PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; update_nowplaying_status_interval "$2" "$3"' _ \
        "${ROOT_DIR}/scripts/helpers.sh" "$output_length" "$scrollable_threshold"
}

seed_status_values() {
    printf '%s' "$1" > "$TMUX_MOCK_STATE_DIR/global/status-left"
    printf '%s' "$2" > "$TMUX_MOCK_STATE_DIR/global/status-right"
    : > "$TMUX_MOCK_STATE_DIR/status-writes"
}

read_status_value() {
    cat "$TMUX_MOCK_STATE_DIR/global/$1"
}

status_write_count() {
    awk -F '\t' -v option="$1" '$1 == option { count++ } END { print count + 0 }' \
        "$TMUX_MOCK_STATE_DIR/status-writes"
}

run_entrypoint() {
    run_with_mocks bash "$1/nowplaying.tmux"
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
    real_interval_update() {
        PATH="${real_bin}:${PATH}" bash -c 'source "$1"; update_nowplaying_status_interval "$2" "$3"' \
            _ "${ROOT_DIR}/scripts/helpers.sh" "$1" "$2"
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
    assert_eq "before#(\"${ROOT_DIR}/scripts/nowplaying.sh\")after" "$actual" "status interpolation remains active"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_playing_icon ""
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_scroll_padding "pad  "
    PATH="${real_bin}:${PATH}" bash "${ROOT_DIR}/nowplaying.tmux"

    if ! "$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -g @nowplaying_playing_icon >/dev/null; then
        fail "plugin load removed empty override"
    fi
    assert_eq "" "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv @nowplaying_playing_icon)" "plugin load preserves empty override"
    assert_eq "pad  " "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv @nowplaying_scroll_padding)" "plugin load preserves non-empty override exactly"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_scrolling_enabled yes
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_auto_interval yes
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_playing_interval 1
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g status-interval 15
    real_interval_update 51 50
    assert_eq "1" "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv status-interval)" "real tmux interval acquisition applies temporary value"
    assert_eq "15" "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv @nowplaying_original_interval)" "real tmux interval acquisition captures original value"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g status-interval 5
    real_interval_update 60 50
    assert_eq "1" "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv status-interval)" "real tmux active refresh reapplies temporary value"
    assert_eq "5" "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv @nowplaying_original_interval)" "real tmux active refresh captures external value"

    real_interval_update 10 50
    assert_eq "5" "$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv status-interval)" "real tmux release restores external value"
    if "$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -g @nowplaying_original_interval >/dev/null 2>&1 ||
        "$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -g @nowplaying_applied_interval >/dev/null 2>&1; then
        fail "real tmux interval release left ownership markers"
    fi
    printf 'ok - real tmux interval release clears ownership markers\n'
}

bash -n "${ROOT_DIR}/nowplaying.tmux" "${ROOT_DIR}"/scripts/*.sh
printf 'ok - bash syntax\n'

write_tmux_mock
set_mock_option status-interval "15"
set_mock_option @nowplaying_playing_icon "♪ "
set_mock_option @nowplaying_paused_icon "⏸ "
set_mock_option @nowplaying_stopped_icon "⏹ "
set_mock_option @nowplaying_scrolling_enabled "no"
set_mock_option @nowplaying_scrollable_threshold "50"
set_mock_option @nowplaying_scroll_speed "1"
set_mock_option @nowplaying_scroll_padding "   "
set_mock_option @nowplaying_auto_interval "no"
set_mock_option @nowplaying_playing_interval "1"
set_mock_option @bad_integer "abc"
set_mock_option @empty_integer ""
set_mock_option @high_integer "99"
set_mock_option @low_integer "0"
set_mock_option @test_global_empty ""
set_mock_option @test_local_empty "global value"
set_mock_local_option @test_local_empty ""
set_mock_option @test_precedence "global value"
set_mock_local_option @test_precedence "local value"
set_mock_option @test_trailing_spaces "value  "
clear_tmux_mock_log

nowplaying_command="#(\"${ROOT_DIR}/scripts/nowplaying.sh\")"
seed_status_values 'left #{nowplaying} / #{nowplaying}' 'right #{nowplaying}'
run_entrypoint "$ROOT_DIR"
assert_eq "left ${nowplaying_command} / ${nowplaying_command}" "$(read_status_value status-left)" "entrypoint replaces every left placeholder"
assert_eq "right ${nowplaying_command}" "$(read_status_value status-right)" "entrypoint replaces right placeholder"
assert_eq "1" "$(status_write_count status-left)" "entrypoint writes status-left once"
assert_eq "1" "$(status_write_count status-right)" "entrypoint writes status-right once"

: > "$TMUX_MOCK_STATE_DIR/status-writes"
run_entrypoint "$ROOT_DIR"
assert_eq "left ${nowplaying_command} / ${nowplaying_command}" "$(read_status_value status-left)" "entrypoint reload preserves status-left"
assert_eq "right ${nowplaying_command}" "$(read_status_value status-right)" "entrypoint reload preserves status-right"
assert_eq "0" "$(status_write_count status-left)" "entrypoint reload does not write status-left"
assert_eq "0" "$(status_write_count status-right)" "entrypoint reload does not write status-right"

seed_status_values '#(/tmp/custom-nowplaying.sh) | #{nowplaying}' 'unchanged right'
run_entrypoint "$ROOT_DIR"
assert_eq "#(/tmp/custom-nowplaying.sh) | ${nowplaying_command}" "$(read_status_value status-left)" "entrypoint preserves unrelated nowplaying command"
assert_eq "unchanged right" "$(read_status_value status-right)" "entrypoint preserves status without placeholder"
assert_eq "1" "$(status_write_count status-left)" "mixed command status is written once"
assert_eq "0" "$(status_write_count status-right)" "status without placeholder is not written"

spaced_root="${TMP_DIR}/plugin with spaces"
mkdir -p "$spaced_root/scripts"
cp -p "${ROOT_DIR}/nowplaying.tmux" "$spaced_root/nowplaying.tmux"
cp -p "${ROOT_DIR}/scripts/helpers.sh" "${ROOT_DIR}/scripts/nowplaying.sh" "$spaced_root/scripts/"
spaced_command="#(\"${spaced_root}/scripts/nowplaying.sh\")"
seed_status_values 'prefix #{nowplaying} suffix' 'plain right'
run_entrypoint "$spaced_root"
assert_eq "prefix ${spaced_command} suffix" "$(read_status_value status-left)" "entrypoint quotes a command path containing spaces"
assert_eq "1" "$(status_write_count status-left)" "path-with-spaces installation writes once"
assert_eq "0" "$(status_write_count status-right)" "path-with-spaces no-placeholder side is not written"

seed_status_values '#(/tmp/custom-nowplaying.sh)' '#{nowplaying } and #{other}'
run_entrypoint "$ROOT_DIR"
assert_eq '#(/tmp/custom-nowplaying.sh)' "$(read_status_value status-left)" "entrypoint leaves unrelated command unchanged"
assert_eq '#{nowplaying } and #{other}' "$(read_status_value status-right)" "entrypoint leaves near-match formats unchanged"
assert_eq "0" "$(status_write_count status-left)" "unrelated command triggers no left write"
assert_eq "0" "$(status_write_count status-right)" "near-match formats trigger no right write"

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

set_mock_option @nowplaying_scrolling_enabled "yes"
set_mock_option @nowplaying_auto_interval "yes"
run_interval_update 51 50
assert_eq "1" "$(get_mock_option status-interval)" "long output applies playing interval"
assert_eq "15" "$(get_mock_option @nowplaying_original_interval)" "acquisition saves original interval"
assert_eq "1" "$(get_mock_option @nowplaying_applied_interval)" "acquisition records applied interval"

run_interval_update 60 50
assert_eq "1" "$(get_mock_option status-interval)" "repeated acquisition keeps playing interval"
assert_eq "15" "$(get_mock_option @nowplaying_original_interval)" "repeated acquisition preserves saved original"

run_interval_update 10 50
assert_eq "15" "$(get_mock_option status-interval)" "short output restores original interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "short output clears saved interval"
assert_eq "" "$(get_mock_option @nowplaying_applied_interval)" "short output clears applied interval"

run_interval_update 51 50
set_mock_option status-interval "5"
run_interval_update 60 50
assert_eq "1" "$(get_mock_option status-interval)" "active update reapplies playing interval after user change"
assert_eq "5" "$(get_mock_option @nowplaying_original_interval)" "active update captures user interval change"
run_interval_update 10 50
assert_eq "5" "$(get_mock_option status-interval)" "release restores user interval changed during ownership"
set_mock_option status-interval "15"

run_interval_update 51 50
rm -f "$TMUX_MOCK_STATE_DIR/pause-ready" "$TMUX_MOCK_STATE_DIR/pause-release"
clear_tmux_mock_log
TMUX_MOCK_CALL_ID="active" TMUX_MOCK_PAUSE_SET_STATUS="yes" \
    PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; update_nowplaying_status_interval "$2" "$3"' _ \
    "${ROOT_DIR}/scripts/helpers.sh" 60 50 &
active_pid=$!
wait_for_mock_file "$TMUX_MOCK_STATE_DIR/pause-ready"
TMUX_MOCK_CALL_ID="inactive" \
    PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; update_nowplaying_status_interval "$2" "$3"' _ \
    "${ROOT_DIR}/scripts/helpers.sh" 10 50 &
inactive_pid=$!
wait_for_mock_log "inactive -L tmux-nowplaying-status-interval"
if ! kill -0 "$inactive_pid" 2>/dev/null; then
    fail "inactive lifecycle transition did not wait for active transition"
fi
: > "$TMUX_MOCK_STATE_DIR/pause-release"
wait "$active_pid"
wait "$inactive_pid"
assert_eq "15" "$(get_mock_option status-interval)" "interleaved release restores original interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "interleaved release clears saved interval"
assert_eq "" "$(get_mock_option @nowplaying_applied_interval)" "interleaved release clears applied interval"

run_interval_update 51 50
set_mock_option @nowplaying_auto_interval "no"
run_interval_update 51 50
assert_eq "15" "$(get_mock_option status-interval)" "disabling automatic interval restores original"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "disabling automatic interval clears saved state"
assert_eq "" "$(get_mock_option @nowplaying_applied_interval)" "disabling automatic interval clears applied state"

set_mock_option @nowplaying_auto_interval "yes"
run_interval_update 51 50
set_mock_option @nowplaying_scrolling_enabled "no"
run_interval_update 51 50
assert_eq "15" "$(get_mock_option status-interval)" "disabling scrolling restores original interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "disabling scrolling clears saved state"
assert_eq "" "$(get_mock_option @nowplaying_applied_interval)" "disabling scrolling clears applied state"

set_mock_option @nowplaying_scrolling_enabled "yes"
run_interval_update 51 50
write_playerctl_mock empty
assert_eq "" "$(run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders empty output without metadata"
assert_eq "15" "$(get_mock_option status-interval)" "empty adapter output restores original interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "empty adapter output clears saved state"
assert_eq "" "$(get_mock_option @nowplaying_applied_interval)" "empty adapter output clears applied state"

set_mock_option status-interval "7"
set_mock_option @nowplaying_original_interval "15"
run_with_mocks tmux set-option -gu @nowplaying_applied_interval
clear_tmux_mock_log
run_interval_update 0 50
assert_eq "7" "$(get_mock_option status-interval)" "legacy saved state does not overwrite user interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "legacy saved state is cleared"
assert_eq "unset @nowplaying_original_interval" "$(cat "$TMUX_MOCK_LOG")" "legacy cleanup does not write status interval"

clear_tmux_mock_log
run_interval_update 0 50
run_interval_update 10 50
assert_eq "7" "$(get_mock_option status-interval)" "inactive releases preserve user interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "inactive releases do not create saved state"
assert_eq "" "$(cat "$TMUX_MOCK_LOG")" "inactive releases do not write tmux options"

run_interval_update 51 50
assert_eq "1" "$(get_mock_option status-interval)" "fresh acquisition applies playing interval"
assert_eq "7" "$(get_mock_option @nowplaying_original_interval)" "fresh acquisition captures later user interval"
assert_eq "1" "$(get_mock_option @nowplaying_applied_interval)" "fresh acquisition records applied interval"
run_interval_update 10 50
assert_eq "7" "$(get_mock_option status-interval)" "fresh acquisition restores later user interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "fresh release clears saved state"
assert_eq "" "$(get_mock_option @nowplaying_applied_interval)" "fresh release clears applied state"

set_mock_option @nowplaying_auto_interval "no"
clear_tmux_mock_log
run_interval_update 51 50
assert_eq "7" "$(get_mock_option status-interval)" "inactive auto-disabled call preserves interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "inactive auto-disabled call keeps saved state absent"
assert_eq "" "$(cat "$TMUX_MOCK_LOG")" "inactive auto-disabled call does not write tmux options"

set_mock_option @nowplaying_auto_interval "yes"
set_mock_option @nowplaying_scrolling_enabled "no"
clear_tmux_mock_log
run_interval_update 51 50
assert_eq "7" "$(get_mock_option status-interval)" "inactive scrolling-disabled call preserves interval"
assert_eq "" "$(get_mock_option @nowplaying_original_interval)" "inactive scrolling-disabled call keeps saved state absent"
assert_eq "" "$(cat "$TMUX_MOCK_LOG")" "inactive scrolling-disabled call does not write tmux options"

run_real_tmux_tests

printf 'all tests passed\n'
