import CoreGraphics
import Foundation

struct DisplayModeOption: Identifiable {
    let mode: CGDisplayMode

    var width: Int { mode.width }
    var height: Int { mode.height }
    var isHiDPI: Bool { mode.pixelWidth > mode.width }
    var refreshRate: Double { mode.refreshRate }

    var id: String { "\(width)x\(height)-\(isHiDPI)-\(Int((refreshRate * 100).rounded()))" }

    var label: String {
        var parts = ["\(width) × \(height)"]
        if isHiDPI { parts.append("HiDPI") }
        if refreshRate > 0 { parts.append(String(format: "%g Hz", refreshRate)) }
        return parts.joined(separator: " · ")
    }
}

enum DisplayModes {
    static func list(for display: CGDirectDisplayID) -> [DisplayModeOption] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
        var seen = Set<String>()
        return modes
            .filter { $0.isUsableForDesktopGUI() }
            .map(DisplayModeOption.init)
            .filter { seen.insert($0.id).inserted }
            .sorted {
                ($0.width, $0.height, $0.isHiDPI ? 1 : 0, $0.refreshRate)
                    > ($1.width, $1.height, $1.isHiDPI ? 1 : 0, $1.refreshRate)
            }
    }

    static func currentID(for display: CGDirectDisplayID) -> DisplayModeOption.ID? {
        CGDisplayCopyDisplayMode(display).map { DisplayModeOption(mode: $0).id }
    }

    static func apply(_ option: DisplayModeOption, to display: CGDirectDisplayID) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        if CGConfigureDisplayWithDisplayMode(config, display, option.mode, nil) == .success {
            CGCompleteDisplayConfiguration(config, .permanently)
        } else {
            CGCancelDisplayConfiguration(config)
        }
    }
}
