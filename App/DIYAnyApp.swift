import SwiftUI

@main
struct DIYAnyApp: App {
    @State private var battery = BatteryModel()
    @State private var ports = PortsModel()
    @State private var keepAwake = KeepAwakeModel()

    init() {
        // Dev Utils input is code: no smart quotes, dashes or autocorrect.
        UserDefaults.standard.register(defaults: [
            "NSAutomaticQuoteSubstitutionEnabled": false,
            "NSAutomaticDashSubstitutionEnabled": false,
            "NSAutomaticSpellingCorrectionEnabled": false,
        ])
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(battery)
                .environment(ports)
                .environment(keepAwake)
        } label: {
            MenuBarLabel(battery: battery, keepAwake: keepAwake)
        }
        .menuBarExtraStyle(.window)

        Window("DIY Any App", id: MainWindow.id) {
            MainWindow()
                .environment(battery)
                .environment(ports)
                .environment(keepAwake)
                .frame(minWidth: 680, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarLabel: View {
    let battery: BatteryModel
    let keepAwake: KeepAwakeModel

    var body: some View {
        HStack(spacing: 3) {
            if keepAwake.isActive {
                Image(systemName: "cup.and.saucer.fill")
            }
            batteryLabel
        }
    }

    @ViewBuilder private var batteryLabel: some View {
        if let status = battery.status, let percent = status.reading?.percent {
            HStack(spacing: 3) {
                Image(systemName: BatteryStyle.symbol(for: status))
                Text("\(percent)%")
            }
        } else {
            Image(systemName: "battery.100")
        }
    }
}
