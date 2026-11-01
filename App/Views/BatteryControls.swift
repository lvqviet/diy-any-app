import BatteryCore
import SwiftUI

/// Charge Limiter, Discharge, Automatic Discharge and Top Up controls.
/// Shared by the menu bar panel and the main window.
struct BatteryControls: View {
    @Environment(BatteryModel.self) private var model
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HelperBanner()
            if model.competingAppRunning {
                Notice(icon: "exclamationmark.triangle.fill", tint: .orange,
                       text: "AlDente is running. Quit it so the two apps do not fight over charging.")
            }
            if let status = model.status {
                StatusHeader(status: status)
                LimitSlider()
                ActionButtons(status: status)
                if !status.capabilities.chargingControl || !status.capabilities.adapterControl {
                    Notice(icon: "xmark.octagon.fill", tint: .red, text: unsupportedText(status.capabilities))
                }
                if let error = status.lastError {
                    Notice(icon: "exclamationmark.circle.fill", tint: .red, text: error)
                }
            }
            if let error = model.lastError {
                Notice(icon: "exclamationmark.circle.fill", tint: .red, text: error)
            }
        }
    }

    private func unsupportedText(_ caps: ChargeCapabilities) -> String {
        var missing: [String] = []
        if !caps.chargingControl { missing.append("Charge Limiter and Top Up") }
        if !caps.adapterControl { missing.append("Discharge") }
        return "Not supported by this Mac's firmware: \(missing.joined(separator: ", "))."
    }
}

private struct StatusHeader: View {
    let status: HelperStatus

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let r = status.reading {
                Text("\(r.percent)%")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(BatteryStyle.color(status.mode)).frame(width: 8, height: 8)
                    Text(BatteryStyle.title(status.mode)).font(.headline)
                }
                Text(BatteryStyle.detail(status.mode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LimitSlider: View {
    @Environment(BatteryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Charge Limit").font(.subheadline.weight(.medium))
                Spacer()
                Text(model.draftLimit >= 100 ? "Off (100%)" : "\(model.draftLimit)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { Double(model.draftLimit) }, set: { model.draftLimit = Int($0) }),
                in: Double(ChargeSettings.limitRange.lowerBound)...Double(ChargeSettings.limitRange.upperBound),
                step: 5
            ) { editing in
                if !editing { model.commitLimit() }
            }
            .disabled(model.status?.capabilities.chargingControl != true)
        }
    }
}

private struct ActionButtons: View {
    @Environment(BatteryModel.self) private var model
    let status: HelperStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !model.settings.automaticDischarge {
                    let active = status.session.dischargeRequested
                    Button(active ? "Stop Discharge" : "Discharge") { model.toggleDischarge() }
                        .disabled(!active && !model.canStartDischarge)
                        .help("Drain the battery to the limit while plugged in")
                }
                let topUp = status.session.topUpActive
                Button(topUp ? "Cancel Top Up" : "Top Up") { model.toggleTopUp() }
                    .disabled(!topUp && !model.canTopUp)
                    .help("Charge to 100% once; the limit returns after you unplug")
            }
            .controlSize(.regular)

            Toggle("Automatic Discharge", isOn: Binding(
                get: { model.settings.automaticDischarge },
                set: { model.setAutomaticDischarge($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!status.capabilities.adapterControl)
            .help("Discharge automatically whenever the battery is above the limit while plugged in")
        }
    }
}

/// Shows install / approval / connection state of the privileged helper.
struct HelperBanner: View {
    @Environment(BatteryModel.self) private var model

    var body: some View {
        switch model.helperState {
        case .connected:
            EmptyView()
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting to helper…").foregroundStyle(.secondary)
            }
        case .notInstalled:
            VStack(alignment: .leading, spacing: 8) {
                Text("A background helper is needed to control charging.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Install Helper") { model.installHelper() }
                    .buttonStyle(.borderedProminent)
            }
        case .requiresApproval:
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow \"DIY Any App\" in System Settings › General › Login Items & Extensions.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Login Items") { model.openLoginItemsSettings() }
            }
        case .error(let message):
            Notice(icon: "exclamationmark.circle.fill", tint: .red, text: message)
        }
    }
}

struct Notice: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        Label {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
    }
}
