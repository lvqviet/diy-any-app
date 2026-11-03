import SwiftUI

@main
struct DIYAnyApp: App {
    @State private var battery = BatteryModel()
    @State private var ports = PortsModel()

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
        } label: {
            MenuBarLabel(battery: battery)
        }
        .menuBarExtraStyle(.window)

        Window("DIY Any App", id: MainWindow.id) {
            MainWindow()
                .environment(battery)
                .environment(ports)
                .frame(minWidth: 680, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarLabel: View {
    let battery: BatteryModel

    var body: some View {
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
