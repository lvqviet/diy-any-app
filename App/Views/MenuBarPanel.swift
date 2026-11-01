import SwiftUI

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatteryControls(compact: true)
            Divider()
            HStack {
                Button("Open DIY Any App…") {
                    openWindow(id: MainWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .help("Quitting restores normal charging")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }
}
