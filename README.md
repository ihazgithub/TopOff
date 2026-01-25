# TopOff 🍺

A simple macOS menu bar app for one-click Homebrew updates.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **One-click updates** — Run `brew update && brew upgrade` from your menu bar
- **Greedy mode** — Force-update apps that auto-update (Chrome, Slack, etc.)
- **See what changed** — View upgraded packages directly in the menu
- **Launch at login** — Always have TopOff ready
- **Custom beer mug icon** — Half-filled when idle, overflowing when updates complete

## Screenshots

The menu bar icon shows a half-filled beer mug. When updates complete, it briefly shows a checkmark, then an overflowing mug with foam, before returning to the half-filled state.

## Installation

### Build from Source

1. Clone this repository
2. Open `TopOff/TopOff.xcodeproj` in Xcode
3. Build and run (⌘R)

### Requirements

- macOS 14.0 or later
- [Homebrew](https://brew.sh) installed

## Usage

1. Click the beer mug icon in your menu bar
2. Choose **Update All** or **Update All (Greedy)**
3. Watch the icon animate while updates run
4. Check the menu again to see what was upgraded

## What's the difference between Update All and Greedy?

| Option | Command | What it does |
|--------|---------|--------------|
| Update All | `brew upgrade` | Updates packages that don't auto-update |
| Update All (Greedy) | `brew upgrade --greedy` | Also updates apps with built-in auto-update (Chrome, VSCode, etc.) |

## License

MIT License - feel free to use, modify, and distribute.

## Credits

Built with [Claude Code](https://claude.ai/code)
