import Foundation
import UserNotifications

class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        // Must be set before any notification is delivered so foreground
        // presentation (willPresent) is consulted.
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            } else if !granted {
                print("Notification permission was not granted; completion notifications will be suppressed")
            }
        }
    }

    private func sendCompletionNotification(success: Bool, title: String, body: String) {
        // User-facing toggle in Options menu; nil (never set) means enabled.
        if let enabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool, !enabled {
            print("Notification suppressed: notifications disabled in Options")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                print("Notification not sent: authorization status \(settings.authorizationStatus.rawValue)")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = success ? .default : .defaultCritical

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

            center.add(request) { error in
                if let error = error {
                    print("Notification delivery failed: \(error)")
                }
            }
        }
    }

    func showCompletionNotification(success: Bool, message: String) {
        let title = "TopOff"
        let body: String
        if success {
            body = message.isEmpty ? "All packages updated! 🎉" : message
        } else {
            body = "Update failed: \(message)"
        }
        sendCompletionNotification(success: success, title: title, body: body)
    }

    func showCompletionNotification(success: Bool, title: String, body: String) {
        let resolvedBody: String
        if success {
            resolvedBody = body.isEmpty ? "All packages updated! 🎉" : body
        } else {
            resolvedBody = body
        }
        sendCompletionNotification(success: success, title: title, body: resolvedBody)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show banners even while TopOff is frontmost. A menu bar app is often
    /// "active" exactly when an update finishes (menu or popover open); without
    /// this, macOS silently suppresses the completion banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
