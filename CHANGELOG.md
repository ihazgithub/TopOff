# Changelog

## v1.4 — February 2026

### New Features

- **Update History** — View your recent package updates with version details. Access via Options → "View Update History" (stores last 20 updates)

### Fixes

- **Intel Mac support** — Now runs on both Apple Silicon and Intel Macs

---

## v1.3.1 — January 2026

### Improvements

- **Automatic retry on network restore** — If the app launches without internet access (e.g., at system startup before WiFi connects), it now automatically checks for updates once connectivity is restored

---

## v1.3 — January 2026

### New Features

- **Real-time update progress** — See exactly which package is being updated as it happens. Click the menu bar icon during an upgrade to watch the progress live — no more wondering what's going on behind the scenes
- **Admin retry for protected packages** — If a package needs admin access to update (common with cask apps like Chrome or Slack), TopOff detects the permission failure, prompts for your password via the standard macOS dialog, and retries automatically

### Improvements

- **Animated spinning icon** — The menu bar icon now visibly spins during updates so you can tell at a glance when TopOff is actively working
- **Fully interactive UI** — The app no longer freezes during brew operations — you can open the menu, check status, or quit at any time

---

## v1.2 — January 2026

### New Features

- **Outdated package details** — See exactly which packages need updating with version numbers (e.g., `node 20.1.0 → 22.0.0`) directly in the menu
- **Selective package updates** — Update individual packages one at a time, or skip packages you don't want to update right now (enable in Settings)
- **Brew cleanup** — Automatically cleans up old package versions after upgrades, freeing disk space. Shows how much space was reclaimed. Can be switched to manual mode in Settings
- **About window** — App info, credits, and a link to support development
- **Update checker** — Checks GitHub for new releases on launch and shows a subtle hint in the menu when an update is available. Manual "Check for Updates" button in the About window with clear feedback
- **Settings submenu** — All preferences organized in one place: Selective Updates, Auto Cleanup, Launch at Login, and Check Interval

### Improvements

- Package version details shown before and after updates
- Active status messages while operations are running
- Check Interval selector uses native macOS picker
- Package list capped at 5 with overflow indicator for cleaner menus

---

## v1.1.0 — January 2026

### New Features

- **Automatic background checking** — Periodically checks for outdated packages
- **Configurable check interval** — Every hour, 4 hours, 12 hours, 24 hours, or manual only

---

## v1.0 — January 2026

### Initial Release

- One-click Homebrew updates from the menu bar
- Greedy mode for apps with built-in auto-update
- Smart icon status (full mug = up-to-date, half mug = updates available)
- Launch at login
- Upgrade results displayed in menu
- System notifications on completion
