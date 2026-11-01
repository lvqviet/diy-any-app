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
                Section("Battery") {
                    LabeledContent("Health", value: "\(r.health)%")
                    LabeledContent("Cycle count", value: "\(r.cycleCount)")
                    LabeledContent("Charger connected", value: r.adapterConnected ? "Yes" : "No")
                    LabeledContent("Current", value: "\(r.amperage) mA")
                }
            }
            Section("General") {
                LaunchAtLoginToggle()
            }
            Section("Helper") {
                LabeledContent("Status", value: helperText)
                if model.helperState != .notInstalled {
                    Button("Uninstall Helper", role: .destructive) { model.uninstallHelper() }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Battery")
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
