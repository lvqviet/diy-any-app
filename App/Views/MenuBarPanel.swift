import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var panelWindow: NSWindow?
    @Environment(BatteryModel.self) private var battery

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatteryControls(compact: true)
            Divider()
            Button("Open DIY Any App…") { openMainWindow() }
                .buttonStyle(.borderless)
            Divider()
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
            .help("Quitting restores normal charging")
        }
        .padding(14)
        .frame(width: 300)
        .background(WindowReader(window: $panelWindow))
        .onWindowVisibilityChange { battery.setWindowVisible("panel", $0) }
    }

    private func openMainWindow() {
        // Close the panel first; it does not always close by itself when another window
        // of this (menu bar only) app becomes key.
        dismiss()
        panelWindow?.orderOut(nil)
        openWindow(id: MainWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Exposes the NSWindow hosting a SwiftUI view.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window !== nsView.window {
            DispatchQueue.main.async { window = nsView.window }
        }
    }
}
