# Agent Instructions for tmux-nowplaying-macos

## Build/Test Commands
- Test script directly: `./scripts/nowplaying.sh`
- Test Swift component: `swift scripts/nowplaying_mediaremote.swift`
- Verify permissions: `chmod +x scripts/*.sh scripts/*.swift`
- No build step required (interpreted scripts)

## Code Style Guidelines
- **Shell Scripts**: Use bash shebang `#!/usr/bin/env bash`, quote variables `"${VAR}"`, use `[[ ]]` for conditionals
- **Swift Scripts**: Use shebang `#!/usr/bin/env swift`, follow Swift conventions, handle optionals safely
- **File Permissions**: All scripts must be executable (755)
- **Error Handling**: Redirect stderr to /dev/null for user-facing commands, exit with proper codes
- **tmux Integration**: Use `tmux show-option -gqv` for reading options, respect user customization
- **Path Handling**: Always use absolute paths via `CURRENT_DIR` or `SCRIPT_DIR` variables
- **Icons/Formatting**: Support customizable icons via tmux options, provide sensible defaults
- **Dependencies**: No external dependencies allowed - only macOS system frameworks and bash/swift
- **Output**: Keep output concise, single line format "Artist - Title" with optional icon prefix
- **Compatibility**: Support tmux 2.9+ and macOS 10.15+, use MediaRemote framework for universal app support
- **Commit Messages**: Never mention AI agents, Claude, or similar tools in commit messages or code comments