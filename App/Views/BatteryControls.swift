import BatteryCore
import SwiftUI

/// Battery status with the Discharge and Top Up actions, shared by the menu bar panel and the
/// main window. The compact panel also shows the charge limit slider; the main window shows the
/// limit and the other settings as form rows instead (`BatterySettingsRows`).
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
                StatusHeader(status: status, ringSize: compact ? 64 : 84)
                if let reading = status.reading {
                    PowerSummary(reading: reading)
                }
                if compact {
                    LimitSlider()
                }
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
        if !caps.chargingControl { missing.append("Charge Limiter, Sailing Mode and Top Up") }
        if !caps.adapterControl { missing.append("Discharge") }
        return "Not supported by this Mac's firmware: \(missing.joined(separator: ", "))."
    }
}

private struct StatusHeader: View {
    let status: HelperStatus
    let ringSize: CGFloat
    /// The repeating pulse renders every frame, so it only runs while the window is visible.
    @State private var visible = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let r = status.reading {
                BatteryRing(percent: r.percent, settings: status.settings, mode: status.mode,
                            color: BatteryStyle.color(status))
                    .frame(width: ringSize, height: ringSize)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: BatteryStyle.icon(status))
                        .foregroundStyle(BatteryStyle.color(status))
                        .symbolEffect(.pulse, options: .repeating,
                                      isActive: visible && BatteryStyle.isActive(status.mode))
                        .frame(width: 18)
                    Text(BatteryStyle.title(status.mode)).font(.headline)
                }
                Text(BatteryStyle.detail(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onWindowVisibilityChange { visible = $0 }
    }
}

/// One-line power summary: negotiated adapter power, power drawn, battery power.
private struct PowerSummary: View {
    let reading: BatteryReading

    var body: some View {
        let power = reading.power
        let attached = (reading.chargerAttached ?? reading.adapterConnected) && power?.adapterWatts != nil
        HStack(spacing: 5) {
            if attached, let watts = power?.adapterWatts {
                Text("\(watts) W adapter").help(power?.adapterName ?? "Adapter")
                if let input = power?.inputPower {
                    Text("·")
                    Text("In \(PowerFormat.watts(input))").help("Power drawn from the adapter")
                }
            }
            if let battery = reading.batteryPower {
                if attached { Text("·") }
                Text("Battery \(PowerFormat.watts(battery, signed: true))")
                    .foregroundStyle(battery > 0.05 ? .orange : (battery < -0.05 ? .blue : .secondary))
                    .help("Positive while charging, negative while draining")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

private struct LimitSlider: View {
    @Environment(BatteryModel.self) private var model

    private var range: ClosedRange<Int> { ChargeSettings.limitRange }

    var body: some View {
        let enabled = model.status?.capabilities.chargingControl == true
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Charge Limit").font(.subheadline.weight(.medium))
                Spacer()
                Text(model.draftLimit >= 100 ? "Off (100%)" : "\(model.draftLimit)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper("Charge Limit", value: Binding(
                    get: { model.draftLimit },
                    set: { model.draftLimit = $0; model.commitLimit() }
                ), in: range)
                .labelsHidden()
                .controlSize(.small)
            }
            // No step: the thumb moves freely and snaps to whole percents.
            Slider(
                value: Binding(get: { Double(model.draftLimit) }, set: { model.draftLimit = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound)
            ) { editing in
                if !editing { model.commitLimit() }
            }
        }
        .disabled(!enabled)
    }
}

private struct ActionButtons: View {
    @Environment(BatteryModel.self) private var model
    let status: HelperStatus

    var body: some View {
        HStack(spacing: 12) {
            if !model.settings.automaticDischarge {
                let active = status.session.dischargeRequested
                Button { model.toggleDischarge() } label: {
                    Text(active ? "Stop Discharge" : "Discharge").frame(maxWidth: .infinity)
                }
                .disabled(!active && !model.canStartDischarge)
                .help("Drain the battery to the limit while plugged in")
            }
            let topUp = status.session.topUpActive
            Button { model.toggleTopUp() } label: {
                Text(topUp ? "Cancel Top Up" : "Top Up").frame(maxWidth: .infinity)
            }
            .disabled(!topUp && !model.canTopUp)
            .help("Charge to 100% once; the limit returns after you unplug")
        }
        // Explicit, so the borderless style of the panel's menu rows does not apply here.
        .buttonStyle(.bordered)
        .controlSize(.large)
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
