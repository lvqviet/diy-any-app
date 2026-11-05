import Darwin
import Foundation

/// Cumulative energy and CPU counters of one process at one moment.
public struct ProcessSample: Equatable, Sendable {
    public let pid: pid_t
    public let name: String
    /// Outermost `.app` bundle the executable lives in, so helpers count toward their app.
    public let appPath: String?
    public let energyNJ: UInt64
    public let cpuNanos: UInt64
    /// `ri_proc_start_abstime`; tells a reused PID apart from the sampled process.
    public let startTime: UInt64

    public init(pid: pid_t, name: String, appPath: String?, energyNJ: UInt64, cpuNanos: UInt64, startTime: UInt64) {
        self.pid = pid
        self.name = name
        self.appPath = appPath
        self.energyNJ = energyNJ
        self.cpuNanos = cpuNanos
        self.startTime = startTime
    }

    /// App bundle path, or process name for command line tools.
    public var groupKey: String { appPath ?? name }
}

/// Power and CPU use of one app (all its processes) between two samples.
public struct AppUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let appPath: String?
    /// PID to start time, to re-check each process before signalling it.
    public let processes: [pid_t: UInt64]
    public let watts: Double
    public let cpuPercent: Double
}

/// Per-app energy use from the kernel's per-process counters (`proc_pid_rusage`).
/// Only processes of this user are readable; others are left out.
public enum AppEnergy {
    public static func sample() -> [pid_t: ProcessSample] {
        var result: [pid_t: ProcessSample] = [:]
        for pid in allPIDs() {
            if let s = sample(pid: pid) { result[pid] = s }
        }
        return result
    }

    public static func sample(pid: pid_t) -> ProcessSample? {
        var info = rusage_info_v6()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard status == 0 else { return nil }
        let path = executablePath(of: pid)
        let app = path.flatMap(outermostApp)
        let name = app.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
            ?? path.map { ($0 as NSString).lastPathComponent } ?? "PID \(pid)"
        // CPU times are mach ticks (not ns) on Apple Silicon.
        let cpu = (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
        return ProcessSample(pid: pid, name: name, appPath: app, energyNJ: info.ri_energy_nj,
                             cpuNanos: cpu, startTime: info.ri_proc_start_abstime)
    }

    /// Apps ranked by power over `interval` seconds, then by CPU. Processes not in both samples
    /// (new, exited or PID reused) are skipped. Near-idle apps are dropped.
    public static func top(previous: [pid_t: ProcessSample], current: [pid_t: ProcessSample],
                           interval: Double, excluding: String? = nil, limit: Int = 5) -> [AppUsage] {
        guard interval > 0 else { return [] }
        struct Total { var name: String; var appPath: String?; var processes: [pid_t: UInt64] = [:]; var nj: UInt64 = 0; var ns: UInt64 = 0 }
        var totals: [String: Total] = [:]
        for (pid, now) in current {
            guard let before = previous[pid], before.startTime == now.startTime,
                  now.energyNJ >= before.energyNJ, now.cpuNanos >= before.cpuNanos,
                  now.groupKey != excluding else { continue }
            var total = totals[now.groupKey] ?? Total(name: now.name, appPath: now.appPath)
            total.processes[pid] = now.startTime
            total.nj += now.energyNJ - before.energyNJ
            total.ns += now.cpuNanos - before.cpuNanos
            totals[now.groupKey] = total
        }
        return totals.map { key, t in
            AppUsage(id: key, name: t.name, appPath: t.appPath, processes: t.processes,
                     watts: Double(t.nj) / 1e9 / interval, cpuPercent: Double(t.ns) / 1e9 / interval * 100)
        }
        .filter { $0.watts >= 0.05 || $0.cpuPercent >= 1 }
        .sorted(by: ranksHigher)
        .prefix(limit)
        .map { $0 }
    }

    /// Watts at the 0.1 W the UI shows; below that the energy counter is noise, so CPU decides.
    private static func ranksHigher(_ a: AppUsage, _ b: AppUsage) -> Bool {
        let wa = (a.watts * 10).rounded(), wb = (b.watts * 10).rounded()
        return wa != wb ? wa > wb : a.cpuPercent > b.cpuPercent
    }

    /// `/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…` → `/Applications/Google Chrome.app`.
    static func outermostApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(max(0, Int(filled))).filter { $0 > 0 }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
