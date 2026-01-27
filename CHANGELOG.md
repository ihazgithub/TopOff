# Changelog

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
