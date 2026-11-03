import XCTest
@testable import DevCore

final class DevToolTests: XCTestCase {
    func testJSONFormatKeepsKeyOrderAndNumbers() throws {
        let input = #"{"b":1.0,"a":[1, {"s":"x, \"y\": [z]"}],"e":{},"f":[ ]}"#
        XCTAssertEqual(try DevTool.json.run(input), """
        {
          "b": 1.0,
          "a": [
            1,
            {
              "s": "x, \\"y\\": [z]"
            }
          ],
          "e": {},
          "f": []
        }
        """)
        XCTAssertEqual(try DevTool.json.run(try DevTool.json.run(input), mode: 1),
                       #"{"b":1.0,"a":[1,{"s":"x, \"y\": [z]"}],"e":{},"f":[]}"#)
    }

    func testJSONReportsErrors() {
        XCTAssertThrowsError(try DevTool.json.run(#"{"a": }"#))
        XCTAssertEqual(try DevTool.json.run("  "), "")
    }

    func testBase64() throws {
        XCTAssertEqual(try DevTool.base64.run("hello?", mode: 0), "aGVsbG8/")
        XCTAssertEqual(try DevTool.base64.run("aGVsbG8/", mode: 1), "hello?")
        XCTAssertEqual(try DevTool.base64.run("aGVsbG8_", mode: 1), "hello?") // URL-safe
        XCTAssertEqual(try DevTool.base64.run("aGk", mode: 1), "hi") // no padding
        XCTAssertThrowsError(try DevTool.base64.run("!!!", mode: 1))
        XCTAssertThrowsError(try DevTool.base64.run("/w==", mode: 1)) // 0xFF is not UTF-8
    }

    func testURL() throws {
        XCTAssertEqual(try DevTool.url.run("a b&c=d/é", mode: 0), "a%20b%26c%3Dd%2F%C3%A9")
        XCTAssertEqual(try DevTool.url.run("a%20b%26c%3Dd%2F%C3%A9", mode: 1), "a b&c=d/é")
        XCTAssertThrowsError(try DevTool.url.run("%zz", mode: 1))
    }

    func testJWT() throws {
        // {"alg":"HS256"} . {"sub":"1","exp":1000} . signature
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIiwiZXhwIjoxMDAwfQ.sig"
        let output = try DevTool.jwt.run(token, now: Date(timeIntervalSince1970: 2000))
        XCTAssertTrue(output.contains(#""alg": "HS256""#))
        XCTAssertTrue(output.contains(#""sub": "1""#))
        XCTAssertTrue(output.contains("exp: 1970-01-01T00:16:40Z (expired)"))
        XCTAssertThrowsError(try DevTool.jwt.run("abc.def"))
    }

    func testTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let seconds = try DevTool.timestamp.run("1700000000", now: now)
        XCTAssertTrue(seconds.contains("UTC:          2023-11-14T22:13:20Z"))
        let millis = try DevTool.timestamp.run("1700000000123", now: now)
        XCTAssertTrue(millis.contains("Milliseconds: 1700000000123"))
        XCTAssertTrue(millis.contains("Seconds:      1700000000"))
        let iso = try DevTool.timestamp.run("2023-11-14T22:13:20Z", now: now)
        XCTAssertTrue(iso.contains("Seconds:      1700000000"))
        XCTAssertTrue(try DevTool.timestamp.run("", now: now).contains("Seconds:      1700000000"))
        XCTAssertThrowsError(try DevTool.timestamp.run("tomorrow", now: now))
    }

    func testHash() throws {
        let output = try DevTool.hash.run("abc")
        XCTAssertTrue(output.contains("MD5:     900150983cd24fb0d6963f7d28e17f72"))
        XCTAssertTrue(output.contains("SHA-256: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    }
}
