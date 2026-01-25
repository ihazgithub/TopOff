# TopOff 🍺

A simple macOS menu bar app for one-click Homebrew updates with automatic background checking.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Download

**[Download TopOff v1.1.0](https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v1.1.0.dmg)** (macOS 14+)

Or view all releases [here](https://github.com/ihazgithub/TopOff/releases).

## Features

- **Automatic update checking** — Periodically checks for outdated packages in the background
- **Smart icon status** — Full mug when up-to-date, half-full when updates are available
- **One-click updates** — Run `brew update && brew upgrade` from your menu bar
- **Greedy mode** — Force-update apps that auto-update (Chrome, Slack, etc.)
- **Configurable check interval** — Check every hour, 4 hours (default), 12 hours, 24 hours, or manually
- **See what changed** — View upgraded packages directly in the menu
- **Launch at login** — Always have TopOff ready

## Screenshots

The menu bar icon tells you at a glance if updates are available:

| Icon | Meaning |
|------|---------|
| Full mug | All packages are up-to-date |
| Half-full mug | Updates are available (needs a refill!) |
| Spinning arrows | Checking for updates or updating |
| Checkmark | Update completed successfully |

## Installation

### Download (Recommended)

1. Download the [latest DMG](https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v1.1.0.dmg)
2. Open the DMG and drag TopOff to your Applications folder
3. Open TopOff (you may need to right-click → Open the first time)

### Build from Source

1. Clone this repository
2. Open `TopOff/TopOff.xcodeproj` in Xcode
3. Build and run (⌘R)

### Requirements

- macOS 14.0 or later
- [Homebrew](https://brew.sh) installed

## Usage

1. Click the beer mug icon in your menu bar
2. See at a glance if updates are available (half-full mug = updates waiting)
3. Choose **Update All** or **Update All (Greedy)**
4. Watch the icon animate while updates run
5. Check the menu again to see what was upgraded

### Check Interval

TopOff automatically checks for outdated packages in the background. You can configure how often:

| Setting | Behavior |
|---------|----------|
| Every hour | Check every 60 minutes |
| Every 4 hours | Default setting |
| Every 12 hours | Check twice daily |
| Every 24 hours | Check once daily |
| Manual only | Only check when you click "Check for Updates" |

## What's the difference between Update All and Greedy?

| Option | Command | What it does |
|--------|---------|--------------|
| Update All | `brew upgrade` | Updates packages that don't auto-update |
| Update All (Greedy) | `brew upgrade --greedy` | Also updates apps with built-in auto-update (Chrome, VSCode, etc.) |

## License

MIT License - feel free to use, modify, and distribute.

## Credits

Created by **Thomas Haslam**
