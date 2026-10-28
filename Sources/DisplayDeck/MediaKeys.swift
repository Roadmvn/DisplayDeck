import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hidsystem

// Les touches de luminosité n'arrivent pas comme des événements clavier mais comme des
// `systemDefined` de sous-type 8, où le code de touche est empaqueté dans `data1`. Les intercepter
// demande un CGEventTap modifiant, donc l'autorisation d'accessibilité.
@MainActor
final class MediaKeys: ObservableObject {
    // Un pas vaut une case du bandeau système, dont macOS dessine seize.
    static let step = 1.0 / Double(SystemOSD.chiclets)
    // macOS affine au quart de case tant que Majuscule et Option sont enfoncées.
    static let fineStep = step / 4

    // `nonisolated` : le rappel du tap les lit hors du main actor.
    nonisolated private static let enabledKey = "keyboardBrightnessEnabled"
    nonisolated private static let subtypeAuxControlButtons = 8
    nonisolated private static let keyStateDown = 0x0A
    // `CGEventType` ne nomme pas cette valeur côté Swift ; AppKit la publie, et c'est la même.
    nonisolated private static let systemDefined = UInt32(NSEvent.EventType.systemDefined.rawValue)

    @Published private(set) var isAuthorized = AXIsProcessTrusted()
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }

    private let displays: DisplayManager
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(displays: DisplayManager) {
        self.displays = displays
        let stored = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        isEnabled = stored ?? true
        start()
    }

    // Pas de `deinit` : l'objet vit autant que l'app, et `stop()` couvre le seul démontage réel,
    // celui de l'interrupteur ou de l'autorisation retirée.

    // La fenêtre système n'apparaît qu'une fois par app ; ensuite seuls les Réglages font foi.
    func requestAuthorization() {
        // littéral plutôt que `kAXTrustedCheckOptionPrompt`, que le SDK déclare en `var` globale
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refreshAuthorization()
    }

    // Appelé à l'ouverture du menu : l'autorisation accordée prend effet sans relancer l'app.
    func refreshAuthorization() {
        isAuthorized = AXIsProcessTrusted()
        isAuthorized ? start() : stop()
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func start() {
        guard isEnabled, isAuthorized, tap == nil else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << Self.systemDefined),
            callback: mediaKeyTapped,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
    }

    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.tap = nil
        runLoopSource = nil
    }

    // `nonisolated` car le tap appelle ceci directement ; `CGEvent` n'est pas `Sendable`, donc le
    // décodage reste ici et seules des valeurs franchissent la frontière du main actor.
    nonisolated fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let unchanged = Unmanaged.passUnretained(event)

        // Un tap que le système a coupé ne se rallume pas de lui-même.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated { reenable() }
            return unchanged
        }

        guard type.rawValue == Self.systemDefined,
              let media = NSEvent(cgEvent: event),
              media.subtype.rawValue == Self.subtypeAuxControlButtons
        else { return unchanged }

        let direction: Double
        switch Int32((media.data1 & 0xFFFF_0000) >> 16) {
        case NX_KEYTYPE_BRIGHTNESS_UP: direction = 1
        case NX_KEYTYPE_BRIGHTNESS_DOWN: direction = -1
        default: return unchanged
        }

        let isDown = (media.data1 & 0x0000_FF00) >> 8 == Self.keyStateDown
        let fine = media.modifierFlags.isSuperset(of: [.shift, .option])
        let handled = MainActor.assumeIsolated { adjust(direction: direction, isDown: isDown, fine: fine) }

        // Le relâchement ne règle rien mais s'absorbe aussi : une moitié de frappe laissée passer
        // ferait varier l'écran intégré en même temps.
        return handled ? nil : unchanged
    }

    private func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Rend `false` quand aucun écran DDC n'est visé : macOS règle alors l'écran intégré comme d'habitude.
    private func adjust(direction: Double, isDown: Bool, fine: Bool) -> Bool {
        guard let display = targetDisplay(), displays.hasDDC(.brightness, for: display) else { return false }
        if isDown {
            displays.stepDDC(.brightness, by: direction * (fine ? Self.fineStep : Self.step), for: display)
        }
        return true
    }

    // L'écran sous le pointeur : c'est le seul indice dont dispose une app sans fenêtre.
    private func targetDisplay() -> CGDirectDisplayID? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }
}

// Le tap appelle ceci sur la boucle principale, celle à laquelle sa source est rattachée.
private let mediaKeyTapped: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let keys = Unmanaged<MediaKeys>.fromOpaque(userInfo).takeUnretainedValue()
    return keys.handle(type, event)
}
