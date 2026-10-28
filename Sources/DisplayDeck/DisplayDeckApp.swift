import SwiftUI

@main
struct DisplayDeckApp: App {
    @StateObject private var displays: DisplayManager
    @StateObject private var virtualDisplays = VirtualDisplays()
    @StateObject private var mediaKeys: MediaKeys

    // Le contenu d'un `MenuBarExtra` n'existe qu'une fois le menu ouvert : l'interception des
    // touches doit donc se mettre en place ici, sinon elle n'agirait qu'après la première ouverture.
    init() {
        let displays = DisplayManager()
        _displays = StateObject(wrappedValue: displays)
        _mediaKeys = StateObject(wrappedValue: MediaKeys(displays: displays))
    }

    var body: some Scene {
        MenuBarExtra("DisplayDeck", systemImage: "display.2") {
            MenuView(displays: displays, virtualDisplays: virtualDisplays, mediaKeys: mediaKeys)
        }
        .menuBarExtraStyle(.window)
    }
}
