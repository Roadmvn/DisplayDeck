import CoreGraphics
import CPrivateAPI

enum BuiltinBrightness {
    static func isSupported(_ display: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(display) != 0 && DDCanChangeBrightness(display)
    }

    static func get(_ display: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        return DDGetBrightness(display, &value) ? Double(value) : nil
    }

    static func set(_ value: Double, on display: CGDirectDisplayID) {
        DDSetBrightness(display, Float(value))
    }

    // `observer` reçoit le contexte tel quel : un pointeur de fonction C ne capture rien.
    static func observe(
        _ display: CGDirectDisplayID,
        context: UnsafeMutableRawPointer?,
        observer: @convention(c) (CGDirectDisplayID, Float, UnsafeMutableRawPointer?) -> Void
    ) -> Bool {
        DDObserveBrightness(display, context, observer)
    }

    static func stopObserving(_ display: CGDirectDisplayID) {
        DDStopObservingBrightness(display)
    }

    static func stopObservingAll() {
        DDStopObservingAllBrightness()
    }
}

// La luminosité automatique n'existe que là où un capteur de lumière ambiante alimente l'écran.
enum AmbientLight {
    static func isSupported(_ display: CGDirectDisplayID) -> Bool {
        DDHasAmbientLightCompensation(display)
    }

    static func isEnabled(_ display: CGDirectDisplayID) -> Bool {
        DDAmbientLightCompensationEnabled(display)
    }

    static func set(_ enabled: Bool, on display: CGDirectDisplayID) {
        DDSetAmbientLightCompensation(display, enabled)
    }
}

enum SystemOSD {
    static let chiclets: UInt32 = 16

    // Appelé depuis la file DDC comme depuis le main actor : OSDManager est une API d'interface.
    static func show(_ image: DDOSDImage, fraction: Double, on display: CGDirectDisplayID) {
        let filled = UInt32((fraction * Double(chiclets)).rounded())
        DispatchQueue.main.async {
            DDShowOSD(image, display, filled, chiclets)
        }
    }
}

// L'assombrissement logiciel passe par la table gamma, ce qui marche sur n'importe quel écran, DDC ou non.
struct GammaFormula {
    struct Channel {
        var min: CGGammaValue = 0
        var max: CGGammaValue = 1
        var gamma: CGGammaValue = 1
    }

    var red = Channel()
    var green = Channel()
    var blue = Channel()

    static func current(of display: CGDirectDisplayID) -> GammaFormula {
        var formula = GammaFormula()
        let error = CGGetDisplayTransferByFormula(
            display,
            &formula.red.min, &formula.red.max, &formula.red.gamma,
            &formula.green.min, &formula.green.max, &formula.green.gamma,
            &formula.blue.min, &formula.blue.max, &formula.blue.gamma
        )
        return error == .success ? formula : GammaFormula()
    }

    func apply(dimmedBy factor: Double, to display: CGDirectDisplayID) {
        let k = CGGammaValue(factor)
        CGSetDisplayTransferByFormula(
            display,
            red.min, red.max * k, red.gamma,
            green.min, green.max * k, green.gamma,
            blue.min, blue.max * k, blue.gamma
        )
    }
}
