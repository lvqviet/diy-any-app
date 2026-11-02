import SwiftUI

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatteryControls(compact: true)
            Divider()
            Button("Open DIY Any App…") {
                openWindow(id: MainWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
            .help("Quitting restores normal charging")
        }
        .buttonStyle(.borderless)
        .padding(14)
        .frame(width: 300)
    }
}
