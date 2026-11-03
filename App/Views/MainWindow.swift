import BatteryCore
import SwiftUI

/// Main window: one sidebar entry per feature. New features add a case here.
struct MainWindow: View {
    static let id = "main"

    enum Feature: String, CaseIterable, Identifiable {
        case battery, ports, devUtils
        var id: String { rawValue }
        var title: String {
            switch self {
            case .battery: return "Battery"
            case .ports: return "Ports"
            case .devUtils: return "Dev Utils"
            }
        }
        var symbol: String {
            switch self {
            case .battery: return "battery.75percent"
            case .ports: return "network"
            case .devUtils: return "wrench.and.screwdriver"
            }
        }
    }

    @State private var selection: Feature? = .battery
    @Environment(BatteryModel.self) private var battery

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selection) { feature in
                Label(feature.title, systemImage: feature.symbol).tag(feature)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch selection {
                case .battery, .none:
                    BatteryPage()
                case .ports:
                    PortsPage()
                case .devUtils:
                    DevUtilsPage()
                }
            }
            // Opaque detail pane, so the translucent sidebar reads as lighter than the content.
            .background(Color(nsColor: .windowBackgroundColor))
            .onWindowVisibilityChange { battery.setWindowVisible("main", $0) }
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
                if model.status != nil {
                    BatterySettingsRows()
                }
            }
            if let r = model.status?.reading {
                Section {
                    if let apple = model.systemMaximumCapacity {
                        row("Maximum capacity", "\(apple)%",
                            help: "As shown in System Settings › Battery › Battery Health")
                    }
                    row("Raw capacity", rawCapacity(r),
                        help: "Full-charge capacity reported by the battery, relative to its design capacity")
                    row("Cycle count", "\(r.cycleCount)")
                    row("Current", "\(r.amperage) mA")
                    if let mV = r.power?.batteryVoltage {
                        row("Voltage", PowerFormat.volts(mV))
                    }
                } header: {
                    Label("Battery", systemImage: "battery.75percent")
                }
                Section {
                    let p = r.power
                    let attached = r.chargerAttached ?? r.adapterConnected
                    row("Charger", attached ? (p?.adapterName ?? "Connected") : "Not connected")
                    if attached {
                        if let watts = p?.adapterWatts {
                            row("Adapter power", "\(watts) W",
                                help: "Power negotiated between the adapter and the Mac")
                        }
                        if let mV = p?.adapterVoltage, let mA = p?.adapterCurrent {
                            row("Adapter rating", "\(PowerFormat.volts(mV)) · \(PowerFormat.amps(mA))")
                        }
                        if let input = p?.inputPower {
                            row("Power in", PowerFormat.watts(input),
                                help: "Power currently drawn from the adapter")
                        }
                    }
                    if let battery = r.batteryPower {
                        row("Battery power", PowerFormat.watts(battery, signed: true),
                            tint: battery > 0.05 ? .orange : (battery < -0.05 ? .blue : nil),
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

    private func row(_ title: String, _ value: String, tint: Color? = nil, help: String? = nil) -> some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
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
