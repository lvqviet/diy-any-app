import BatteryCore
import SwiftUI

/// Main window: one sidebar entry per feature. New features add a case here.
struct MainWindow: View {
    static let id = "main"

    enum Feature: String, CaseIterable, Identifiable {
        case battery
        var id: String { rawValue }
        var title: String {
            switch self {
            case .battery: return "Battery"
            }
        }
        var symbol: String {
            switch self {
            case .battery: return "battery.75percent"
            }
        }
    }

    @State private var selection: Feature? = .battery

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selection) { feature in
                Label(feature.title, systemImage: feature.symbol).tag(feature)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection {
            case .battery, .none:
                BatteryPage()
            }
        }
    }
}

private struct BatteryPage: View {
    @Environment(BatteryModel.self) private var model

    var body: some View {
        Form {
            Section {
                BatteryControls()
                    .padding(.vertical, 4)
            }
            if let r = model.status?.reading {
                Section {
                    if let apple = model.systemMaximumCapacity {
                        row("Maximum capacity", "heart.fill", .pink, "\(apple)%",
                            help: "As shown in System Settings › Battery › Battery Health")
                    }
                    row("Raw capacity", "heart.text.square", .pink, rawCapacity(r),
                        help: "Full-charge capacity reported by the battery, relative to its design capacity")
                    row("Cycle count", "arrow.triangle.2.circlepath", .purple, "\(r.cycleCount)")
                    row("Current", "waveform.path.ecg", .orange, "\(r.amperage) mA")
                    if let mV = r.power?.batteryVoltage {
                        row("Voltage", "bolt.horizontal", .yellow, PowerFormat.volts(mV))
                    }
                } header: {
                    Label("Battery", systemImage: "battery.75percent")
                }
                Section {
                    let p = r.power
                    let attached = r.chargerAttached ?? r.adapterConnected
                    row("Charger", "powerplug.fill", attached ? .green : .secondary,
                        attached ? (p?.adapterName ?? "Connected") : "Not connected")
                    if attached {
                        if let watts = p?.adapterWatts {
                            row("Adapter power", "bolt.fill", .green, "\(watts) W",
                                help: "Power negotiated between the adapter and the Mac")
                        }
                        if let mV = p?.adapterVoltage, let mA = p?.adapterCurrent {
                            row("Adapter rating", "dial.medium", .teal,
                                "\(PowerFormat.volts(mV)) · \(PowerFormat.amps(mA))")
                        }
                        if let input = p?.inputPower {
                            row("Power in", "arrow.down.to.line", .orange, PowerFormat.watts(input),
                                help: "Power currently drawn from the adapter")
                        }
                    }
                    if let battery = r.batteryPower {
                        row("Battery power", battery >= 0 ? "battery.100percent.bolt" : "battery.50percent",
                            battery > 0.05 ? .yellow : (battery < -0.05 ? .blue : .secondary),
                            PowerFormat.watts(battery, signed: true),
                            help: "Positive while charging, negative while draining")
                    }
                } header: {
                    Label("Power", systemImage: "bolt.circle")
                }
            }
            Section {
                LaunchAtLoginToggle()
                LabeledContent("Version", value: appVersion)
            } header: {
                Label("General", systemImage: "gearshape")
            }
            Section {
                LabeledContent("Status", value: helperText)
                if model.helperState != .notInstalled {
                    Button("Uninstall Helper", role: .destructive) { model.uninstallHelper() }
                }
            } header: {
                Label("Helper", systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Battery")
    }

    private func row(_ title: String, _ symbol: String, _ tint: Color, _ value: String, help: String? = nil) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
        }
        .help(help ?? "")
    }

    private func rawCapacity(_ r: BatteryReading) -> String {
        guard let max = r.maxCapacity, let design = r.designCapacity else { return "\(r.health)%" }
        return "\(r.health)% (\(max) / \(design) mAh)"
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var helperText: String {
        switch model.helperState {
        case .connected: return "Running"
        case .connecting: return "Connecting"
        case .notInstalled: return "Not installed"
        case .requiresApproval: return "Waiting for approval"
        case .error(let m): return m
        }
    }
}
