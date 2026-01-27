# TopOff 🍺

A simple macOS menu bar app for one-click Homebrew updates with automatic background checking.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Download

**[Download TopOff v1.2](https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v1.2.dmg)** (macOS 14+)

Or view all releases [here](https://github.com/ihazgithub/TopOff/releases).

## Features

- **Automatic update checking** — Periodically checks for outdated packages in the background
- **Smart icon status** — Full mug when up-to-date, half-full when updates are available
- **Package details at a glance** — See outdated package names and version changes directly in the menu
- **One-click updates** — Run `brew update && brew upgrade` from your menu bar
- **Selective updates** — Update or skip individual packages (enable in Settings)
- **Greedy mode** — Force-update apps that auto-update (Chrome, Slack, etc.)
- **Auto cleanup** — Automatically runs `brew cleanup` after upgrades to free disk space
- **Configurable check interval** — Check every hour, 4 hours (default), 12 hours, 24 hours, or manually
- **See what changed** — View upgraded packages and freed disk space in the menu
- **Update notifications** — Checks GitHub for new releases on launch and lets you know when an update is available
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

1. Download the [latest DMG](https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v1.2.dmg)
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
2. See which packages need updating with version details
3. Choose **Update All**, **Update All (Greedy)**, or update individual packages
4. Watch the icon animate while updates run
5. Check the menu to see what was upgraded and how much disk space was freed

### Settings

All preferences are available under the **Settings** submenu:

- **Selective Updates** — Enable to update or skip individual packages
- **Auto Cleanup** — Automatically runs `brew cleanup` after upgrades (on by default). Disable to use the manual Clean Up button instead.
- **Launch at Login** — Start TopOff when you log in
- **Check Interval** — How often TopOff checks for outdated packages:

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
