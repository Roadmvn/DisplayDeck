import Combine
import CoreGraphics
import CPrivateAPI

struct VirtualDisplayPreset: Identifiable {
    let width: UInt32
    let height: UInt32

    var id: String { label }
    var label: String { "\(width) × \(height) HiDPI" }

    static let all = [
        VirtualDisplayPreset(width: 1920, height: 1080),
        VirtualDisplayPreset(width: 2560, height: 1440),
        VirtualDisplayPreset(width: 1440, height: 900),
    ]
}

@MainActor
final class VirtualDisplays: ObservableObject {
    struct Item: Identifiable {
        let serial: UInt32
        let preset: VirtualDisplayPreset
        let display: CGVirtualDisplay

        var id: UInt32 { serial }
    }

    // Identifiants propres à l'app, qui servent aussi à exclure nos écrans virtuels de la recherche DDC.
    static let vendorID: UInt32 = 0x1164
    static let productID: UInt32 = 0xDD01

    @Published private(set) var items: [Item] = []

    func create(_ preset: VirtualDisplayPreset) -> Bool {
        // macOS mémorise réglages et disposition par numéro de série : reprendre le plus petit libre évite d'empiler des écrans fantômes
        var serial: UInt32 = 1
        while items.contains(where: { $0.serial == serial }) { serial += 1 }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = .main
        descriptor.name = "DisplayDeck \(serial)"
        descriptor.maxPixelsWide = preset.width * 2
        descriptor.maxPixelsHigh = preset.height * 2
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 600 * Double(preset.height) / Double(preset.width))
        descriptor.serialNum = serial
        descriptor.vendorID = Self.vendorID
        descriptor.productID = Self.productID
        descriptor.terminationHandler = { [weak self] _, display in
            self?.items.removeAll { $0.display === display }
        }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else { return false }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [
            CGVirtualDisplayMode(width: preset.width * 2, height: preset.height * 2, refreshRate: 60),
            CGVirtualDisplayMode(width: preset.width, height: preset.height, refreshRate: 60),
        ]
        guard display.apply(settings) else { return false }

        items.append(Item(serial: serial, preset: preset, display: display))
        return true
    }

    func remove(_ item: Item) {
        // relâcher la dernière référence au CGVirtualDisplay suffit à faire disparaître l'écran
        items.removeAll { $0.id == item.id }
    }
}
