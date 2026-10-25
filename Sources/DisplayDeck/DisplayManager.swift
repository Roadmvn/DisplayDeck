import AppKit
import Combine

struct Display: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let hasHardwareBrightness: Bool
    let modes: [DisplayModeOption]
    let currentModeID: DisplayModeOption.ID?
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published private(set) var ddcDevices: [CGDirectDisplayID: DDCDevice] = [:]
    @Published private(set) var dimFactors: [CGDirectDisplayID: Double] = [:]

    private var gammaBaselines: [CGDirectDisplayID: GammaFormula] = [:]
    private var refreshScheduled = false
    private var screenChanges: AnyCancellable?
    private let ddcDiscoveryQueue = DispatchQueue(label: "DisplayDeck.ddc-discovery")

    init() {
        refresh()
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        // NSScreen n'est à jour qu'après cette notification : sans elle, un écran tout juste branché garderait un nom générique
        screenChanges = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.setNeedsRefresh() }
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    func setDimFactor(_ factor: Double, for display: CGDirectDisplayID) {
        guard factor < 1 else {
            dimFactors[display] = nil
            gammaBaselines[display] = nil
            // la restauration ColorSync vaut pour tous les écrans, d'où la réapplication des autres
            CGDisplayRestoreColorSyncSettings()
            reapplyDimming()
            return
        }
        if gammaBaselines[display] == nil {
            gammaBaselines[display] = GammaFormula.current(of: display)
        }
        dimFactors[display] = factor
        gammaBaselines[display]?.apply(dimmedBy: factor, to: display)
    }

    fileprivate func setNeedsRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        // une reconfiguration déclenche une rafale de rappels (un par écran et par étape) : un seul rafraîchissement suffit
        DispatchQueue.main.async { [self] in
            refreshScheduled = false
            refresh()
        }
    }

    private func refresh() {
        let names = screenNames()
        displays = onlineDisplayIDs().map { id in
            // après un changement de mode, macOS ne retire plus l'écran virtuel avant la fin du processus :
            // sa résolution se choisit donc uniquement à la création
            let isOwnVirtual = CGDisplayVendorNumber(id) == VirtualDisplays.vendorID
            return Display(
                id: id,
                name: names[id] ?? "Écran \(id)",
                hasHardwareBrightness: BuiltinBrightness.isSupported(id),
                modes: isOwnVirtual ? [] : DisplayModes.list(for: id),
                currentModeID: DisplayModes.currentID(for: id)
            )
        }

        let online = Set(displays.map(\.id))
        dimFactors = dimFactors.filter { online.contains($0.key) }
        gammaBaselines = gammaBaselines.filter { online.contains($0.key) }
        // un changement de mode ou un branchement peut remettre la table gamma par défaut
        reapplyDimming()
        discoverDDC()
    }

    private func reapplyDimming() {
        for (display, factor) in dimFactors {
            gammaBaselines[display]?.apply(dimmedBy: factor, to: display)
        }
    }

    private func discoverDDC() {
        let externals = displays.map(\.id).filter {
            CGDisplayIsBuiltin($0) == 0 && CGDisplayVendorNumber($0) != VirtualDisplays.vendorID
        }
        // file série : les découvertes se terminent dans l'ordre, la dernière configuration l'emporte toujours
        ddcDiscoveryQueue.async {
            let devices = DDCDevice.discover(for: externals)
            DispatchQueue.main.async { self.ddcDevices = devices }
        }
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }
}

private func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { manager.setNeedsRefresh() }
}
