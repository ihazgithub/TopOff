<p align="center">
  <img src="docs/assets/topoff-icon-transparent.png" alt="TopOff app icon" width="112">
</p>

<h1 align="center">TopOff</h1>

<p align="center">
  A lightweight native Mac menu bar app for keeping Homebrew packages up to date.
</p>

<p align="center">
  Free · MIT licensed · No telemetry · macOS 14+
</p>

<p align="center">
  <a href="https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v2.1.dmg">Download TopOff for macOS</a>
</p>

<p align="center">
  <em>Version 2.1 — TopOff now updates itself. <a href="CHANGELOG.md">See what's new →</a></em>
</p>

If you use Homebrew, you have probably forgotten to run `brew update && brew upgrade` for weeks at a time. TopOff checks quietly in the background, shows outdated packages from the menu bar, and lets you update with one click.

## Features

- **One-click updates** — Run `brew update && brew upgrade` from your menu bar
- **Automatic update checking** — Periodically checks for outdated packages in the background
- **Smart icon status** — Full mug when up-to-date, half-full when updates are available, animated spinner when actively updating
- **Real-time progress** — See exactly which package is being updated as it happens — click the menu bar during updates to watch live
- **Package details at a glance** — See outdated package names and version changes directly in the menu
- **Selective updates** — Update or skip individual packages
- **Greedy mode** — Optionally include apps that handle their own updates (Chrome, Slack, etc.) in both scheduled checks and upgrades
- **Auto cleanup** — Automatically runs standard `brew cleanup` after upgrades, with an optional deep-prune style for power users
- **Deep cache prune** — Manually run `brew cleanup --prune=all`, or opt Auto Cleanup into it from the Cleanup submenu
- **Admin retry for protected packages** — If a cask needs admin access, TopOff prompts for your password and retries automatically
- **Update history** — View recently updated packages with version changes
- **Configurable check interval** — Check every hour, 4 hours (default), 12 hours, 24 hours, or manually
- **Launch at login** — Always have TopOff ready
- **Desktop notifications** — Optional banner when an update run finishes, so you can kick off updates and walk away
- **Automatic retry on network restore** — If the app launches without internet (e.g., at startup before WiFi connects), it automatically checks for updates once connectivity is restored
- **In-app updates** — TopOff keeps itself up to date with [Sparkle](https://sparkle-project.org): signed updates, installed in place with one click
- **See what changed** — View upgraded packages and freed disk space in the menu

## Screenshots

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/topoff-demo-dark.gif">
  <img src="docs/assets/topoff-demo.gif" alt="TopOff Demo" width="252">
</picture>

The menu bar icon tells you at a glance if updates are available:

<img src="docs/assets/icon-states.png" alt="Menu bar icon states — up to date, updates available, updating, done" width="176">

| Icon | Meaning |
|------|---------|
| Full mug | All packages are up-to-date |
| Half-full mug | Updates are available (needs a refill!) |
| Spinning arrows | Checking for updates or updating — click to see live progress |
| Checkmark | Update completed successfully |

When an update run finishes, TopOff can post a desktop notification so you don't have to keep the menu open (on by default — toggle it under **Options → Notifications**):

<img src="docs/assets/notification.png" alt="TopOff desktop notification after an update finishes" width="394">

## Installation

### Download (Recommended)

1. Download the [latest DMG](https://github.com/ihazgithub/TopOff/releases/latest/download/TopOff-v2.1.dmg)
2. Open the DMG and drag TopOff to your Applications folder
3. Launch TopOff. It's signed and notarized by Apple, so it opens immediately on first launch — no trip through Privacy & Security needed.

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
- **Auto Cleanup** — Automatically runs standard `brew cleanup` after upgrades (on by default)
- **Cleanup** — Run standard cleanup, run **Deep Cache Prune…**, or choose the saved **Auto Cleanup Style**
- **Auto Cleanup Style** — Defaults to standard `brew cleanup`. Power users can opt into `brew cleanup --prune=all` after a confirmation step. This removes Homebrew cached downloads to reclaim more disk space, but does not uninstall apps or command line tools.
- **Greedy Mode** — Always check and update everything, including apps that auto-update themselves (off by default — see [Greedy Mode explained](#whats-the-difference-between-update-all-and-greedy))
- **Notifications** — Show a desktop banner when an update finishes (on by default)
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

Some casks (Chrome, Slack, VSCode, etc.) have built-in auto-update and are normally skipped by Homebrew. Greedy mode tells Homebrew to update them anyway.

**By default**, TopOff gives you both options:

| Button | Command | What it does |
|--------|---------|--------------|
| Update All | `brew upgrade` | Updates packages that don't auto-update themselves |
| Update All (Greedy) | `brew upgrade`, then `brew upgrade --greedy` | Updates everything, including apps that auto-update |

Scheduled background checks use normal mode, so those auto-updating apps won't show up as outdated.

**With Greedy Mode enabled** (in Options), TopOff switches to greedy everywhere:

- Scheduled checks use `brew outdated --greedy` so auto-updating apps appear as outdated
- The normal "Update All" button is hidden since "Update All (Greedy)" covers everything
- This is ideal if you prefer Homebrew to manage all your app updates in one place

Greedy Mode is off by default. You can toggle it anytime under **Options > Greedy Mode**.

## Privacy & Network Connections

TopOff makes only one network connection:

- **GitHub API** (`api.github.com`) — Checks for new TopOff releases on launch and periodically while running

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

## Attribution

TopOff is open source under the MIT License.

If you use, fork, or build on TopOff, attribution to Thomas Haslam and a link to the original project are appreciated where practical, such as in your README, credits, or release notes.

## Credits

Created by **Thomas Haslam**
