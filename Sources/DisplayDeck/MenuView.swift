import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var displays: DisplayManager
    @ObservedObject var virtualDisplays: VirtualDisplays
    @ObservedObject var mediaKeys: MediaKeys

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displays.displays) { display in
                DisplaySection(display: display, manager: displays)
                Divider()
            }
            VirtualDisplaysSection(model: virtualDisplays)
            Divider()
            KeyboardSection(mediaKeys: mediaKeys)
            Divider()
            Button("Quitter DisplayDeck", action: quit)
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            displays.refreshBrightnessValues()
            // l'autorisation peut avoir été accordée depuis la dernière ouverture
            mediaKeys.refreshAuthorization()
        }
    }

    private func quit() {
        CGDisplayRestoreColorSyncSettings()
        NSApplication.shared.terminate(nil)
    }
}

private struct DisplaySection: View {
    let display: Display
    @ObservedObject var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.name).font(.headline)

            if display.hasHardwareBrightness {
                // la valeur vient du gestionnaire, qui suit aussi les touches du clavier et le capteur
                ControlSlider(title: "Luminosité", value: Binding(
                    get: { manager.brightness[display.id] ?? 0 },
                    set: { manager.setBrightness($0, for: display.id) }
                ))
            }

            if display.hasAutoBrightness {
                Toggle("Luminosité automatique", isOn: Binding(
                    get: { manager.autoBrightness[display.id] ?? false },
                    set: { manager.setAutoBrightness($0, for: display.id) }
                ))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            // un écran qui ne gère pas un code ne rend aucun maximum : le curseur reste masqué
            ForEach(VCP.sliders, id: \.self) { code in
                if let fraction = manager.ddcFraction(code, for: display.id) {
                    ControlSlider(title: code.title, icons: code.icons, value: Binding(
                        get: { fraction },
                        set: { manager.setDDC(code, fraction: $0, for: display.id) }
                    ))
                }
            }

            ControlSlider(title: "Assombrissement logiciel", range: 0.1...1, value: field(\.dim))

            ImageAdjustmentsGroup(display: display, manager: manager)

            if manager.canPowerOff(display.id) {
                HStack(spacing: 10) {
                    Button("Éteindre l'écran") { manager.setPower(.off, for: display.id) }
                    Button("Rallumer") { manager.setPower(.on, for: display.id) }
                }
                .font(.caption)
                .buttonStyle(.link)
                .help("Coupe l'écran lui-même. Le minimum du curseur de luminosité ne fait que baisser le rétroéclairage.")
            }

            if !display.modes.isEmpty {
                Picker("Résolution", selection: modeSelection) {
                    ForEach(display.modes) { Text($0.label).tag(Optional($0.id)) }
                }
            }
        }
    }

    // Chaque curseur écrit un seul champ : le reste des réglages de l'écran est repris tel quel.
    private func field(_ key: WritableKeyPath<ImageAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { manager.adjustment(for: display.id)[keyPath: key] },
            set: { value in
                var adjustments = manager.adjustment(for: display.id)
                adjustments[keyPath: key] = value
                manager.setAdjustments(adjustments, for: display.id)
            }
        )
    }

    private var modeSelection: Binding<DisplayModeOption.ID?> {
        Binding(
            get: { display.currentModeID },
            set: { id in
                guard let option = display.modes.first(where: { $0.id == id }) else { return }
                DisplayModes.apply(option, to: display.id)
            }
        )
    }

}

// Repliés : cinq réglages de plus par écran déborderaient un panneau de barre des menus.
private struct ImageAdjustmentsGroup: View {
    let display: Display
    @ObservedObject var manager: DisplayManager
    @State private var isExpanded = false

    private var adjustments: ImageAdjustments { manager.adjustment(for: display.id) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ControlSlider(title: "Contraste", icons: ("circle.lefthalf.filled", "circle.righthalf.filled"),
                              range: -1...1, value: field(\.contrast))
                ControlSlider(title: "Gamma", icons: ("moon", "sun.max"),
                              range: -1...1, value: field(\.gamma))
                ControlSlider(title: "Température", icons: ("flame", "snowflake"),
                              range: -1...1, value: field(\.temperature))

                Toggle("Inverser les couleurs", isOn: Binding(
                    get: { adjustments.isInverted },
                    set: { value in
                        var next = adjustments
                        next.isInverted = value
                        manager.setAdjustments(next, for: display.id)
                    }
                ))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)

                Button("Réinitialiser") { manager.setAdjustments(.neutral, for: display.id) }
                    .font(.caption)
                    .buttonStyle(.link)
                    .disabled(adjustments.isNeutral)
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("Réglages d'image").font(.caption).foregroundStyle(.secondary)
                if !adjustments.isNeutral {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tint)
                }
            }
        }
    }

    private func field(_ key: WritableKeyPath<ImageAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { adjustments[keyPath: key] },
            set: { value in
                var next = adjustments
                next[keyPath: key] = value
                manager.setAdjustments(next, for: display.id)
            }
        )
    }
}

private struct KeyboardSection: View {
    @ObservedObject var mediaKeys: MediaKeys

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Touches du clavier").font(.headline)

            Toggle("Luminosité de l'écran sous le pointeur", isOn: $mediaKeys.isEnabled)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!mediaKeys.isAuthorized)

            if mediaKeys.isAuthorized {
                Text("Majuscule + Option pour un pas fin.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Intercepter les touches de luminosité demande l'accès à l'accessibilité.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Autoriser…") { mediaKeys.requestAuthorization() }
                    Button("Ouvrir les Réglages") { MediaKeys.openAccessibilitySettings() }
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
    }
}

private struct VirtualDisplaysSection: View {
    @ObservedObject var model: VirtualDisplays
    @State private var creationFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Écrans virtuels").font(.headline)

            ForEach(model.items) { item in
                HStack {
                    Text(item.preset.label)
                    Text("n° \(item.serial)").foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        model.remove(item)
                    } label: {
                        Label("Supprimer", systemImage: "trash").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Supprimer cet écran virtuel")
                }
            }

            Menu("Créer un écran virtuel") {
                ForEach(VirtualDisplayPreset.all) { preset in
                    Button(preset.label) { creationFailed = !model.create(preset) }
                }
            }

            if creationFailed {
                Text("Impossible de créer l'écran virtuel.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct ControlSlider: View {
    let title: String
    var icons = (low: "sun.min", high: "sun.max")
    var range: ClosedRange<Double> = 0...1
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: $value, in: range) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: icons.low)
            } maximumValueLabel: {
                Image(systemName: icons.high)
            }
            .accessibilityLabel(title)
        }
    }
}

private extension VCP {
    var title: String {
        switch self {
        case .brightness: "Luminosité"
        case .contrast: "Contraste"
        case .volume: "Volume"
        case .power: "Alimentation"
        }
    }

    var icons: (low: String, high: String) {
        switch self {
        case .brightness: ("sun.min", "sun.max")
        case .contrast: ("circle.lefthalf.filled", "circle.righthalf.filled")
        case .volume: ("speaker.fill", "speaker.wave.3.fill")
        case .power: ("powersleep", "power")
        }
    }
}
