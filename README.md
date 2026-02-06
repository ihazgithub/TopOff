# TopOff 🍺

Your Homebrew is running low. TopOff keeps your packages fresh from the menu bar — automatic checks, one-click refills, no terminal tab required.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Download

**[Download TopOff v1.5.0](https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v1.5.0.dmg)** (macOS 14+)

Or view all releases [here](https://github.com/ihazgithub/TopOff/releases).

## Why TopOff?

If you use Homebrew, you've probably forgotten to run `brew update && brew upgrade` for weeks at a time. Packages get stale, security patches wait, and when you finally remember, you're stuck watching terminal output scroll.

TopOff fixes this — it checks in the background and shows you at a glance when your system needs a refill. One click and you're up to date.

## Features

- **One-click updates** — Run `brew update && brew upgrade` from your menu bar
- **Automatic update checking** — Periodically checks for outdated packages in the background
- **Smart icon status** — Full mug when up-to-date, half-full when updates are available, animated spinner when actively updating
- **Real-time progress** — See exactly which package is being updated as it happens — click the menu bar during updates to watch live
- **Package details at a glance** — See outdated package names and version changes directly in the menu
- **Selective updates** — Update or skip individual packages
- **Greedy mode toggle** — Enable to include apps that auto-update (Chrome, Slack, etc.) in scheduled checks and hide the normal Update All button
- **Auto cleanup** — Automatically runs `brew cleanup` after upgrades to free disk space
- **Admin retry for protected packages** — If a cask needs admin access, TopOff prompts for your password and retries automatically
- **Update history** — View recently updated packages with version changes
- **Configurable check interval** — Check every hour, 4 hours (default), 12 hours, 24 hours, or manually
- **Launch at login** — Always have TopOff ready
- **Automatic retry on network restore** — If the app launches without internet (e.g., at startup before WiFi connects), it automatically checks for updates once connectivity is restored
- **Update notifications** — Checks GitHub for new releases on launch and lets you know when an update is available
- **See what changed** — View upgraded packages and freed disk space in the menu

## Screenshots

![TopOff Demo](TopOff_demo.gif)

The menu bar icon tells you at a glance if updates are available:

| Icon | Meaning |
|------|---------|
| Full mug | All packages are up-to-date |
| Half-full mug | Updates are available (needs a refill!) |
| Spinning arrows | Checking for updates or updating — click to see live progress |
| Checkmark | Update completed successfully |

## Installation

### Download (Recommended)

1. Download the [latest DMG](https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v1.5.0.dmg)
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

### Options

All preferences are available under the **Options** submenu:

- **Launch at Login** — Start TopOff when you log in
- **Auto Cleanup** — Automatically runs `brew cleanup` after upgrades (on by default). Disable to use the manual Clean Up button instead.
- **Greedy Mode** — When enabled, scheduled checks use `brew outdated --greedy` to include apps with built-in auto-update (Chrome, Slack, etc.). Also hides the normal "Update All" button, leaving only "Update All (Greedy)".
- **Check Interval** — How often TopOff checks for outdated packages:
- **View Update History** — See recently updated packages with version changes

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

## Privacy & Network Connections

TopOff makes only one network connection:

- **GitHub API** (`api.github.com`) — Checks for new TopOff releases on app launch

That's it. No analytics, no telemetry, no tracking.

### Why does my firewall show other connections?

If you use a firewall like Little Snitch or Lulu, you may see TopOff associated with connections to other servers (e.g., InfluxData, Google, etc.). **These connections are from Homebrew, not TopOff.**

When TopOff runs `brew update` or `brew upgrade`, it spawns Homebrew as a child process. Firewalls often attribute child process network activity to the parent app. These connections may come from:

- Homebrew's own analytics (can be disabled with `brew analytics off`)
- Specific formulas or casks being updated that have telemetry
- Package download servers

You can safely allow or deny these connections based on your preferences — denying them won't affect TopOff's functionality.

## License

MIT License - feel free to use, modify, and distribute.

## Credits

Created by **Thomas Haslam**
