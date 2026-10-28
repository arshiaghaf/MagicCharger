import XCTest
@testable import MagicCharger
final class ThresholdTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func reading(_ p: Int, _ state: Charging = .charging, id: String = "a", at date: Date? = nil) -> Reading { Reading(id: id, name: "Simulation", symbol: "keyboard", percent: p, state: state, sampled: date ?? now, evidence: "SIMULATED") }
    func testSkippedThresholdsAndRestart() throws {
        var t = Thresholds(); XCTAssertEqual(t.consume(reading(77), now: now), []); XCTAssertEqual(t.consume(reading(81), now: now), [80])
        t.sessions = try JSONDecoder().decode([String: Session].self, from: JSONEncoder().encode(t.sessions))
        XCTAssertEqual(t.consume(reading(82), now: now), [])
        XCTAssertEqual(t.consume(reading(77, id: "b"), now: now), []); XCTAssertEqual(t.consume(reading(78, id: "b"), now: now), [78])
    }
    func testBaselineUnknownDisconnectAndNewSessionCooldown() {
        var t = Thresholds()
        XCTAssertEqual(t.consume(reading(90), now: now), [])
        XCTAssertEqual(t.consume(reading(70, .idle), now: now), [])
        XCTAssertEqual(t.consume(reading(77), now: now), [])
        XCTAssertEqual(t.consume(reading(78), now: now), [78])
        XCTAssertEqual(t.consume(reading(0, .unknown), now: now), [])
        XCTAssertEqual(t.consume(reading(77), now: now), [])
        XCTAssertEqual(t.consume(reading(78), now: now), [])
        XCTAssertEqual(t.consume(reading(77, .idle), now: now), [])
        XCTAssertEqual(t.consume(reading(77), now: now), [])
        XCTAssertEqual(t.consume(reading(78), now: now), [])
        let later = now.addingTimeInterval(301)
        XCTAssertEqual(t.consume(reading(77, .idle, at: later), now: later), [])
        XCTAssertEqual(t.consume(reading(77, at: later), now: later), [])
        XCTAssertEqual(t.consume(reading(78, at: later), now: later), [78])
    }
    func testStaleAndFutureCannotAlertOrEndSession() {
        var t = Thresholds(); _ = t.consume(reading(77), now: now); XCTAssertEqual(t.consume(reading(78), now: now), [78])
        _ = t.consume(reading(0, .idle, at: now.addingTimeInterval(-100)), now: now)
        XCTAssertEqual(t.consume(reading(78), now: now), [])
        XCTAssertEqual(t.consume(reading(80, at: now.addingTimeInterval(100)), now: now), [])
        XCTAssertEqual(t.consume(reading(80), now: now), []) // Fresh recovery establishes a baseline.
    }
    func testLongUnknownGapDoesNotReplayHistoricalCrossing() {
        var t = Thresholds(); _ = t.consume(reading(77), now: now)
        let later = now.addingTimeInterval(120)
        XCTAssertEqual(t.consume(reading(81, at: later), now: later), [])
        XCTAssertEqual(t.consume(reading(82, at: later), now: later), [])
    }
    func testPrivateIdentitySurvivesReconnectWithoutModelMerging() {
        let key = Data(repeating: 1, count: 32)
        let a = DeviceIdentity.stable(address: "00:11:22:33:44:55", productID: 100, key: key)
        XCTAssertEqual(a, DeviceIdentity.stable(address: "00-11-22-33-44-55", productID: 100, key: key))
        XCTAssertNotEqual(a, DeviceIdentity.stable(address: "00:11:22:33:44:56", productID: 100, key: key))
        XCTAssertNotEqual(a, DeviceIdentity.stable(address: "00:11:22:33:44:55", productID: 100, key: Data(repeating: 2, count: 32)))
        XCTAssertNil(DeviceIdentity.stable(address: nil, productID: 100, key: key))
        XCTAssertNil(DeviceIdentity.stable(address: "invalid", productID: 100, key: key))
    }
}
