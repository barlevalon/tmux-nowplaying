# Agent Instructions for tmux-nowplaying-macos

## Build/Test Commands
- Test plugin directly: `./scripts/nowplaying.sh`
- Test Swift component: `swift scripts/nowplaying_mediaremote.swift`
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
- **Dependencies**: No external dependencies - only macOS system frameworks, bash, and swift runtime
- **Output Format**: Concise single line "Artist - Title" with optional icon prefix, handle missing metadata gracefully
- **Compatibility**: Support tmux 2.9+ and macOS 10.15+, use MediaRemote private framework for universal app support
- **Testing**: Test with various media apps (Spotify, Apple Music, YouTube in browser), verify scrolling behavior
- **Commit Messages**: Never mention AI agents, Claude, or similar tools in commit messages or code comments