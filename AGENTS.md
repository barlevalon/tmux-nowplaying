# Agent instructions for tmux-nowplaying

## Project shape
- tmux plugin entrypoint: `nowplaying.tmux`
- Runtime script: `scripts/nowplaying.sh`
- Shared shell helpers: `scripts/helpers.sh`
- Platform adapters:
  - macOS: `scripts/nowplaying_mediaremote.swift`
  - Linux: `scripts/nowplaying_linux.sh`

## Test commands
- Test suite: `./scripts/test.sh`
- Main script: `./scripts/nowplaying.sh`
- Shell syntax: `bash -n nowplaying.tmux scripts/*.sh`
- Linux adapter: `./scripts/nowplaying_linux.sh` (requires `playerctl` and a playing MPRIS source)
- macOS adapter: `swift scripts/nowplaying_mediaremote.swift`
- tmux integration: source the plugin from a tmux session and render `#{nowplaying}` in `status-left` or `status-right`
- Permissions check: scripts intended to execute must stay mode `755`

## Compatibility targets
- tmux 2.9+
- macOS 10.15+ with Swift runtime and MediaRemote private framework
- Linux with D-Bus/MPRIS via `playerctl`

## Code style
- Shell: bash, `[[ ]]`, quote variables, handle paths with spaces, keep user-facing stderr quiet.
- Swift: no external dependencies, safe optional handling, exit non-zero for adapter failure.
- tmux options: read with `tmux show-option -gqv` or `get_tmux_option`; preserve user overrides.
- Adapter output: single line `Status<TAB>Artist<TAB>Title`; empty output means “nothing renderable now playing”.
- Dependencies: do not add runtime dependencies beyond Swift on macOS and `playerctl` on Linux.

## Documentation rules
- Keep `README.md` short and user-facing: install, usage, options, troubleshooting.
- Do not document options that current code cannot actually render.
- Keep platform-specific claims tied to the current adapter implementations.

## Git hygiene
- Do not add compatibility symlinks for agent files (`AGENT.md`, `CLAUDE.md`). `AGENTS.md` is the source of truth.
- Do not mention AI tools or agents in commits, PRs, changelog entries, or code comments.
