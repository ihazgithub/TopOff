# TopOff - Design Document

A lightweight macOS menu bar app for one-click Homebrew updates.

## Overview

**Problem:** Running `brew update && brew upgrade` requires opening Terminal and typing commands.

**Solution:** A menu bar app with two buttons - one for normal updates, one for greedy updates (forces updates on auto-updating apps).

## User Interface

### Menu Bar Icon States

| State | Icon | Duration |
|-------|------|----------|
| Idle | Half-filled mug | Default |
| Running | Spinner | While command runs |
| Success | Checkmark | 1 second |
| Complete | Full mug | 2 seconds, then back to idle |

### Dropdown Menu

```
┌─────────────────────────┐
│ Update All              │
│ Update All (Greedy)     │
├─────────────────────────┤
│ ✓ Launch at Login       │
├─────────────────────────┤
│ Quit                    │
└─────────────────────────┘
```

## Behavior

### Update Flow

1. User clicks "Update All" or "Update All (Greedy)"
2. Icon changes to spinner
3. App runs the appropriate brew command
4. On completion:
   - Icon: checkmark (1s) → full mug (2s) → half-filled mug
   - macOS notification with dancing stick figure icon
5. On error: notification shows error message, icon returns to half-filled

### Commands

- **Update All:** `brew update && brew upgrade`
- **Update All (Greedy):** `brew update && brew upgrade --greedy`

### Launch at Login

- Toggle persisted via `UserDefaults`
- Uses `SMAppService` API to register/unregister

## Technical Architecture

### Project Structure

```
TopOff/
├── TopOffApp.swift           # App entry point, menu bar setup
├── BrewService.swift         # Runs brew commands, captures output
├── NotificationManager.swift # Handles macOS notifications
├── Assets.xcassets/
│   ├── MenuBarIcon           # Half-filled mug (idle)
│   ├── MenuBarFull           # Full mug (success)
│   ├── DancingStickFigure    # Notification icon
│   └── AppIcon               # App icon
└── Info.plist
```

### Key Components

- **MenuBarExtra** (SwiftUI) - Native menu bar API for macOS 13+
- **Process** - Runs shell commands asynchronously
- **UserNotifications** - System notifications
- **SMAppService** - Launch at login registration

### Requirements

- macOS 13.0+
- Homebrew installed at `/opt/homebrew/bin/brew` (Apple Silicon) or `/usr/local/bin/brew` (Intel)

## Assets

| Asset | Format | Notes |
|-------|--------|-------|
| Half-filled mug | SF Symbol or PNG 16x16 @1x/@2x | Menu bar idle state |
| Full mug | SF Symbol or PNG 16x16 @1x/@2x | Success state |
| Checkmark | SF Symbol `checkmark.circle.fill` | Brief success indicator |
| Dancing stick figure | PNG | Notification icon |
| App icon | PNG 512x512, 256x256, 128x128, etc. | Standard macOS app icon |

## Out of Scope

- Viewing list of outdated packages
- Selective package updates
- Package search/install
- Update scheduling
- Background update checking
