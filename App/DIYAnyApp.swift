import SwiftUI

@main
struct DIYAnyApp: App {
    @State private var battery = BatteryModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(battery)
        } label: {
            MenuBarLabel(battery: battery)
        }
        .menuBarExtraStyle(.window)

        Window("DIY Any App", id: MainWindow.id) {
            MainWindow()
                .environment(battery)
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
