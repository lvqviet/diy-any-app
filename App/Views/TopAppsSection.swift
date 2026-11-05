import AppKit
import BatteryCore
import SwiftUI

/// Battery page section: this user's apps using the most power right now.
struct TopAppsSection: View {
    @Environment(TopAppsModel.self) private var model

    var body: some View {
        Section {
            if let error = model.lastError {
                Notice(icon: "exclamationmark.circle.fill", tint: .red, text: error)
            }
            if model.apps.isEmpty {
                Text(model.measuring ? "Measuring…" : "No app is using noticeable power.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.apps) { TopAppRow(app: $0) }
        } header: {
            Label("Top energy use", systemImage: "flame")
        } footer: {
            Text("Estimated from this user's apps. System processes are not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onWindowVisibilityChange { model.setWindowVisible("main", $0) }
    }
}

private struct TopAppRow: View {
    @Environment(TopAppsModel.self) private var model
    let app: AppUsage

    var body: some View {
        let force = model.unresponsive.contains(app.id)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appPath ?? "/bin/sh"))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(app.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(app.appPath ?? app.name)
            Spacer()
            Text(String(format: "%.0f%% CPU", app.cpuPercent))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(PowerFormat.watts(app.watts))
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)
            Button(force ? "Force Kill" : "Quit", role: force ? .destructive : nil) {
                force ? model.forceKill(app) : model.quit(app)
            }
            .buttonStyle(.bordered)
            .help(force ? "\(app.name) did not quit. Force it to quit (unsaved work is lost)."
                        : "Quit \(app.name)")
        }
        .padding(.vertical, 2)
    }
}
