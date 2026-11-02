import BatteryCore
import SwiftUI

/// Charge Limit, Automatic Discharge and Sailing Mode as form rows for the main window.
/// The menu bar panel keeps its own slider for the limit.
struct BatterySettingsRows: View {
    @Environment(BatteryModel.self) private var model

    var body: some View {
        let caps = model.status?.capabilities
        Group {
            LabeledContent {
                LimitField()
            } label: {
                SettingLabel("Charge Limit", systemImage: "battery.75percent",
                             info: "Charging stops at this level while the adapter is plugged in. "
                                 + "Set \(ChargeSettings.limitRange.upperBound)% to charge normally.")
            }
            .disabled(caps?.chargingControl != true)

            Toggle(isOn: binding(model.settings.automaticDischarge, model.setAutomaticDischarge)) {
                SettingLabel("Automatic Discharge", systemImage: "bolt.slash",
                             info: "Discharge automatically whenever the battery is above the limit "
                                 + "while plugged in.")
            }
            .disabled(caps?.adapterControl != true)

            Toggle(isOn: binding(model.settings.sailingMode, model.setSailingMode)) {
                SettingLabel("Sailing Mode", systemImage: "sailboat",
                             info: "Below the limit, only charge again once the battery drops "
                                 + "\(ChargeSettings.sailingGap)% under it, so it is not topped up "
                                 + "in small bursts.")
            }
            .disabled(caps?.chargingControl != true || model.settings.limit >= 100)
        }
        .toggleStyle(.switch)
    }

    private func binding(_ value: Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: set)
    }
}

/// Icon, title and an info button that explains the setting.
private struct SettingLabel: View {
    let title: String
    let systemImage: String
    let info: String
    @State private var showsInfo = false

    init(_ title: String, systemImage: String, info: String) {
        self.title = title
        self.systemImage = systemImage
        self.info = info
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
            Button { showsInfo.toggle() } label: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(info)
            .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
                Text(info)
                    .font(.callout)
                    .frame(width: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
        }
    }
}

/// Numeric input for the charge limit. Commits on Return or when the field loses focus,
/// clamped to the allowed range.
private struct LimitField: View {
    @Environment(BatteryModel.self) private var model
    @State private var text = ""
    @FocusState private var focused: Bool

    private var range: ClosedRange<Int> { ChargeSettings.limitRange }

    var body: some View {
        HStack(spacing: 4) {
            TextField("Charge Limit", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 52)
                .focused($focused)
                .onSubmit(commit)
            Text("%").foregroundStyle(.secondary)
        }
        .onAppear { text = "\(model.draftLimit)" }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        // Follow changes made elsewhere (the panel slider) while not editing.
        .onChange(of: model.draftLimit) { _, limit in
            if !focused { text = "\(limit)" }
        }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        if let value = Int(digits) {
            model.draftLimit = min(max(value, range.lowerBound), range.upperBound)
            model.commitLimit()
        }
        text = "\(model.draftLimit)"
    }
}
