import CoreGraphics
import CPrivateAPI
import Foundation

// Codes MCCS : un écran n'est pas tenu de les gérer tous, d'où la lecture avant affichage.
enum VCP: UInt8, CaseIterable {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
    case power = 0xD6

    // `power` commande une extinction, pas un niveau : elle n'a pas de curseur.
    static let sliders: [VCP] = [.brightness, .contrast, .volume]
}

// Valeurs d'alimentation du MCCS. Le minimum d'un curseur de luminosité n'éteint pas un écran :
// il laisse le rétroéclairage à son plus bas, et seule cette commande le coupe vraiment.
enum DisplayPower: UInt16 {
    case on = 0x01
    case off = 0x04
}

struct VCPValue {
    let current: UInt16
    let maximum: UInt16
}

// Sendable à la main : `service` n'est touché que sur `queue`, `latest` et `isDraining` que sur le main actor.
final class DDCDevice: @unchecked Sendable {
    // Mesuré à 1,85 ms par écriture sur le bus : l'intervalle ne protège pas le bus mais le
    // contrôleur de l'écran, que des trames trop rapprochées perturbent.
    private static let minimumInterval = 0.05

    private let service: AnyObject
    private let display: CGDirectDisplayID
    private let queue: DispatchQueue
    private var latest: [VCP: (value: UInt16, maximum: UInt16)] = [:]
    private var isDraining: Set<VCP> = []

    private init(service: AnyObject, display: CGDirectDisplayID) {
        self.service = service
        self.display = display
        queue = DispatchQueue(label: "DisplayDeck.ddc.\(display)")
    }

    func read(_ code: VCP) async -> VCPValue? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var current: UInt16 = 0
                var maximum: UInt16 = 0
                let ok = DDReadVCP(service, code.rawValue, &current, &maximum)
                continuation.resume(returning: ok ? VCPValue(current: current, maximum: maximum) : nil)
            }
        }
    }

    // La première valeur part tout de suite ; celles qui arrivent ensuite écrasent la précédente
    // et sortent au rythme de `minimumInterval`. Reporter chaque écriture d'un délai fixe, comme
    // avant, ne laissait rien partir tant que la touche restait enfoncée ou le curseur en mouvement.
    @MainActor
    func write(_ code: VCP, value: UInt16, of maximum: UInt16) {
        latest[code] = (value, maximum)
        guard !isDraining.contains(code) else { return }
        isDraining.insert(code)
        drain(code)
    }

    @MainActor
    private func drain(_ code: VCP) {
        guard let next = latest.removeValue(forKey: code) else {
            isDraining.remove(code)
            return
        }
        queue.async { [self] in
            DDWriteVCP(service, code.rawValue, next.value)
            // macOS n'affiche aucun bandeau pour un écran externe : sans celui-ci, un réglage
            // lancé depuis un autre écran que celui réglé ne donne aucun retour visuel.
            if let image = code.osdImage, next.maximum > 0 {
                SystemOSD.show(image, fraction: Double(next.value) / Double(next.maximum), on: display)
            }
            // bloquer cette file privée ne retient que nos propres écritures
            Thread.sleep(forTimeInterval: Self.minimumInterval)
            Task { @MainActor in self.drain(code) }
        }
    }

    // Bloquant (registre IOKit + lecture EDID) : à appeler hors du main thread.
    static func discover(for displays: [CGDirectDisplayID]) -> [CGDirectDisplayID: DDCDevice] {
        guard !displays.isEmpty else { return [:] }
        var services = DDExternalAVServices().map { AVService(ref: $0 as AnyObject) }
        var devices: [CGDirectDisplayID: DDCDevice] = [:]
        var unmatched: [CGDirectDisplayID] = []

        // Première passe avec le numéro de série, qui seul distingue deux écrans du même modèle.
        for display in displays {
            let identity = EDIDIdentity(
                vendor: CGDisplayVendorNumber(display),
                product: CGDisplayModelNumber(display),
                serial: CGDisplaySerialNumber(display)
            )
            if let index = services.firstIndex(where: { $0.identity == identity }) {
                devices[display] = DDCDevice(service: services.remove(at: index).ref, display: display)
            } else {
                unmatched.append(display)
            }
        }

        // Tous les écrans ne publient pas leur série dans les octets 12-15 de l'EDID : certains la
        // rangent dans un bloc descripteur, que CoreGraphics peut résumer autrement. Retomber sur
        // fabricant/modèle préserve alors l'appariement que la seule première passe aurait perdu.
        for display in unmatched {
            let identity = EDIDIdentity(vendor: CGDisplayVendorNumber(display), product: CGDisplayModelNumber(display), serial: nil)
            if let index = services.firstIndex(where: { $0.identity?.ignoringSerial == identity }) {
                devices[display] = DDCDevice(service: services.remove(at: index).ref, display: display)
            }
        }
        unmatched.removeAll { devices[$0] != nil }
        // EDID illisible ou incohérent : avec un seul candidat de chaque côté, l'association reste sans ambiguïté
        if unmatched.count == 1, services.count == 1 {
            devices[unmatched[0]] = DDCDevice(service: services[0].ref, display: unmatched[0])
        }
        return devices
    }
}

private struct EDIDIdentity: Equatable {
    let vendor: UInt32
    let product: UInt32
    let serial: UInt32?

    var ignoringSerial: EDIDIdentity { EDIDIdentity(vendor: vendor, product: product, serial: nil) }
}

private struct AVService {
    let ref: AnyObject
    let identity: EDIDIdentity?

    init(ref: AnyObject) {
        self.ref = ref
        var vendor: UInt32 = 0
        var product: UInt32 = 0
        var serial: UInt32 = 0
        identity = DDReadEDIDIdentity(ref, &vendor, &product, &serial)
            ? EDIDIdentity(vendor: vendor, product: product, serial: serial)
            : nil
    }
}

private extension VCP {
    // `nil` pour une commande qui ne représente pas un niveau : aucun bandeau à montrer.
    var osdImage: DDOSDImage? {
        switch self {
        case .brightness: DDOSDImageBrightness
        case .contrast: DDOSDImageContrast
        case .volume: DDOSDImageVolume
        case .power: nil
        }
    }
}
