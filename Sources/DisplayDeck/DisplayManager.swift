import AppKit
import Combine

struct Display: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let hasHardwareBrightness: Bool
    let hasAutoBrightness: Bool
    let modes: [DisplayModeOption]
    let currentModeID: DisplayModeOption.ID?
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published private(set) var ddcDevices: [CGDirectDisplayID: DDCDevice] = [:]
    @Published private(set) var dimFactors: [CGDirectDisplayID: Double] = [:]
    @Published private(set) var brightness: [CGDirectDisplayID: Double] = [:]
    @Published private(set) var autoBrightness: [CGDirectDisplayID: Bool] = [:]

    private var gammaBaselines: [CGDirectDisplayID: GammaFormula] = [:]
    private var brightnessObservers: Set<CGDirectDisplayID> = []
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
        BuiltinBrightness.stopObservingAll()
    }

    func setBrightness(_ value: Double, for display: CGDirectDisplayID) {
        // affichage immédiat : la notification qui suit confirmera la valeur retenue par l'écran
        brightness[display] = value
        BuiltinBrightness.set(value, on: display)
    }

    func setAutoBrightness(_ enabled: Bool, for display: CGDirectDisplayID) {
        autoBrightness[display] = enabled
        AmbientLight.set(enabled, on: display)
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
                hasAutoBrightness: AmbientLight.isSupported(id),
                modes: isOwnVirtual ? [] : DisplayModes.list(for: id),
                currentModeID: DisplayModes.currentID(for: id)
            )
        }

        let online = Set(displays.map(\.id))
        dimFactors = dimFactors.filter { online.contains($0.key) }
        gammaBaselines = gammaBaselines.filter { online.contains($0.key) }
        brightness = brightness.filter { online.contains($0.key) }
        autoBrightness = autoBrightness.filter { online.contains($0.key) }
        // un changement de mode ou un branchement peut remettre la table gamma par défaut
        reapplyDimming()
        refreshBrightness()
        discoverDDC()
    }

    // Les notifications suffisent quand elles répondent ; cette relecture à l'ouverture du menu
    // garde le curseur juste même si l'inscription a échoué.
    func refreshBrightnessValues() {
        refreshBrightness()
    }

    private func refreshBrightness() {
        for display in displays {
            if display.hasHardwareBrightness {
                // la clé doit exister pour que les notifications suivantes soient acceptées
                brightness[display.id] = BuiltinBrightness.get(display.id) ?? brightness[display.id] ?? 0
                observeBrightness(of: display.id)
            }
            if display.hasAutoBrightness {
                autoBrightness[display.id] = AmbientLight.isEnabled(display.id)
            }
        }

        // `observeBrightness` ajoute les écrans suivis ; il ne reste qu'à retirer ceux qui ont disparu
        let observable = Set(displays.filter(\.hasHardwareBrightness).map(\.id))
        for display in brightnessObservers.subtracting(observable) {
            BuiltinBrightness.stopObserving(display)
            brightnessObservers.remove(display)
        }
    }

    private func observeBrightness(of display: CGDirectDisplayID) {
        guard !brightnessObservers.contains(display) else { return }
        let observed = BuiltinBrightness.observe(display, context: Unmanaged.passUnretained(self).toOpaque()) { display, value, context in
            guard let context else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { manager.brightnessChanged(Double(value), on: display) }
        }
        // sans ce garde-fou, un échec marquerait l'écran comme suivi et aucun rafraîchissement n'y reviendrait
        if observed { brightnessObservers.insert(display) }
    }

    fileprivate func brightnessChanged(_ value: Double, on display: CGDirectDisplayID) {
        guard brightness[display] != nil else { return }
        brightness[display] = value
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
