#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TMUX_MOCK_STATE_DIR="${TMP_DIR}/tmux-state"
TMUX_MOCK_LOG="${TMP_DIR}/tmux.log"
PLAYERCTL_MOCK_LOG="${TMP_DIR}/playerctl.log"
SLEEP_MOCK_LOG="${TMP_DIR}/sleep.log"
REAL_TMUX=""
TMUX_TEST_SERVER=""
export TMUX_MOCK_STATE_DIR TMUX_MOCK_LOG PLAYERCTL_MOCK_LOG SLEEP_MOCK_LOG

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
        [[ -f "$file" ]] || exit 1
        cat "$file"
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
        else
            value="${4:-}"
            printf '%s' "$value" > "$file"
            if [[ "$scope" == "global" && ( "$option" == "status-left" || "$option" == "status-right" ) ]]; then
                printf '%s\t%s\n' "$option" "$value" >> "$TMUX_MOCK_STATE_DIR/status-writes"
            fi
        fi
        ;;
    refresh-client)
        [[ "$#" -eq 4 && "${2:-}" == "-t" && -n "${3:-}" && "${4:-}" == "-S" ]] || exit 1
        printf 'refresh-client -t %s -S\n' "$3" >> "$TMUX_MOCK_LOG"
        ;;
    *)
        printf 'unsupported tmux mock command: %s\n' "$*" >&2
        exit 1
        ;;
esac
MOCK
    chmod +x "${TMP_DIR}/tmux"
}

write_platform_mocks() {
    cat > "${TMP_DIR}/uname" <<'MOCK'
#!/usr/bin/env bash
printf 'Linux\n'
MOCK
    cat > "${TMP_DIR}/sleep" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$SLEEP_MOCK_LOG"
MOCK
    cat > "${TMP_DIR}/playerctl" <<'MOCK'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$PLAYERCTL_MOCK_LOG"
separator=$'\034'
mode="${PLAYERCTL_MOCK_MODE:-playing}"

if [[ "$1" == "-l" ]]; then
    case "$mode" in
        playing) printf 'paused.instance\nplaying.instance\n' ;;
        paused) printf 'paused.instance\n' ;;
        stopped) printf 'stopped.instance\n' ;;
        coherent) printf 'changing.instance\n' ;;
        title_only) printf 'title-only.instance\n' ;;
        artist_only) printf 'artist-only.instance\n' ;;
        sanitized) printf 'controls.instance\n' ;;
        empty) printf '' ;;
    esac
    exit 0
fi

if [[ "$1" == "-p" && "$3" == "status" ]]; then
    case "$2" in
        paused.instance) printf 'Paused\n' ;;
        playing.instance) printf 'Playing\n' ;;
        stopped.instance) printf 'Stopped\n' ;;
        changing.instance) printf 'Playing\n' ;;
        title-only.instance) printf 'Playing\n' ;;
        artist-only.instance) printf 'Playing\n' ;;
        controls.instance) printf 'Playing\n' ;;
        *) exit 1 ;;
    esac
    exit 0
fi

if [[ "$1" == "-p" && "$3" == "metadata" && "$4" == "--format" ]]; then
    expected_format="{{status}}${separator}{{artist}}${separator}{{title}}"
    [[ "$5" == "$expected_format" ]] || exit 1
    case "$2" in
        paused.instance) printf 'Paused%sOld%sTrack\n' "$separator" "$separator" ;;
        playing.instance) printf 'Playing%sArtist%sTitle\n' "$separator" "$separator" ;;
        stopped.instance) printf 'Stopped%sDone%sSong\n' "$separator" "$separator" ;;
        changing.instance) printf 'Paused%sFresh%sSnapshot\n' "$separator" "$separator" ;;
        title-only.instance) printf 'Playing%s%sTitle\n' "$separator" "$separator" ;;
        artist-only.instance) printf 'Playing%sArtist%s\n' "$separator" "$separator" ;;
        controls.instance) printf 'Playing%sArtist\tOne\rTwo\nThree%sTitle\tFour\rFive\nSix\n' "$separator" "$separator" ;;
        *) exit 1 ;;
    esac
    exit 0
fi

exit 1
MOCK
    chmod +x "${TMP_DIR}/uname" "${TMP_DIR}/sleep" "${TMP_DIR}/playerctl"
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

resolve_with_mock() {
    PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; get_tmux_option "$2" "$3"' \
        _ "${ROOT_DIR}/scripts/helpers.sh" "$1" "$2"
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

wait_for_log_line() {
    local file="$1"
    local expected="$2"
    local message="$3"
    local attempt

    for ((attempt = 0; attempt < 200; attempt++)); do
        if [[ -f "$file" ]] && grep -Fqx "$expected" "$file"; then
            printf 'ok - %s\n' "$message"
            return
        fi
        sleep 0.01
    done
    fail "$message"
}

assert_no_scheduled_refresh() {
    local message="$1"

    sleep 0.05
    assert_eq "" "$(cat "$SLEEP_MOCK_LOG")" "${message} does not schedule sleep"
    assert_eq "" "$(cat "$TMUX_MOCK_LOG")" "${message} does not refresh client"
}

clear_refresh_logs() {
    : > "$SLEEP_MOCK_LOG"
    : > "$TMUX_MOCK_LOG"
}

run_entrypoint() {
    run_with_mocks bash "$1/nowplaying.tmux"
}

run_real_tmux_tests() {
    local real_bin="${TMP_DIR}/real-tmux-bin"
    local session="nowplaying-test"
    local actual

    REAL_TMUX="$(command -v tmux || true)"
    [[ -n "$REAL_TMUX" ]] || fail "tmux is required for isolated integration tests"

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
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @test "global value"
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -t "$session" @test "local value"
    assert_eq "local value" "$(real_resolve @test fallback)" "real tmux local option wins"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g -u @nowplaying_playing_icon 2>/dev/null || true
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -t "$session" -u @nowplaying_playing_icon 2>/dev/null || true
    assert_eq "♪ " "$(real_nowplaying_option @nowplaying_playing_icon)" "real tmux icon fallback preserves trailing space"
    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g @nowplaying_playing_icon ""
    assert_eq "" "$(real_nowplaying_option @nowplaying_playing_icon)" "real tmux empty icon wins"

    "$REAL_TMUX" -L "$TMUX_TEST_SERVER" set-option -g status-right 'before#{nowplaying}after'
    PATH="${real_bin}:${PATH}" bash "${ROOT_DIR}/nowplaying.tmux"
    actual="$("$REAL_TMUX" -L "$TMUX_TEST_SERVER" show-option -gqv status-right)"
    assert_eq "before#(\"${ROOT_DIR}/scripts/nowplaying.sh\" \"#{client_name}\")after" "$actual" "real tmux status interpolation includes client target"
}

bash -n "${ROOT_DIR}/nowplaying.tmux" "${ROOT_DIR}"/scripts/*.sh
printf 'ok - bash syntax\n'

write_tmux_mock
write_platform_mocks
: > "$TMUX_MOCK_LOG"
: > "$PLAYERCTL_MOCK_LOG"
: > "$SLEEP_MOCK_LOG"
set_mock_option @nowplaying_playing_icon "♪ "
set_mock_option @nowplaying_paused_icon "⏸ "
set_mock_option @nowplaying_stopped_icon "⏹ "
set_mock_option @nowplaying_scrolling_enabled "no"
set_mock_option @nowplaying_scrollable_threshold "50"
set_mock_option @nowplaying_scroll_speed "1"
set_mock_option @nowplaying_scroll_padding "   "
set_mock_option @nowplaying_auto_interval "no"
set_mock_option @nowplaying_playing_interval "1"
set_mock_option @test_global_empty ""
set_mock_option @test_local_empty "global value"
set_mock_local_option @test_local_empty ""
set_mock_option @test_precedence "global value"
set_mock_local_option @test_precedence "local value"
set_mock_option @test_trailing_spaces "value  "

nowplaying_command="#(\"${ROOT_DIR}/scripts/nowplaying.sh\" \"#{client_name}\")"
seed_status_values 'left #{nowplaying} / #{nowplaying}' 'right #{nowplaying}'
run_entrypoint "$ROOT_DIR"
assert_eq "left ${nowplaying_command} / ${nowplaying_command}" "$(read_status_value status-left)" "entrypoint replaces every left placeholder"
assert_eq "right ${nowplaying_command}" "$(read_status_value status-right)" "entrypoint replaces right placeholder"
assert_eq "1" "$(status_write_count status-left)" "entrypoint writes status-left once"

: > "$TMUX_MOCK_STATE_DIR/status-writes"
run_entrypoint "$ROOT_DIR"
assert_eq "0" "$(status_write_count status-left)" "entrypoint reload is idempotent"
assert_eq "0" "$(status_write_count status-right)" "entrypoint reload leaves right unchanged"

spaced_root="${TMP_DIR}/plugin with spaces"
mkdir -p "$spaced_root"
cp -p "${ROOT_DIR}/nowplaying.tmux" "$spaced_root/nowplaying.tmux"
spaced_command="#(\"${spaced_root}/scripts/nowplaying.sh\" \"#{client_name}\")"
seed_status_values 'prefix #{nowplaying} suffix' '#{nowplaying } and #{other}'
run_entrypoint "$spaced_root"
assert_eq "prefix ${spaced_command} suffix" "$(read_status_value status-left)" "entrypoint quotes path containing spaces"
assert_eq '#{nowplaying } and #{other}' "$(read_status_value status-right)" "entrypoint leaves near-match formats unchanged"

assert_eq "fallback" "$(resolve_with_mock @test_absent fallback)" "mock absent option uses fallback"
assert_eq "" "$(resolve_with_mock @test_global_empty fallback)" "mock empty global option wins"
assert_eq "" "$(resolve_with_mock @test_local_empty fallback)" "mock empty local option wins over global"
assert_eq "local value" "$(resolve_with_mock @test_precedence fallback)" "mock local option wins over global"
assert_eq "value  " "$(resolve_with_mock @test_trailing_spaces fallback)" "mock option preserves trailing spaces"

set_mock_option @nowplaying_scrollable_threshold ""
empty_threshold="$(PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; get_nowplaying_integer_option @nowplaying_scrollable_threshold 4' _ "${ROOT_DIR}/scripts/helpers.sh")"
assert_eq "50" "$empty_threshold" "empty numeric option falls back to built-in before clamping"
set_mock_option @nowplaying_scrollable_threshold "invalid"
invalid_threshold="$(PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; get_nowplaying_integer_option @nowplaying_scrollable_threshold 4' _ "${ROOT_DIR}/scripts/helpers.sh")"
assert_eq "50" "$invalid_threshold" "invalid numeric option falls back to built-in before clamping"
set_mock_option @nowplaying_playing_icon ""
assert_eq "" "$(PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; get_nowplaying_option @nowplaying_playing_icon' _ "${ROOT_DIR}/scripts/helpers.sh")" "empty nonnumeric icon is preserved"
set_mock_option @nowplaying_scroll_padding ""
assert_eq "" "$(PATH="${TMP_DIR}:${PATH}" bash -c 'source "$1"; get_nowplaying_option @nowplaying_scroll_padding' _ "${ROOT_DIR}/scripts/helpers.sh")" "empty nonnumeric padding is preserved"
set_mock_option @nowplaying_scrollable_threshold "50"
set_mock_option @nowplaying_playing_icon "♪ "
set_mock_option @nowplaying_scroll_padding "   "

# shellcheck source=scripts/helpers.sh
source "${ROOT_DIR}/scripts/helpers.sh"
assert_eq "Artist - Title" "$(format_nowplaying_metadata "Artist" "Title")" "formatter joins artist and title"
assert_eq "Artist" "$(format_nowplaying_metadata "Artist" "")" "formatter renders artist-only metadata"
assert_eq "Title" "$(format_nowplaying_metadata "" "Title")" "formatter renders title-only metadata"
assert_eq "" "$(format_nowplaying_metadata "" "")" "formatter leaves empty metadata blank"
assert_adapter_record $'Paused\tArtist\tTitle' "Paused" "Artist" "Title" "complete adapter record"
assert_adapter_record $'Playing\t\tTitle' "Playing" "" "Title" "title-only adapter record"
assert_adapter_record $'Stopped\tArtist\t' "Stopped" "Artist" "" "stopped adapter record"
assert_adapter_rejected $'Buffering\tArtist\tTitle' "unknown-status adapter output"
assert_adapter_rejected "plain text" "plain-text adapter output"
assert_adapter_rejected $'Playing\tTitle' "one-tab adapter output"
assert_adapter_rejected $'Playing\tArtist\tTitle\tExtra' "extra-tab adapter output"
assert_adapter_rejected $'Playing\tArtist\tTitle\nSecond' "multiline adapter output"
assert_adapter_rejected $'Playing\tArtist\tTitle\r' "carriage-return adapter output"

assert_scrolling_text "abcde" "abcde" 5 "::" 99 "scrolling returns text that exactly fits"
assert_scrolling_text "e::a" "abcde" 4 "::" 4 "scrolling crosses into padding"
assert_scrolling_text "::ab" "abcde" 4 "::" 5 "scrolling starts at padding"
assert_scrolling_text "abcd" "abcde" 4 "::" 7 "scrolling wraps at cycle length"
assert_scrolling_text "eabc" "abcde" 4 "" 4 "scrolling crosses empty-padding boundary"

: > "$PLAYERCTL_MOCK_LOG"
PLAYERCTL_MOCK_MODE=playing run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh" > "${TMP_DIR}/adapter-output"
assert_eq $'Playing\tArtist\tTitle' "$(cat "${TMP_DIR}/adapter-output")" "linux adapter prefers exact playing instance"
assert_eq "4" "$(wc -l < "$PLAYERCTL_MOCK_LOG" | tr -d ' ')" "linux adapter uses list plus selection statuses plus one snapshot"
assert_eq "1" "$(grep -c ' metadata --format ' "$PLAYERCTL_MOCK_LOG")" "linux adapter makes one metadata snapshot call"
assert_eq "♪ Artist - Title" "$(PLAYERCTL_MOCK_MODE=playing run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders playing metadata"
assert_eq "⏸ Old - Track" "$(PLAYERCTL_MOCK_MODE=paused run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders paused metadata"
assert_eq "⏹ Done - Song" "$(PLAYERCTL_MOCK_MODE=stopped run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders stopped metadata"
assert_eq $'Paused\tFresh\tSnapshot' "$(PLAYERCTL_MOCK_MODE=coherent run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh")" "linux adapter uses final snapshot status"
assert_eq $'Playing\t\tTitle' "$(PLAYERCTL_MOCK_MODE=title_only run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh")" "linux adapter preserves title-only metadata"
assert_eq $'Playing\tArtist\t' "$(PLAYERCTL_MOCK_MODE=artist_only run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh")" "linux adapter preserves artist-only metadata"
assert_eq "♪ Artist" "$(PLAYERCTL_MOCK_MODE=artist_only run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh")" "main renders artist-only metadata"
assert_eq $'Playing\tArtist One Two Three\tTitle Four Five Six' "$(PLAYERCTL_MOCK_MODE=sanitized run_with_mocks "${ROOT_DIR}/scripts/nowplaying_linux.sh")" "linux adapter sanitizes tab CR and LF"

if ! grep -Fq '.replacingOccurrences(of: "\t", with: " ")' "${ROOT_DIR}/scripts/nowplaying_mediaremote.swift" ||
    ! grep -Fq '.replacingOccurrences(of: "\r", with: " ")' "${ROOT_DIR}/scripts/nowplaying_mediaremote.swift" ||
    ! grep -Fq '.replacingOccurrences(of: "\n", with: " ")' "${ROOT_DIR}/scripts/nowplaying_mediaremote.swift"; then
    fail "macOS adapter source does not sanitize canonical control characters"
fi
printf 'ok - macOS adapter source sanitizes canonical control characters\n'
grep -Fq 'playbackRate > 0.0 ? "Playing" : "Paused"' "${ROOT_DIR}/scripts/nowplaying_mediaremote.swift" || fail "macOS adapter does not classify positive playback rates as playing"
printf 'ok - macOS adapter source classifies positive playback rates as playing\n'

set_mock_option @nowplaying_scrollable_threshold "4"
set_mock_option @nowplaying_scrolling_enabled "yes"
set_mock_option @nowplaying_auto_interval "yes"
set_mock_option @nowplaying_playing_interval "invalid"
client_target="/dev/pts/42"
clear_refresh_logs
PLAYERCTL_MOCK_MODE=playing run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh" "$client_target" >/dev/null
wait_for_log_line "$SLEEP_MOCK_LOG" "1" "long scrolling output schedules validated interval"
wait_for_log_line "$TMUX_MOCK_LOG" "refresh-client -t ${client_target} -S" "scheduled job refreshes exact tmux client"

clear_refresh_logs
PLAYERCTL_MOCK_MODE=playing run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh" >/dev/null
assert_no_scheduled_refresh "manual invocation without client target"

set_mock_option @nowplaying_auto_interval "no"
clear_refresh_logs
PLAYERCTL_MOCK_MODE=playing run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh" "$client_target" >/dev/null
assert_no_scheduled_refresh "auto-disabled long output"

set_mock_option @nowplaying_auto_interval "yes"
set_mock_option @nowplaying_scrolling_enabled "no"
clear_refresh_logs
PLAYERCTL_MOCK_MODE=playing run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh" "$client_target" >/dev/null
assert_no_scheduled_refresh "scrolling-disabled long output"

set_mock_option @nowplaying_scrolling_enabled "yes"
set_mock_option @nowplaying_scrollable_threshold "50"
clear_refresh_logs
PLAYERCTL_MOCK_MODE=title_only run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh" "$client_target" >/dev/null
assert_no_scheduled_refresh "short output"

set_mock_option @nowplaying_scrollable_threshold "4"
clear_refresh_logs
PLAYERCTL_MOCK_MODE=empty run_with_mocks "${ROOT_DIR}/scripts/nowplaying.sh" "$client_target" >/dev/null
assert_no_scheduled_refresh "empty adapter output"

run_real_tmux_tests
printf 'all tests passed\n'
