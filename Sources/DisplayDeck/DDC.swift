import CoreGraphics
import CPrivateAPI
import Foundation

// Codes MCCS : un écran n'est pas tenu de les gérer tous, d'où la lecture avant affichage.
enum VCP: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
}

struct VCPValue {
    let current: UInt16
    let maximum: UInt16
}

// Sendable à la main : `service` n'est touché que sur `queue`, `pendingWrites` que sur le main actor.
final class DDCDevice: @unchecked Sendable {
    private let service: AnyObject
    private let display: CGDirectDisplayID
    private let queue: DispatchQueue
    private var pendingWrites: [VCP: DispatchWorkItem] = [:]

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

    @MainActor
    func write(_ code: VCP, value: UInt16, of maximum: UInt16) {
        pendingWrites[code]?.cancel()
        let write = DispatchWorkItem { [self] in
            DDWriteVCP(service, code.rawValue, value)
            // macOS n'affiche aucun bandeau pour un écran externe : sans celui-ci, un réglage
            // lancé depuis un autre écran que celui réglé ne donne aucun retour visuel.
            if maximum > 0 {
                SystemOSD.show(code.osdImage, fraction: Double(value) / Double(maximum), on: display)
            }
        }
        pendingWrites[code] = write
        // l'I2C est bien plus lent qu'un slider : pendant un glissement, seule la dernière valeur part
        queue.asyncAfter(deadline: .now() + 0.1, execute: write)
    }

    // Bloquant (registre IOKit + lecture EDID) : à appeler hors du main thread.
    static func discover(for displays: [CGDirectDisplayID]) -> [CGDirectDisplayID: DDCDevice] {
        guard !displays.isEmpty else { return [:] }
        var services = DDExternalAVServices().map { AVService(ref: $0 as AnyObject) }
        var devices: [CGDirectDisplayID: DDCDevice] = [:]
        var unmatched: [CGDirectDisplayID] = []

        for display in displays {
            // le numéro de série distingue deux écrans de même modèle, que le couple
            // fabricant/modèle seul associait dans un ordre arbitraire
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
    let serial: UInt32
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
    var osdImage: DDOSDImage {
        switch self {
        case .brightness: DDOSDImageBrightness
        case .contrast: DDOSDImageContrast
        case .volume: DDOSDImageVolume
        }
    }
}
