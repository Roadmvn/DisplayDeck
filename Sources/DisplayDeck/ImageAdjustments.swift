import CoreGraphics

// Tout passe par la table de couleur de l'écran : un LUT à une dimension, par canal. Elle courbe
// chaque canal indépendamment — assombrissement, contraste, gamma, température, inversion — mais
// elle ne les mélange jamais, ce qui met saturation, teinte et vibrance hors de sa portée : celles-ci
// exigeraient un calque composité par-dessus l'écran.
struct ImageAdjustments: Equatable {
    var dim = 1.0          // 0,1 … 1
    var contrast = 0.0     // −1 aplati … 1 doublé
    var gamma = 0.0        // −1 tons moyens assombris … 1 éclaircis
    var temperature = 0.0  // −1 chaud … 1 froid
    var isInverted = false

    static let neutral = ImageAdjustments()

    var isNeutral: Bool { self == .neutral }

    // Pente du contraste autour du gris moyen : −1 la divise par deux, +1 la double.
    private var slope: Double { pow(2, contrast) }

    // Exposant du gamma : la valeur positive éclaircit, donc l'exposant descend sous 1.
    private var exponent: Double { pow(2, -gamma) }

    // Gains par canal. Tous restent sous 1 : réchauffer en retirant du bleu ne peut pas écrêter,
    // alors qu'en ajouter du rouge le ferait sur toute zone déjà saturée.
    var gains: (red: Double, green: Double, blue: Double) {
        (
            red: temperature > 0 ? 1 - 0.30 * temperature : 1,
            green: 1 - 0.10 * abs(temperature),
            blue: temperature < 0 ? 1 + 0.30 * temperature : 1
        )
    }

    // La courbe commune aux trois canaux. `calibrated` est la valeur déjà passée par le profil de
    // l'écran : les réglages s'appliquent après lui, pour ne pas écraser l'étalonnage.
    func curve(_ calibrated: Double) -> Double {
        var value = (calibrated - 0.5) * slope + 0.5
        // borner avant la puissance : un exposant fractionnaire sur un négatif rendrait NaN
        value = pow(min(max(value, 0), 1), exponent)
        return isInverted ? 1 - value : value
    }
}

// La table courante de l'écran, étalonnage compris, qui sert de point de départ aux réglages.
struct ColorTable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    static func current(of display: CGDirectDisplayID) -> ColorTable? {
        let capacity = Int(CGDisplayGammaTableCapacity(display))
        guard capacity > 1 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, UInt32(capacity), &red, &green, &blue, &count) == .success,
              count > 1
        else { return nil }
        let used = Int(count)
        return ColorTable(
            red: Array(red.prefix(used)),
            green: Array(green.prefix(used)),
            blue: Array(blue.prefix(used))
        )
    }

    // Chaque canal part de sa propre courbe étalonnée, puis reçoit son gain de température.
    func applying(_ adjustments: ImageAdjustments) -> ColorTable {
        let gains = adjustments.gains
        func adjusted(_ calibrated: CGGammaValue, _ gain: Double) -> CGGammaValue {
            let value = adjustments.curve(Double(calibrated)) * gain * adjustments.dim
            return CGGammaValue(min(max(value, 0), 1))
        }
        return ColorTable(
            red: red.map { adjusted($0, gains.red) },
            green: green.map { adjusted($0, gains.green) },
            blue: blue.map { adjusted($0, gains.blue) }
        )
    }

    func apply(to display: CGDirectDisplayID) {
        CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue)
    }
}
