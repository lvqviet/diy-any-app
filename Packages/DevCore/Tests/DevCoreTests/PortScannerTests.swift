import Darwin
import XCTest
@testable import DevCore

final class PortScannerTests: XCTestCase {
    func testFindsOwnListeningSocket() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                XCTAssertEqual(Darwin.bind(fd, $0, length), 0) // port 0: the kernel picks a free one
                XCTAssertEqual(listen(fd, 1), 0)
                XCTAssertEqual(getsockname(fd, $0, &length), 0)
            }
        }
        let port = UInt16(bigEndian: addr.sin_port)

        let found = PortScanner.listeningPorts().first { $0.pid == getpid() && $0.port == port }
        XCTAssertEqual(found?.addresses, ["127.0.0.1"])
        XCTAssertNotNil(found?.startDate)
        XCTAssertNotNil(found?.workingDirectory)
    }

    func testAppOrSystemPaths() {
        func port(_ path: String) -> ListeningPort {
            ListeningPort(port: 1, addresses: [], pid: 1, processName: "", executablePath: path,
                          workingDirectory: nil, startDate: nil)
        }
        XCTAssertTrue(port("/usr/libexec/rapportd").isAppOrSystem)
        XCTAssertTrue(port("/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter").isAppOrSystem)
        XCTAssertTrue(port("/Applications/Spotify.app/Contents/MacOS/Spotify").isAppOrSystem)
        XCTAssertTrue(port(NSHomeDirectory() + "/Library/Application Support/Logi/x.app/Contents/MacOS/x").isAppOrSystem)
        // Python runs from a Python.app bundle; it must still count as a dev process.
        XCTAssertFalse(port("/opt/homebrew/Cellar/python@3.13/3.13.1/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python").isAppOrSystem)
        XCTAssertFalse(port("/opt/homebrew/bin/node").isAppOrSystem)
    }
}
