import SwiftUI

@main
struct AnchrApp: App {
    var body: some Scene {
        MenuBarExtra("Anchr", systemImage: "circle.fill") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
