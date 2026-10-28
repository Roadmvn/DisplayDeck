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
    @Published private(set) var adjustments: [CGDirectDisplayID: ImageAdjustments] = [:]
    @Published private(set) var brightness: [CGDirectDisplayID: Double] = [:]
    // Détenues ici et non dans la vue : le clavier règle les mêmes valeurs que les curseurs.
    @Published private(set) var ddcValues: [CGDirectDisplayID: [VCP: VCPValue]] = [:]
    @Published private(set) var autoBrightness: [CGDirectDisplayID: Bool] = [:]

    // Capturée avant la première retouche : elle porte l'étalonnage et sert de point de départ.
    private var colorBaselines: [CGDirectDisplayID: ColorTable] = [:]
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

    func hasDDC(_ code: VCP, for display: CGDirectDisplayID) -> Bool {
        ddcFraction(code, for: display) != nil
    }

    func ddcFraction(_ code: VCP, for display: CGDirectDisplayID) -> Double? {
        guard let value = ddcValues[display]?[code], value.maximum > 0 else { return nil }
        return Double(value.current) / Double(value.maximum)
    }

    func setDDC(_ code: VCP, fraction: Double, for display: CGDirectDisplayID) {
        guard let device = ddcDevices[display],
              let value = ddcValues[display]?[code], value.maximum > 0
        else { return }
        let raw = UInt16((min(max(fraction, 0), 1) * Double(value.maximum)).rounded())
        ddcValues[display]?[code] = VCPValue(current: raw, maximum: value.maximum)
        device.write(code, value: raw, of: value.maximum)
    }

    // L'écran répond encore au DDC une fois éteint, donc il peut être rallumé d'ici.
    func canPowerOff(_ display: CGDirectDisplayID) -> Bool {
        (ddcValues[display]?[.power]?.maximum ?? 0) > 0
    }

    func setPower(_ power: DisplayPower, for display: CGDirectDisplayID) {
        guard let device = ddcDevices[display], canPowerOff(display) else { return }
        device.write(.power, value: power.rawValue, of: 0)
    }

    func stepDDC(_ code: VCP, by delta: Double, for display: CGDirectDisplayID) {
        guard let fraction = ddcFraction(code, for: display) else { return }
        setDDC(code, fraction: fraction + delta, for: display)
    }

    func adjustment(for display: CGDirectDisplayID) -> ImageAdjustments {
        adjustments[display] ?? .neutral
    }

    func setAdjustments(_ value: ImageAdjustments, for display: CGDirectDisplayID) {
        guard !value.isNeutral else {
            adjustments[display] = nil
            colorBaselines[display] = nil
            // la restauration ColorSync vaut pour tous les écrans, d'où la réapplication des autres
            CGDisplayRestoreColorSyncSettings()
            reapplyAdjustments()
            return
        }
        if colorBaselines[display] == nil {
            colorBaselines[display] = ColorTable.current(of: display)
        }
        adjustments[display] = value
        colorBaselines[display]?.applying(value).apply(to: display)
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
        adjustments = adjustments.filter { online.contains($0.key) }
        colorBaselines = colorBaselines.filter { online.contains($0.key) }
        brightness = brightness.filter { online.contains($0.key) }
        autoBrightness = autoBrightness.filter { online.contains($0.key) }
        // un changement de mode ou un branchement peut remettre la table de couleur par défaut
        reapplyAdjustments()
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

    private func reapplyAdjustments() {
        for (display, value) in adjustments {
            colorBaselines[display]?.applying(value).apply(to: display)
        }
    }

    private func discoverDDC() {
        let externals = displays.map(\.id).filter {
            CGDisplayIsBuiltin($0) == 0 && CGDisplayVendorNumber($0) != VirtualDisplays.vendorID
        }
        // file série : les découvertes se terminent dans l'ordre, la dernière configuration l'emporte toujours
        ddcDiscoveryQueue.async {
            let devices = DDCDevice.discover(for: externals)
            DispatchQueue.main.async {
                self.ddcDevices = devices
                self.readDDCValues()
            }
        }
    }

    private func readDDCValues() {
        ddcValues = ddcValues.filter { ddcDevices[$0.key] != nil }
        for (display, device) in ddcDevices {
            Task { @MainActor in
                var values: [VCP: VCPValue] = [:]
                for code in VCP.allCases {
                    values[code] = await device.read(code)
                }
                // chaque lecture coûte un aller-retour I2C : la configuration a pu changer entretemps
                guard self.ddcDevices[display] === device else { return }
                self.ddcValues[display] = values
            }
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
