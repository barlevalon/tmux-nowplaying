# Agent Instructions for tmux-nowplaying

## Build/Test Commands
- Test plugin directly: `./scripts/nowplaying.sh`
- Test macOS component: `swift scripts/nowplaying_mediaremote.swift`
- Test Linux component: `./scripts/nowplaying_linux.sh`
- Test single script: `bash -n scripts/nowplaying.sh` (syntax check)
- Verify permissions: `chmod +x scripts/*.sh scripts/*.swift`
- Test tmux integration: `tmux source-file ~/.tmux.conf && tmux`
- No build/lint commands required (interpreted scripts only)

## Code Style Guidelines
- **Shell Scripts**: Use bash shebang `#!/usr/bin/env bash`, quote all variables `"${VAR}"`, use `[[ ]]` for conditionals, follow shellcheck recommendations
- **Swift Scripts**: Use shebang `#!/usr/bin/env swift`, handle optionals safely with guard/if-let, no external dependencies
- **File Permissions**: All scripts must be executable (755)
- **Error Handling**: Redirect stderr to /dev/null for user-facing commands, use proper exit codes (0=success, 1=error)
- **tmux Integration**: Use `tmux show-option -gqv` for reading options, respect user customization, maintain backwards compatibility
- **Path Handling**: Always use absolute paths via `CURRENT_DIR` or `SCRIPT_DIR` variables, handle spaces in paths
- **Icons/Formatting**: Support customizable icons via tmux options, provide sensible defaults, keep output single-line
- **Dependencies**: 
  - macOS: No external dependencies - only system frameworks, bash, and swift runtime
  - Linux: playerctl for MPRIS support (user must install)
- **Output Format**: Concise single line "Artist - Title" with optional icon prefix, handle missing metadata gracefully
- **Compatibility**: 
  - tmux 2.9+ on all platforms
  - macOS 10.15+ with MediaRemote private framework
  - Linux with MPRIS D-Bus interface via playerctl
- **Testing**: 
  - macOS: Test with Spotify, Apple Music, YouTube in browser
  - Linux: Test with spotify-player, VLC, Firefox/Chrome media
  - Verify scrolling behavior on both platforms
- **Commit Messages**: Never mention AI agents, Claude, or similar tools in commit messages or code comments