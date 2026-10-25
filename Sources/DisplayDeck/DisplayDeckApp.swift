import SwiftUI

@main
struct DisplayDeckApp: App {
    @StateObject private var displays = DisplayManager()
    @StateObject private var virtualDisplays = VirtualDisplays()

    var body: some Scene {
        MenuBarExtra("DisplayDeck", systemImage: "display.2") {
            MenuView(displays: displays, virtualDisplays: virtualDisplays)
        }
        .menuBarExtraStyle(.window)
    }
}
