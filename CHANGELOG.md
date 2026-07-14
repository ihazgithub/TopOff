# Changelog

## v2.0.2 — June 2026

### Fixes

- **Self-updating apps now finish updating** — Some casks that manage their own updates (for example DuckDuckGo) could sit in the menu as outdated and never clear, no matter how many times you ran Update All. Homebrew refuses to upgrade these in place — even in Greedy mode — and instead needs a forced reinstall, which TopOff wasn't doing. TopOff now detects that case and completes the update with a forced reinstall, from Update All, Update All (Greedy), and the per-package Update.

### Notes

- Supports macOS 14 and later. Universal binary for Apple Silicon and Intel.

---

## v2.0.1 — June 2026

### Fixes

- **Correct package counts in Last Update and History** — Updates could be double-counted: each upgraded package sometimes appeared twice — once correctly and once as a phantom `? → ?` row — so the menu and Update History showed too many packages (for example "4 packages" when only two updated). The cause was a recent change to Homebrew's upgrade output, which now lines versions up into columns; TopOff's parser misread the extra spacing and even folded a package's old version into its name. TopOff now reads the column-aligned output correctly, counts each package once, and shows its real version change. History saved by an affected version is cleaned up automatically the next time you launch.

### Notes

- Existing settings and history carry over; the one-time history cleanup needs no action.
- Supports macOS 14 and later. Universal binary for Apple Silicon and Intel.

---

## v2.0 — June 2026

### Headline

- **Signed and notarized by Apple** — installs cleanly on first launch. No more visiting System Settings → Privacy & Security or clicking "Open Anyway."

### Improvements

- **Native admin password prompt** — replaces the old AppleScript dialog with a native window that names the package needing access and allows up to three retries on a wrong password.
- **Persistent Skipped Packages** — optional Remember mode in Options keeps Skip choices across checks and restarts; a Manage window lets you clear saved skips.
- **"All packages up to date" confirmation** — a subtle green check line appears in the menu when nothing is outdated.
- **History grouped by date** — Update History now uses Today / Yesterday / day-name / date headers.
- **Friendlier error messages** — common Homebrew failures (network, disk full, missing Command Line Tools, busy lock, removed casks) show clear titles and suggestions instead of raw CLI output.
- **Cleaner outdated rows** — show just the package name, so the menu stays narrow.
- **Smarter version display** — collapses long cask version strings (e.g. `2506-8.16.0-16536825094,CART26FQ2_MAC_2506`) down to the semver-shaped core (`8.16.0`).

### Fixes

- **Per-package Update works on auto-updating casks** — apps like Omnissa Horizon Client no longer fail silently.
- **Admin-protected cask installs no longer deadlock** — the multi-step sudo handoff has been reworked.
- **Cancel actually stops Homebrew** — uses SIGKILL on the process group so brew halts within seconds instead of finishing on its own.
- **Submenu hover works during active updates** — outdated rows open their Update/Skip submenu reliably while another update is running.

### Notes

- Existing settings carry over; no manual migration needed.
- Supports macOS 14 and later. Universal binary for Apple Silicon and Intel.

---

## v1.8.3 — May 2026

### Improvements

- **Optional Auto Cleanup deep prune** — Power users can now set Auto Cleanup to run `brew cleanup --prune=all` after successful updates; standard cleanup remains the default
- **Cleaner Cleanup menu** — Cleanup actions now live under a dedicated Options → Cleanup submenu with the deep-prune auto style tucked away as an advanced choice

### Fixes

- **Launchpad icon rendering** — Updated the app icon assets so TopOff keeps rounded transparent corners on macOS Sequoia Launchpad

---

## v1.8.2 — May 2026

### Improvements

- **Manual Deep Cache Prune** — Added a deliberate, confirmation-protected option to run `brew cleanup --prune=all` without changing the default Auto Cleanup behavior
- **Always-available manual cleanup** — Standard cleanup can now be run from Options at any time

---

## v1.8.1 — May 2026

### Improvements

- **Clearer update progress** — Update All now shows which Homebrew items are queued and which item is currently updating or being repaired
- **More self-sufficient Greedy updates** — Interrupted cask upgrades are now repaired automatically instead of being shown repeatedly as normal updates

### Fixes

- **Fixed stuck Greedy cask updates** — TopOff now recovers from stale Homebrew `.upgrading` cask folders that could cause apps like DuckDuckGo or Google Chrome to appear again on every update attempt
- **More reliable update history** — Update history now only records packages after TopOff verifies that Homebrew no longer reports them as outdated

---

## v1.8 — May 2026

### Improvements

- **Refreshed app artwork** — TopOff has a new app icon and updated release artwork for a cleaner, more polished look
- **Background app update checks** — TopOff now checks for new app releases on launch and periodically while running

### Fixes

- **Fixed Greedy updates** — Update All (Greedy) now upgrades regular outdated packages as well as greedy-only casks
- **Improved Greedy Mode update history** — Version changes for greedy cask upgrades are now captured more reliably when Homebrew reports them in its upgrade summary

---

## v1.7.1 — April 2026

### Improvements

- **Refined menu bar mug icons** — Tightened the full and half mug artwork for a cleaner look while keeping the original TopOff character
- **Vector-backed menu bar assets** — Switched the menu bar image sets to SVG-backed assets for cleaner rendering and simpler maintenance

### Fixes

- **Asset catalog cleanup** — Added the missing accent color asset and removed asset-catalog warnings from the build

---

## v1.7 — March 2026

### Improvements

- **Spinner stays visible during updates** — The menu bar icon now keeps rotating even while the menu is open, so it’s clear an update is still in progress
- **Greedy Mode help text** — Added a tooltip explaining that Greedy Mode includes apps with built-in auto-update in both checks and upgrades

---

## v1.6.0 — March 2026

### Fixes

- **Admin update flow fixed** — Retrying protected upgrades now uses a Homebrew-compatible authentication path, so updates continue after entering your password instead of stalling

---

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
