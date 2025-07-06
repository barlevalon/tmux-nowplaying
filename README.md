# tmux-nowplaying

A cross-platform tmux plugin that displays currently playing media. On macOS, it uses the system-wide Now Playing widget. On Linux, it uses MPRIS to work with any compatible media player.

![tmux-nowplaying screenshot](screenshot.png)

## Features

- 🎵 Cross-platform support (macOS and Linux)
- 🌐 Works with web-based players (YouTube, SoundCloud, etc.)
- 🎧 Supports Spotify, Apple Music, VLC, and all compatible media apps
- ⚡ Native integration:
  - macOS: Uses MediaRemote framework
  - Linux: Uses MPRIS D-Bus interface via playerctl
- 🎯 Minimal dependencies
- 🔧 Customizable icons and formatting
- 📜 Optional scrolling for long artist/title text

## Requirements

- tmux 2.9 or later

### macOS
- macOS 10.15 or later
- Swift runtime (included with macOS)

### Linux
- playerctl (for MPRIS support)
- D-Bus (usually pre-installed)

## Migration from tmux-nowplaying-macos

If you're upgrading from the old `tmux-nowplaying-macos` plugin:

1. Update your `~/.tmux.conf`:
   ```bash
   # Old:
   set -g @plugin 'barlevalon/tmux-nowplaying-macos'
   
   # New:
   set -g @plugin 'barlevalon/tmux-nowplaying'
   ```

2. Remove the old plugin and install the new one:
   ```bash
   rm -rf ~/.tmux/plugins/tmux-nowplaying-macos
   ```

3. Press `prefix + I` to install the new plugin

The plugin now supports both macOS and Linux!

## Installation

### Using [TPM](https://github.com/tmux-plugins/tpm) (recommended)

Add plugin to your `~/.tmux.conf`:

```bash
set -g @plugin 'barlevalon/tmux-nowplaying'
```

Press `prefix + I` to install the plugin.

### Manual Installation

Clone the repository:

```bash
git clone https://github.com/barlevalon/tmux-nowplaying ~/.tmux/plugins/tmux-nowplaying
```

Add this to your `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/tmux-nowplaying/nowplaying.tmux
```

Reload tmux configuration:

```bash
tmux source ~/.tmux.conf
```

## Usage

Add `#{nowplaying}` to your `status-left` or `status-right` in `~/.tmux.conf`:

```bash
set -g status-right '#{nowplaying} | %H:%M'
```

The plugin will display the currently playing track in the format: `♪ Artist - Title`

Note: After installing the plugin, you may need to reload your tmux configuration (`prefix + r` or `tmux source ~/.tmux.conf`) for the interpolation to take effect.

## Configuration

### Customize Icons

```bash
# Playing icon (default: "♪ ")
set -g @nowplaying_playing_icon "🎵 "

# Paused icon (default: "")
set -g @nowplaying_paused_icon "⏸ "

# Stopped icon (default: "")
set -g @nowplaying_stopped_icon "⏹ "
```

### Scrolling Text

When the artist and title text is too long, it can automatically scroll:

```bash
# Enable/disable scrolling text (default: "no")
set -g @nowplaying_scrolling_enabled "yes"

# Maximum characters before scrolling (default: 50, minimum: 1)
set -g @nowplaying_scrollable_threshold 50

# Scroll speed multiplier (default: 1, range: 1-10)
# Higher values = faster scrolling
set -g @nowplaying_scroll_speed 1

# Padding between text repetitions (default: "   ")
set -g @nowplaying_scroll_padding "   "
```

### Auto-update

The plugin automatically updates when tmux refreshes the status bar. You can control the refresh rate:

```bash
# Refresh every 2 seconds (default: 15)
set -g status-interval 2

# Enable automatic interval adjustment for smooth scrolling (default: "no")
# Only works when scrolling is enabled
set -g @nowplaying_auto_interval "yes"

# Interval when playing and scrolling (default: 1)
set -g @nowplaying_playing_interval 1
```

By default, the plugin automatically manages the refresh rate:
- **1 second** when text is scrolling for smooth animation
- **Your original status-interval** when music is stopped or text fits without scrolling
- The plugin remembers your original `status-interval` and restores it when not scrolling
- You can disable this automatic management by setting `@nowplaying_auto_interval` to "no"

## How It Works

The plugin automatically detects your operating system and uses the appropriate method:

### macOS
Uses the private MediaRemote framework to access the same "Now Playing" information that appears in Control Center. Works with any media source on your system.

### Linux
Uses the MPRIS (Media Player Remote Interfacing Specification) D-Bus interface via playerctl. This is the standard protocol that most Linux media players support, including:
- Spotify (desktop and TUI clients like spotify-player)
- VLC
- Firefox/Chrome (for web-based media)
- Rhythmbox, Clementine, and most other players

The plugin consists of:
1. Platform-specific scripts (Swift for macOS, bash for Linux)
2. A main bash script that detects the OS and calls the appropriate handler
3. TPM-compatible plugin structure

## Comparison with Other Solutions

| Feature | tmux-nowplaying-macos | tmux-spotify | nowplaying-cli |
|---------|----------------------|--------------|----------------|
| Works with all media apps | ✅ | ❌ | ✅ |
| No external dependencies | ✅ | ❌ | ❌ |
| TPM compatible | ✅ | ✅ | ❌ |
| Maintained | ✅ | ❓ | ❓ |
| Cross-platform | ✅ | ❌ | ❌ |

## Installation Notes

### Linux

Install playerctl for MPRIS support:

```bash
# Arch Linux
sudo pacman -S playerctl

# Ubuntu/Debian
sudo apt install playerctl

# Fedora
sudo dnf install playerctl
```

## Troubleshooting

### Nothing is displayed

1. Ensure media is actually playing in a supported app
2. Check that the script has execute permissions:
   ```bash
   chmod +x ~/.tmux/plugins/tmux-nowplaying/scripts/*
   ```
3. Test the script directly:
   ```bash
   ~/.tmux/plugins/tmux-nowplaying/scripts/nowplaying.sh
   ```

### Linux-specific issues

1. Check if playerctl is installed:
   ```bash
   which playerctl
   ```
2. List available players:
   ```bash
   playerctl -l
   ```
3. Test playerctl directly:
   ```bash
   playerctl metadata
   ```

### macOS: "No such file or directory" error

Make sure Swift is available:
```bash
swift --version
```

### Slow performance

The first run may be slower as Swift compiles the script. Subsequent runs will be faster.

### Scrolling settings persist after removal

tmux options remain set even after removing them from your config. To fully disable scrolling after removing the configuration:

```bash
# Explicitly disable scrolling
tmux set-option -g @nowplaying_scrolling_enabled "no"

# Or unset all plugin options to restore defaults
tmux set-option -gu @nowplaying_scrolling_enabled
tmux set-option -gu @nowplaying_scrollable_threshold
tmux set-option -gu @nowplaying_scroll_speed
```

## Contributing

Pull requests are welcome! Please feel free to submit issues or PRs.

## License

MIT - see [LICENSE](LICENSE) file for details.

## Credits

- Uses macOS MediaRemote framework
- Inspired by [tmux-spotify](https://github.com/robhurring/tmux-spotify) and [nowplaying-cli](https://github.com/kirtan-shah/nowplaying-cli)
- Created by [@barlevalon](https://github.com/barlevalon)