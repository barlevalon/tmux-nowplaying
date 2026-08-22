# Changelog

## [1.1.1] - 2026-08-22
### Added
- Linux and macOS CI coverage for shell tests, static checks, and Swift type-checking.

### Changed
- Scrolling now schedules client-targeted refreshes without changing tmux's `status-interval`.
- Linux reads the selected player's final status and metadata from one coherent snapshot.
- Simplified status interpolation and scrolling wrap logic.
- Installation documentation now recommends pinning a stable release tag.

### Fixed
- Explicitly empty tmux options are preserved, while empty or invalid numeric options use built-in defaults before clamping.
- Empty, title-only, and artist-only adapter metadata render correctly.
- Adapter metadata containing tabs or line breaks no longer corrupts the record protocol.
- Positive macOS playback rates are classified as playing.
- Every `#{nowplaying}` placeholder in a status option is expanded safely, including plugin paths containing spaces.

## [1.1.0] - 2026-05-31
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
