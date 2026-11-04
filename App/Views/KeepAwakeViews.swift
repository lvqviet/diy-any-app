import DevCore
import SwiftUI

/// Duration buttons, status and Stop. Shared by the menu bar panel and the main window.
struct KeepAwakeControls: View {
    @Environment(KeepAwakeModel.self) private var model
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 6) {
                Image(systemName: model.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(model.isActive ? Color.orange : .secondary)
                    .frame(width: 18)
                Text("Keep Awake").font(compact ? .subheadline.weight(.medium) : .headline)
                Spacer()
                if model.isActive {
                    Button("Stop") { model.stop() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if model.isActive {
                StatusText(endDate: model.endDate)
            }
            HStack(spacing: 4) {
                ForEach(KeepAwakeModel.durations, id: \.title) { duration in
                    Button { model.start(minutes: duration.minutes) } label: {
                        Text(duration.title).frame(maxWidth: .infinity)
                    }
                    .help(duration.minutes == nil ? "Until you stop it" : "Keep the Mac awake for \(duration.title)")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(compact ? .small : .regular)
            .disabled(model.blockReason != nil)
            if let reason = model.blockReason {
                Notice(icon: "exclamationmark.triangle.fill", tint: .orange,
                       text: "\(reason). Keep Awake is unavailable to protect the Mac.")
            } else if let message = model.autoStopMessage {
                Notice(icon: "info.circle.fill", tint: .secondary, text: message)
            }
        }
    }
}

/// "Awake until 15:30 · 42 min left". Updates once a minute, only while its window is visible.
private struct StatusText: View {
    let endDate: Date?
    @State private var visible = false

    var body: some View {
        Group {
            if let endDate {
                if visible {
                    TimelineView(.everyMinute) { context in text(endDate, now: context.date) }
                } else {
                    text(endDate, now: Date())
                }
            } else {
                Text("Awake until you stop it")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .onWindowVisibilityChange { visible = $0 }
    }

    private func text(_ end: Date, now: Date) -> Text {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        let left = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        return Text("Awake until \(end.formatted(date: .omitted, time: .shortened)) · \(left) left")
    }
}

struct KeepAwakePage: View {
    var body: some View {
        Form {
            Section {
                KeepAwakeControls()
                    .padding(.vertical, 4)
            }
            Section {
                Text("Keeps the display on and the Mac from sleeping while idle, like `caffeinate -d`.")
                Text("Stops by itself on battery at \(KeepAwakePolicy.lowBatteryPercent)% or when the Mac gets critically hot. Quitting the app also stops it.")
                Text("Closing the lid or choosing Sleep from the Apple menu still puts the Mac to sleep.")
            } header: {
                Label("About", systemImage: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Keep Awake")
    }
}
