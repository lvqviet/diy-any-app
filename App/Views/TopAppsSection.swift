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
            let maxWatts = model.apps.map(\.watts).max() ?? 0
            ForEach(model.apps) { TopAppRow(app: $0, share: maxWatts > 0 ? $0.watts / maxWatts : 0) }
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
    /// Power relative to the top app, for the bar.
    let share: Double

    var body: some View {
        let force = model.unresponsive.contains(app.id)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appPath ?? "/bin/sh"))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(cpu)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .help(app.appPath ?? app.name)
            Spacer()
            ProgressView(value: share)
                .tint(.orange)
                .frame(width: 120)
                .help("Power use relative to the top app")
                .accessibilityLabel("Power use")
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

    /// Share of the whole machine (all cores), so it stays within 0–100%.
    private var cpu: String {
        let percent = app.cpuPercent / Double(ProcessInfo.processInfo.activeProcessorCount)
        return percent < 1 ? "<1% CPU" : String(format: "%.0f%% CPU", percent)
    }
}
