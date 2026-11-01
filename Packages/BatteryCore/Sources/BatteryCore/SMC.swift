import Foundation
import IOKit

/// Errors raised while talking to the System Management Controller.
public enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(key: String, kern_return_t)
    case smcResult(key: String, UInt8)
    case keyNotFound(String)
    case sizeMismatch(key: String, expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found"
        case .openFailed(let r): return "IOServiceOpen failed: \(String(format: "0x%08x", r))"
        case .callFailed(let k, let r): return "SMC call for \(k) failed: \(String(format: "0x%08x", r))"
        case .smcResult(let k, let c): return "SMC returned error \(c) for \(k)"
        case .keyNotFound(let k): return "SMC key \(k) not found"
        case .sizeMismatch(let k, let e, let a): return "SMC key \(k) expects \(e) bytes, got \(a)"
        }
    }
}

/// Metadata of an SMC key.
public struct SMCKeyInfo: Equatable, Sendable {
    public let size: Int
    public let type: String
}

/// Minimal IOKit client for the AppleSMC user client.
/// Reads work for any user; writes require root.
public final class SMC {
    // Layout must match the kernel's SMCParamStruct (80 bytes).
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 { case read = 5, write = 6, keyInfo = 9 }
    private static let kernelIndex: UInt32 = 2
    private static let resultKeyNotFound: UInt8 = 0x84

    private var connection: io_connect_t = 0
    private var infoCache: [String: SMCKeyInfo] = [:]
    private let lock = NSLock()

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let r = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard r == kIOReturnSuccess else { throw SMCError.openFailed(r) }
        assert(MemoryLayout<Param>.stride == 80, "SMCParamStruct layout mismatch")
    }

    deinit { IOServiceClose(connection) }

    /// Returns key metadata, or nil if the key does not exist on this machine.
    public func info(_ key: String) throws -> SMCKeyInfo? {
        lock.lock(); defer { lock.unlock() }
        return try infoLocked(key)
    }

    public func read(_ key: String) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        guard let info = try infoLocked(key) else { throw SMCError.keyNotFound(key) }
        var input = Param()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.command = Command.read.rawValue
        let output = try call(key, &input)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(info.size)) }
    }

    public func write(_ key: String, _ value: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        guard let info = try infoLocked(key) else { throw SMCError.keyNotFound(key) }
        guard info.size == value.count else {
            throw SMCError.sizeMismatch(key: key, expected: info.size, actual: value.count)
        }
        var input = Param()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.command = Command.write.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buf in
            for (i, b) in value.enumerated() { buf[i] = b }
        }
        _ = try call(key, &input)
    }

    private func infoLocked(_ key: String) throws -> SMCKeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = Param()
        input.key = Self.fourCC(key)
        input.command = Command.keyInfo.rawValue
        let output: Param
        do {
            output = try call(key, &input)
        } catch SMCError.smcResult(_, Self.resultKeyNotFound) {
            return nil
        } catch SMCError.callFailed(_, kIOReturnNotPrivileged) {
            // Newer firmware gates charge-control keys behind a private entitlement.
            return nil
        }
        // Firmware may keep a gated key as a zero-size placeholder; treat it as absent.
        guard output.keyInfo.dataSize > 0 else { return nil }
        let info = SMCKeyInfo(size: Int(output.keyInfo.dataSize), type: Self.string(output.keyInfo.dataType))
        infoCache[key] = info
        return info
    }

    private func call(_ key: String, _ input: inout Param) throws -> Param {
        var output = Param()
        var outSize = MemoryLayout<Param>.stride
        let r = IOConnectCallStructMethod(connection, Self.kernelIndex, &input, MemoryLayout<Param>.stride, &output, &outSize)
        guard r == kIOReturnSuccess else { throw SMCError.callFailed(key: key, r) }
        guard output.result == 0 else { throw SMCError.smcResult(key: key, output.result) }
        return output
    }

    static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func string(_ v: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((v >> UInt32($0)) & 0xff) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
