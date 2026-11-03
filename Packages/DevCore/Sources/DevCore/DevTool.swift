import CryptoKit
import Foundation

public struct DevToolError: LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// Text conversions for the Dev Utils page. Pure functions of the input, so they are tested
/// here and the view only renders the result.
public enum DevTool: String, CaseIterable, Identifiable, Sendable {
    case json, base64, url, jwt, timestamp, hash, uuid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .json: return "JSON"
        case .base64: return "Base64"
        case .url: return "URL"
        case .jwt: return "JWT"
        case .timestamp: return "Timestamp"
        case .hash: return "Hash"
        case .uuid: return "UUID"
        }
    }

    /// Variants of the tool picked in the UI; `run` takes the index. Empty for single-mode tools.
    public var modes: [String] {
        switch self {
        case .json: return ["Format", "Minify"]
        case .base64, .url: return ["Encode", "Decode"]
        case .jwt, .timestamp, .hash, .uuid: return []
        }
    }

    /// Converts `input`. Empty input gives empty output, except Timestamp (shows now) and
    /// UUID (ignores input and generates one).
    public func run(_ input: String, mode: Int = 0, now: Date = Date()) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .uuid:
            return UUID().uuidString.lowercased()
        case .timestamp:
            return try Self.timestamp(trimmed, now: now)
        default:
            guard !trimmed.isEmpty else { return "" }
        }
        switch self {
        case .json:
            try Self.validateJSON(trimmed)
            return Self.reformatJSON(trimmed, indent: mode == 0 ? "  " : nil)
        case .base64:
            if mode == 0 { return Data(input.utf8).base64EncodedString() }
            return try Self.utf8(Self.base64Decode(trimmed))
        case .url:
            if mode == 0 {
                return input.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved) ?? input
            }
            guard let decoded = input.removingPercentEncoding else { throw DevToolError("Invalid percent encoding") }
            return decoded
        case .jwt:
            return try Self.decodeJWT(trimmed, now: now)
        case .hash:
            let data = Data(input.utf8)
            return [
                "MD5:     " + Self.hex(Insecure.MD5.hash(data: data)),
                "SHA-1:   " + Self.hex(Insecure.SHA1.hash(data: data)),
                "SHA-256: " + Self.hex(SHA256.hash(data: data)),
                "SHA-512: " + Self.hex(SHA512.hash(data: data)),
            ].joined(separator: "\n")
        case .uuid, .timestamp:
            fatalError("handled above")
        }
    }

    // MARK: JSON

    private static func validateJSON(_ text: String) throws {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        } catch let error as NSError {
            throw DevToolError(error.userInfo[NSDebugDescriptionErrorKey] as? String ?? "Invalid JSON")
        }
    }

    /// Re-indents valid JSON text. Works on the text itself, so key order and number
    /// spelling stay exactly as written (JSONSerialization would reorder keys and reformat
    /// numbers). `indent` nil minifies.
    static func reformatJSON(_ text: String, indent: String?) -> String {
        let chars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var level = 0
        var inString = false
        var escaped = false
        func newline() {
            guard let indent else { return }
            out.append("\n")
            for _ in 0..<level { out.append(contentsOf: indent.unicodeScalars) }
        }
        func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\n" || c == "\r" || c == "\t" }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                out.append(c)
                var j = i + 1
                while j < chars.count, isSpace(chars[j]) { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" {
                    out.append(chars[j]) // keep empty containers on one line: {} []
                    i = j
                } else {
                    level += 1
                    newline()
                }
            case "}", "]":
                level -= 1
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                out.append(":")
                if indent != nil { out.append(" ") }
            default:
                if !isSpace(c) { out.append(c) }
            }
            i += 1
        }
        return String(out)
    }

    // MARK: Encodings

    private static let urlUnreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Accepts standard and URL-safe alphabets, with or without padding.
    static func base64Decode(_ text: String) throws -> Data {
        var s = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let data = Data(base64Encoded: s) else { throw DevToolError("Invalid Base64") }
        return data
    }

    private static func utf8(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DevToolError("Decoded \(data.count) bytes of binary data (not UTF-8 text)")
        }
        return text
    }

    private static func hex<D: Digest>(_ digest: D) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: JWT

    private static func decodeJWT(_ token: String, now: Date) throws -> String {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw DevToolError("A JWT has 3 parts separated by dots") }
        func part(_ index: Int, _ name: String) throws -> String {
            guard let text = try? utf8(base64Decode(String(parts[index]))),
                  (try? validateJSON(text)) != nil else { throw DevToolError("Invalid \(name)") }
            return reformatJSON(text, indent: "  ")
        }
        var lines = ["Header:", try part(0, "header"), "", "Payload:", try part(1, "payload")]
        let payload = try? JSONSerialization.jsonObject(with: try base64Decode(String(parts[1]))) as? [String: Any]
        var claims: [String] = []
        for key in ["iat", "nbf", "exp"] {
            guard let seconds = (payload?[key] as? NSNumber)?.doubleValue else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            var line = "\(key): \(date.formatted(.iso8601))"
            if key == "exp" { line += date < now ? " (expired)" : " (valid)" }
            claims.append(line)
        }
        if !claims.isEmpty { lines += [""] + claims }
        lines += ["", "Signature is not verified."]
        return lines.joined(separator: "\n")
    }

    // MARK: Timestamp

    /// Unix seconds or milliseconds become dates; an ISO 8601 or "yyyy-MM-dd HH:mm:ss" (local
    /// time) date becomes a Unix timestamp. Empty input shows now.
    static func timestamp(_ text: String, now: Date) throws -> String {
        let date: Date
        if text.isEmpty {
            date = now
        } else if let number = Double(text) {
            // Values this large are milliseconds (seconds would be past the year 5000).
            date = Date(timeIntervalSince1970: abs(number) >= 1e11 ? number / 1000 : number)
        } else if let parsed = parseDate(text) {
            date = parsed
        } else {
            throw DevToolError("Enter Unix seconds or milliseconds, or an ISO 8601 date")
        }
        let seconds = date.timeIntervalSince1970
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return [
            "Seconds:      \(Int64(seconds.rounded(.down)))",
            "Milliseconds: \(Int64((seconds * 1000).rounded()))",
            "UTC:          \(date.formatted(.iso8601))",
            "Local:        \(local.string(from: date))",
            "Relative:     \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now))",
        ].joined(separator: "\n")
    }

    private static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }
}
