import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var displays: DisplayManager
    @ObservedObject var virtualDisplays: VirtualDisplays

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displays.displays) { display in
                DisplaySection(display: display, manager: displays)
                Divider()
            }
            VirtualDisplaysSection(model: virtualDisplays)
            Divider()
            Button("Quitter DisplayDeck", action: quit)
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
    }

    private func quit() {
        CGDisplayRestoreColorSyncSettings()
        NSApplication.shared.terminate(nil)
    }
}

private struct DisplaySection: View {
    let display: Display
    @ObservedObject var manager: DisplayManager
    @State private var ddcValues: [VCP: VCPValue] = [:]

    private static let ddcControls: [VCP] = [.brightness, .contrast, .volume]

    private var ddc: DDCDevice? { manager.ddcDevices[display.id] }

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

            if let ddc {
                ForEach(Self.ddcControls, id: \.self) { code in
                    // un écran qui ne gère pas un code ne rend aucun maximum : le curseur reste masqué
                    if let value = ddcValues[code], value.maximum > 0 {
                        ControlSlider(title: code.title, icons: code.icons, value: ddcBinding(code, value, ddc))
                    }
                }
            }

            ControlSlider(title: "Assombrissement logiciel", range: 0.1...1, value: Binding(
                get: { manager.dimFactors[display.id] ?? 1 },
                set: { manager.setDimFactor($0, for: display.id) }
            ))

            if !display.modes.isEmpty {
                Picker("Résolution", selection: modeSelection) {
                    ForEach(display.modes) { Text($0.label).tag(Optional($0.id)) }
                }
            }
        }
        .task(id: ddc.map(ObjectIdentifier.init)) {
            ddcValues = [:]
            guard let ddc else { return }
            for code in Self.ddcControls {
                ddcValues[code] = await ddc.read(code)
            }
        }
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

    private func ddcBinding(_ code: VCP, _ value: VCPValue, _ device: DDCDevice) -> Binding<Double> {
        Binding(
            get: { Double(value.current) / Double(value.maximum) },
            set: { fraction in
                let raw = UInt16((fraction * Double(value.maximum)).rounded())
                ddcValues[code] = VCPValue(current: raw, maximum: value.maximum)
                device.write(code, value: raw, of: value.maximum)
            }
        )
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
        }
    }

    var icons: (low: String, high: String) {
        switch self {
        case .brightness: ("sun.min", "sun.max")
        case .contrast: ("circle.lefthalf.filled", "circle.righthalf.filled")
        case .volume: ("speaker.fill", "speaker.wave.3.fill")
        }
    }
}
