import AppKit
import DevCore
import SwiftUI

/// Main window page: every listening port with its process and actions.
struct PortsPage: View {
    @Environment(PortsModel.self) private var model
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        let ports = filtered
        Form {
            Section {
                if let error = model.lastError {
                    Notice(icon: "exclamationmark.circle.fill", tint: .red, text: error)
                }
                if ports.isEmpty {
                    Text(search.isEmpty ? "No dev servers are listening." : "No match.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ports) { PortRow(port: $0) }
            } header: {
                Label("Listening ports", systemImage: "network")
            } footer: {
                HStack {
                    Toggle("Show apps and system services", isOn: $model.showAll)
                    Spacer()
                    if !model.showAll && model.hiddenCount > 0 {
                        Text("\(model.hiddenCount) hidden").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Section {
                Text("Ports of processes run by other users (for example with sudo) are not listed. Find them with `sudo lsof -nP -iTCP:<port> -sTCP:LISTEN`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ports")
        .searchable(text: $search, placement: .toolbar, prompt: "Port or process")
        .onWindowVisibilityChange { model.setWindowVisible("main", $0) }
    }

    private var filtered: [ListeningPort] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return model.visiblePorts }
        // A search also looks at hidden ports, so "5000" finds AirPlay.
        return model.ports.filter {
            String($0.port).hasPrefix(query) || $0.processName.lowercased().contains(query)
                || ($0.workingDirectory?.lowercased().contains(query) ?? false)
        }
    }
}

private struct PortRow: View {
    @Environment(PortsModel.self) private var model
    let port: ListeningPort

    var body: some View {
        HStack(spacing: 12) {
            Text(String(port.port))
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(minWidth: 56, alignment: .leading)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 2) {
                Text(port.processName).lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(tooltip)
            Spacer()
            Button { PortActions.openInBrowser(port) } label: { Image(systemName: "safari") }
                .buttonStyle(.borderless)
                .help("Open http://localhost:\(port.port)")
            PortMenu(port: port)
            StopButton(port: port, compact: false)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = ["PID \(port.pid)", port.addresses.joined(separator: ", ")]
        if let cwd = PortActions.projectFolder(port) { parts.append((cwd as NSString).abbreviatingWithTildeInPath) }
        return parts.joined(separator: " · ")
    }

    private var tooltip: String {
        var lines = [port.executablePath ?? port.processName]
        if let start = port.startDate {
            lines.append("Started \(start.formatted(.relative(presentation: .named)))")
        }
        return lines.joined(separator: "\n")
    }
}

/// Compact list for the menu bar panel: dev servers only.
struct PortsPanelSection: View {
    @Environment(PortsModel.self) private var model
    private static let maxRows = 8

    var body: some View {
        let ports = model.ports.filter { !$0.isAppOrSystem }
        VStack(alignment: .leading, spacing: 6) {
            Text("Ports").font(.subheadline.weight(.medium))
            if let error = model.lastError {
                Notice(icon: "exclamationmark.circle.fill", tint: .red, text: error)
            }
            if ports.isEmpty {
                Text("No dev servers listening").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(ports.prefix(Self.maxRows)) { port in
                    HStack(spacing: 8) {
                        Button { PortActions.openInBrowser(port) } label: {
                            Text(":\(String(port.port))").monospacedDigit().frame(minWidth: 48, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .help("Open http://localhost:\(port.port)")
                        Text(panelName(port))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(port.executablePath ?? port.processName)
                        Spacer(minLength: 4)
                        StopButton(port: port, compact: true)
                    }
                }
                if ports.count > Self.maxRows {
                    Text("\(ports.count - Self.maxRows) more in the main window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onWindowVisibilityChange { model.setWindowVisible("panel", $0) }
    }

    private func panelName(_ port: ListeningPort) -> String {
        guard let folder = PortActions.projectFolder(port) else { return port.processName }
        return "\(port.processName) · \((folder as NSString).lastPathComponent)"
    }
}

private struct StopButton: View {
    @Environment(PortsModel.self) private var model
    let port: ListeningPort
    let compact: Bool

    var body: some View {
        let force = model.unresponsive.contains(port.pid)
        let button = Button(role: force ? .destructive : nil) {
            force ? model.forceKill(port) : model.stop(port)
        } label: {
            if compact {
                Image(systemName: force ? "bolt.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(force ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            } else {
                Text(force ? "Force Kill" : "Stop")
            }
        }
        .help(force ? "\(port.processName) did not quit. Send SIGKILL (unsaved work is lost)."
                    : "Quit \(port.processName) (PID \(port.pid)) with SIGTERM")
        if compact {
            button.buttonStyle(.borderless)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

private struct PortMenu: View {
    let port: ListeningPort

    var body: some View {
        Menu {
            Button("Copy PID") { PortActions.copy(String(port.pid)) }
            Button("Copy URL") { PortActions.copy("http://localhost:\(port.port)") }
            if let folder = PortActions.projectFolder(port) {
                Divider()
                Button("Show Folder in Finder") { PortActions.revealInFinder(folder) }
                Button("Open Folder in Terminal") { PortActions.openInTerminal(folder) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

enum PortActions {
    /// The process's working directory, unless it is "/" (apps and daemons) which says nothing.
    static func projectFolder(_ port: ListeningPort) -> String? {
        guard let cwd = port.workingDirectory, cwd != "/" else { return nil }
        return cwd
    }

    static func openInBrowser(_ port: ListeningPort) {
        if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func revealInFinder(_ folder: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
    }

    static func openInTerminal(_ folder: String) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
