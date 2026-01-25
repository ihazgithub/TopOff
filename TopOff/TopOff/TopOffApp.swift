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
