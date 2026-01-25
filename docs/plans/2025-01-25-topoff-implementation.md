# TopOff Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that runs Homebrew updates with one click.

**Architecture:** SwiftUI app using MenuBarExtra for the menu bar interface. BrewService handles shell command execution asynchronously. NotificationManager wraps UserNotifications. SMAppService handles launch-at-login.

**Tech Stack:** Swift, SwiftUI, MenuBarExtra, Process, UserNotifications, SMAppService, macOS 13+

---

### Task 1: Create Xcode Project Structure

**Files:**
- Create: `TopOff/TopOff.xcodeproj` (Xcode project)
- Create: `TopOff/TopOff/TopOffApp.swift`
- Create: `TopOff/TopOff/Assets.xcassets/`
- Create: `TopOff/TopOff/TopOff.entitlements`

**Step 1: Create the Xcode project directory structure**

```bash
mkdir -p "TopOff/TopOff/Assets.xcassets/AppIcon.appiconset"
mkdir -p "TopOff/TopOff/Assets.xcassets/MenuBarIcon.imageset"
mkdir -p "TopOff/TopOff/Assets.xcassets/MenuBarFull.imageset"
mkdir -p "TopOff/TopOff/Assets.xcassets/MenuBarSpinner.imageset"
mkdir -p "TopOff/TopOff/Assets.xcassets/DancingStickFigure.imageset"
mkdir -p "TopOff/TopOffTests"
```

**Step 2: Create the Swift Package-style project.pbxproj**

Create `TopOff/TopOff.xcodeproj/project.pbxproj` with proper Xcode project configuration for a macOS menu bar app targeting macOS 13.0+.

**Step 3: Create entitlements file**

Create `TopOff/TopOff/TopOff.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

Note: Sandbox disabled because we need to run `/opt/homebrew/bin/brew`.

**Step 4: Create minimal app entry point**

Create `TopOff/TopOff/TopOffApp.swift`:
```swift
import SwiftUI

@main
struct TopOffApp: App {
    var body: some Scene {
        MenuBarExtra("TopOff", systemImage: "mug") {
            Text("TopOff")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

**Step 5: Create asset catalog Contents.json**

Create `TopOff/TopOff/Assets.xcassets/Contents.json`:
```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 6: Build and verify**

Run: `cd TopOff && xcodebuild -scheme TopOff -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add TopOff/
git commit -m "feat: create TopOff Xcode project structure"
```

---

### Task 2: Implement BrewService

**Files:**
- Create: `TopOff/TopOff/BrewService.swift`
- Create: `TopOff/TopOffTests/BrewServiceTests.swift`

**Step 1: Write the BrewService interface and tests**

Create `TopOff/TopOffTests/BrewServiceTests.swift`:
```swift
import XCTest
@testable import TopOff

final class BrewServiceTests: XCTestCase {

    func testBrewPathExists() {
        let service = BrewService()
        XCTAssertNotNil(service.brewPath, "Brew path should be found")
    }

    func testFindBrewPathAppleSilicon() {
        let service = BrewService()
        let path = service.findBrewPath()
        // Should find either Apple Silicon or Intel path
        XCTAssertTrue(
            path == "/opt/homebrew/bin/brew" || path == "/usr/local/bin/brew",
            "Should find valid brew path"
        )
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd TopOff && xcodebuild test -scheme TopOff -destination 'platform=macOS'`
Expected: FAIL - BrewService not defined

**Step 3: Implement BrewService**

Create `TopOff/TopOff/BrewService.swift`:
```swift
import Foundation

enum BrewError: Error, LocalizedError {
    case brewNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew not found. Please install Homebrew first."
        case .commandFailed(let message):
            return "Brew command failed: \(message)"
        }
    }
}

@MainActor
class BrewService: ObservableObject {
    @Published var isRunning = false
    @Published var lastOutput: String = ""

    let brewPath: String?

    init() {
        self.brewPath = Self.findBrewPath()
    }

    static func findBrewPath() -> String? {
        let appleSiliconPath = "/opt/homebrew/bin/brew"
        let intelPath = "/usr/local/bin/brew"

        if FileManager.default.fileExists(atPath: appleSiliconPath) {
            return appleSiliconPath
        } else if FileManager.default.fileExists(atPath: intelPath) {
            return intelPath
        }
        return nil
    }

    func findBrewPath() -> String? {
        Self.findBrewPath()
    }

    func updateAll(greedy: Bool = false) async throws -> String {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        isRunning = true
        defer { isRunning = false }

        // Run brew update
        let updateOutput = try await runCommand(brewPath, arguments: ["update"])

        // Run brew upgrade
        var upgradeArgs = ["upgrade"]
        if greedy {
            upgradeArgs.append("--greedy")
        }
        let upgradeOutput = try await runCommand(brewPath, arguments: upgradeArgs)

        let fullOutput = updateOutput + "\n" + upgradeOutput
        lastOutput = fullOutput
        return fullOutput
    }

    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            // Set up environment to find brew dependencies
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "")
            process.environment = environment

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: BrewError.commandFailed(output))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd TopOff && xcodebuild test -scheme TopOff -destination 'platform=macOS'`
Expected: PASS

**Step 5: Commit**

```bash
git add TopOff/TopOff/BrewService.swift TopOff/TopOffTests/BrewServiceTests.swift
git commit -m "feat: add BrewService for running brew commands"
```

---

### Task 3: Implement NotificationManager

**Files:**
- Create: `TopOff/TopOff/NotificationManager.swift`

**Step 1: Create NotificationManager**

Create `TopOff/TopOff/NotificationManager.swift`:
```swift
import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func showCompletionNotification(success: Bool, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "TopOff"

        if success {
            content.body = "All packages updated! 🎉"
            content.sound = .default
        } else {
            content.body = "Update failed: \(message)"
            content.sound = .defaultCritical
        }

        // Use custom notification icon if available
        if let imageURL = Bundle.main.url(forResource: "DancingStickFigure", withExtension: "png") {
            if let attachment = try? UNNotificationAttachment(identifier: "image", url: imageURL, options: nil) {
                content.attachments = [attachment]
            }
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
```

**Step 2: Build to verify**

Run: `cd TopOff && xcodebuild -scheme TopOff -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add TopOff/TopOff/NotificationManager.swift
git commit -m "feat: add NotificationManager for completion notifications"
```

---

### Task 4: Implement Menu Bar UI with Icon States

**Files:**
- Modify: `TopOff/TopOff/TopOffApp.swift`
- Create: `TopOff/TopOff/MenuBarViewModel.swift`

**Step 1: Create MenuBarViewModel**

Create `TopOff/TopOff/MenuBarViewModel.swift`:
```swift
import SwiftUI
import ServiceManagement

enum MenuBarIconState {
    case idle        // Half-filled mug
    case running     // Spinner
    case checkmark   // Brief checkmark
    case complete    // Full mug

    var systemImage: String {
        switch self {
        case .idle:
            return "mug"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .checkmark:
            return "checkmark.circle.fill"
        case .complete:
            return "mug.fill"
        }
    }
}

@MainActor
class MenuBarViewModel: ObservableObject {
    @Published var iconState: MenuBarIconState = .idle
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    private let brewService = BrewService()
    private let notificationManager = NotificationManager.shared

    var isRunning: Bool {
        brewService.isRunning
    }

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        notificationManager.requestPermission()
    }

    func updateAll(greedy: Bool) {
        Task {
            iconState = .running

            do {
                _ = try await brewService.updateAll(greedy: greedy)
                await showSuccessAnimation()
                notificationManager.showCompletionNotification(success: true, message: "")
            } catch {
                iconState = .idle
                notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
            }
        }
    }

    private func showSuccessAnimation() async {
        // Checkmark for 1 second
        iconState = .checkmark
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Full mug for 2 seconds
        iconState = .complete
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Back to idle
        iconState = .idle
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
```

**Step 2: Update TopOffApp with full menu**

Replace `TopOff/TopOff/TopOffApp.swift`:
```swift
import SwiftUI

@main
struct TopOffApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            Button("Update All") {
                viewModel.updateAll(greedy: false)
            }
            .disabled(viewModel.isRunning)

            Button("Update All (Greedy)") {
                viewModel.updateAll(greedy: true)
            }
            .disabled(viewModel.isRunning)

            Divider()

            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: viewModel.iconState.systemImage)
                .symbolEffect(.pulse, isActive: viewModel.iconState == .running)
        }
    }
}
```

**Step 3: Build and verify**

Run: `cd TopOff && xcodebuild -scheme TopOff -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add TopOff/TopOff/MenuBarViewModel.swift TopOff/TopOff/TopOffApp.swift
git commit -m "feat: implement menu bar UI with icon states and actions"
```

---

### Task 5: Create Asset Placeholders

**Files:**
- Create: `TopOff/TopOff/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `TopOff/TopOff/Assets.xcassets/DancingStickFigure.imageset/Contents.json`

**Step 1: Create AppIcon Contents.json**

Create `TopOff/TopOff/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 2: Create DancingStickFigure imageset**

Create `TopOff/TopOff/Assets.xcassets/DancingStickFigure.imageset/Contents.json`:
```json
{
  "images" : [
    {
      "filename" : "DancingStickFigure.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 3: Create a simple placeholder PNG for dancing stick figure**

We'll create a simple SVG and convert it, or just note that custom artwork is needed.

Create placeholder note `TopOff/TopOff/Assets.xcassets/DancingStickFigure.imageset/README.md`:
```markdown
# Dancing Stick Figure Asset

Replace DancingStickFigure.png with a 64x64 or 128x128 PNG of a dancing stick figure.

This image appears in the macOS notification when updates complete successfully.
```

**Step 4: Commit**

```bash
git add TopOff/TopOff/Assets.xcassets/
git commit -m "feat: add asset catalog structure with placeholders"
```

---

### Task 6: Create Xcode Project File

**Files:**
- Create: `TopOff/TopOff.xcodeproj/project.pbxproj`

**Step 1: Generate project.pbxproj**

This is the most complex file. Create `TopOff/TopOff.xcodeproj/project.pbxproj` with the full Xcode project configuration including:
- TopOff target (macOS app)
- TopOffTests target (unit tests)
- Build settings for macOS 13.0+
- Code signing settings
- Asset catalog references
- Source file references

**Step 2: Build the complete project**

Run: `cd TopOff && xcodebuild -scheme TopOff -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 3: Run tests**

Run: `cd TopOff && xcodebuild test -scheme TopOff -destination 'platform=macOS'`
Expected: All tests pass

**Step 4: Commit**

```bash
git add TopOff/TopOff.xcodeproj/
git commit -m "feat: add complete Xcode project configuration"
```

---

### Task 7: Manual Testing & Polish

**Step 1: Open in Xcode and run**

Run: `open TopOff/TopOff.xcodeproj`

**Step 2: Manual test checklist**

- [ ] App appears in menu bar with mug icon
- [ ] Clicking "Update All" runs brew update && brew upgrade
- [ ] Icon changes to spinner while running
- [ ] Icon shows checkmark, then full mug, then back to half mug
- [ ] Notification appears on completion
- [ ] "Update All (Greedy)" runs with --greedy flag
- [ ] "Launch at Login" toggle works and persists
- [ ] "Quit" terminates the app

**Step 3: Fix any issues found**

Address any bugs discovered during manual testing.

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: polish and bug fixes from manual testing"
```

---

## Summary

| Task | Description |
|------|-------------|
| 1 | Create Xcode project structure |
| 2 | Implement BrewService with tests |
| 3 | Implement NotificationManager |
| 4 | Implement Menu Bar UI with icon states |
| 5 | Create asset placeholders |
| 6 | Create Xcode project file |
| 7 | Manual testing & polish |

Total: 7 tasks to complete TopOff.
