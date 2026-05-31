# Changelog

## Unreleased
### Added
- Linux MPRIS adapter now reports playback status and metadata separately.
- Paused and stopped media can render with configurable icons when metadata is available.
- Shell regression suite for option parsing, adapter parsing, and mocked Linux playback states.

### Changed
- Simplified README around install, usage, options, and troubleshooting.
- Centralized tmux option defaults in shared helpers.
- Isolated automatic `status-interval` management from display formatting.
- Removed legacy agent-file symlinks; `AGENTS.md` is the source of truth.

### Fixed
- Invalid numeric tmux options now fall back or clamp instead of causing shell comparison errors.

## [1.0.0] - 2025-06-26
### Added
- Initial release
- MediaRemote framework integration for system-wide now playing info
- TPM compatibility
- Customizable playing/paused/stopped icons
- Support for all macOS media apps
