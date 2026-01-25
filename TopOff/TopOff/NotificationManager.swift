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
