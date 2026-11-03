import Darwin
import Foundation

/// A TCP port in LISTEN state and the process holding it.
public struct ListeningPort: Hashable, Identifiable, Sendable {
    public let port: UInt16
    /// Local addresses the port is bound to, IPv4 and IPv6 merged. "*" means all interfaces.
    public let addresses: [String]
    public let pid: pid_t
    public let processName: String
    public let executablePath: String?
    public let workingDirectory: String?
    public let startDate: Date?

    public var id: String { "\(pid):\(port)" }

    /// macOS services and regular apps (AirPlay, Spotify, editor helpers), hidden by default
    /// so the list shows dev servers. Bundles that run dev workloads still count as dev.
    public var isAppOrSystem: Bool {
        guard let path = executablePath else { return false }
        if ["/System/", "/usr/libexec/", "/usr/sbin/"].contains(where: path.hasPrefix) { return true }
        guard path.contains(".app/") else { return false }
        return !["/Python.app/", "/Docker.app/", "/OrbStack.app/"].contains(where: path.contains)
    }
}

/// Reads listening sockets straight from the kernel via libproc (a few ms, unlike `lsof`).
public enum PortScanner {
    /// Listening TCP ports of processes this user may inspect, sorted by port. Processes of
    /// other users (including root) are not readable and are left out.
    public static func listeningPorts() -> [ListeningPort] {
        var result: [ListeningPort] = []
        for pid in allPIDs() {
            var addressesByPort: [UInt16: Set<String>] = [:]
            for fd in fileDescriptors(of: pid) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                guard let (port, address) = listeningSocket(pid: pid, fd: fd.proc_fd) else { continue }
                addressesByPort[port, default: []].insert(address)
            }
            guard !addressesByPort.isEmpty else { continue }
            let path = executablePath(of: pid)
            let name = path.map { ($0 as NSString).lastPathComponent } ?? processName(of: pid)
            let cwd = workingDirectory(of: pid)
            let start = startDate(of: pid)
            for (port, addresses) in addressesByPort {
                result.append(ListeningPort(port: port, addresses: addresses.sorted(), pid: pid,
                                            processName: name, executablePath: path,
                                            workingDirectory: cwd, startDate: start))
            }
        }
        return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(max(0, Int(filled))).filter { $0 > 0 }
    }

    private static func fileDescriptors(of pid: pid_t) -> [proc_fdinfo] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        return Array(fds.prefix(max(0, Int(filled)) / stride))
    }

    private static func listeningSocket(pid: pid_t, fd: Int32) -> (UInt16, String)? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
              info.psi.soi_kind == SOCKINFO_TCP,
              info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { return nil }
        var ini = info.psi.soi_proto.pri_tcp.tcpsi_ini
        let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let converted = ini.insi_vflag & UInt8(INI_IPV6) != 0
            ? inet_ntop(AF_INET6, &ini.insi_laddr.ina_6, &buffer, socklen_t(buffer.count))
            : inet_ntop(AF_INET, &ini.insi_laddr.ina_46.i46a_addr4, &buffer, socklen_t(buffer.count))
        guard converted != nil else { return (port, "?") }
        let address = String(cString: buffer)
        return (port, address == "0.0.0.0" || address == "::" ? "*" : address)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processName(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "PID \(pid)" }
        return String(cString: buffer)
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    private static func startDate(of pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }
}
