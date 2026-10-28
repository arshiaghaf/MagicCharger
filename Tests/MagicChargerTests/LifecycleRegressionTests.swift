import XCTest
@testable import MagicCharger

final class LifecycleRegressionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func r(_ percent: Int, state: Charging = .charging, at: Date? = nil, full: Bool = false) -> Reading {
        Reading(id: "fixture", name: "Simulation", symbol: "keyboard", percent: percent, state: state,
                sampled: at ?? now, evidence: "SIMULATED", fullChargeEvidence: full)
    }
    func testRestartAndEveryContinuityInterruptionBaselineAllMilestones() throws {
        for interrupt in 0...4 {
            var engine = Thresholds()
            _ = engine.consume(r(77), now: now)
            switch interrupt {
            case 0: engine = Thresholds(sessions: try JSONDecoder().decode([String: Session].self,
                from: JSONEncoder().encode(engine.sessions)), now: now)
            case 1: engine.invalidateContinuity() // sleep
            case 2: engine.retainContinuity(for: []) // disconnect
            case 3: _ = engine.consume(r(77, state: .unknown), now: now)
            default: _ = engine.consume(r(77, at: now.addingTimeInterval(-91)), now: now)
            }
            XCTAssertEqual(engine.consume(r(79), now: now), [], "interruption \(interrupt)")
            XCTAssertEqual(engine.consume(r(81), now: now), [80], "a subsequent genuine crossing remains eligible")
            XCTAssertEqual(engine.consume(r(82), now: now), [])
        }
        var sleep = Thresholds(); _ = sleep.consume(r(77), now: now); sleep.invalidateContinuity()
        XCTAssertEqual(sleep.consume(r(81), now: now), [])
    }
    func testBaselinePreservesConsumedAndCooldownHistory() {
        var engine = Thresholds(); _ = engine.consume(r(77), now: now)
        XCTAssertEqual(engine.consume(r(78), now: now), [78])
        let before = engine.sessions["fixture"]?.lastAlert
        engine.invalidateContinuity()
        _ = engine.consume(r(77), now: now)
        XCTAssertEqual(engine.consume(r(78), now: now), [])
        XCTAssertEqual(engine.sessions["fixture"]?.lastAlert, before)
    }
    func testBooleanFullWithoutSupportedFullEvidenceIsNotConsumedOrSubmitted() {
        var engine = Thresholds(); _ = engine.consume(r(99), now: now)
        XCTAssertEqual(engine.consume(r(100), now: now), [])
        XCTAssertEqual(engine.sessions["fixture"]?.lastPercent, 100)
        XCTAssertFalse(engine.sessions["fixture"]?.sent.contains(100) ?? true)
        XCTAssertFalse(AlertEvidence.allows(r(100), kind: .full, now: now))
        let supported = r(100, state: .unknown, full: true)
        XCTAssertEqual(engine.consume(supported, now: now), [100])
        XCTAssertTrue(AlertEvidence.allows(supported, kind: .full, now: now))
        XCTAssertTrue(AlertEvidence.allows(supported, kind: .target, now: now))
    }
    func testPruningOnLoadAndWithoutUsableReadings() {
        let expired = Session(lastSeen: now.addingTimeInterval(-30 * 86400))
        var engine = Thresholds(sessions: ["old": expired, "fresh": Session(lastSeen: now)], now: now)
        XCTAssertNil(engine.sessions["old"])
        XCTAssertNotNil(engine.sessions["fresh"])
        let later = now.addingTimeInterval(31 * 86400)
        XCTAssertTrue(engine.prune(now: later)) // empty snapshots need no consume call
        XCTAssertTrue(engine.sessions.isEmpty)
        engine.sessions["old"] = expired
        _ = engine.consume(r(78, state: .unknown), now: now)
        XCTAssertNil(engine.sessions["old"])
        engine.sessions["old"] = expired
        _ = engine.consume(r(78, at: now.addingTimeInterval(-100)), now: now)
        XCTAssertNil(engine.sessions["old"])
        let restarted = Thresholds(sessions: engine.sessions, now: later)
        XCTAssertTrue(restarted.sessions.isEmpty)
    }
    func testLaunchAtUnsupportedFullDoesNotInventALaterCrossing() {
        var engine = Thresholds()
        XCTAssertEqual(engine.consume(r(100), now: now), [])
        XCTAssertEqual(engine.sessions["fixture"]?.lastPercent, 100)
        XCTAssertFalse(engine.sessions["fixture"]?.sent.contains(100) ?? true)
        XCTAssertEqual(engine.consume(r(100, state: .unknown, full: true), now: now), [])
        // A real later below-full to full crossing remains eligible.
        _ = engine.consume(r(99), now: now)
        XCTAssertEqual(engine.consume(r(100, state: .unknown, full: true), now: now), [100])
    }

    func testPendingFullCrossingDoesNotSurviveLifecycleInterruptions() {
        for interruption in 0...4 {
            var engine = Thresholds()
            _ = engine.consume(r(99), now: now)
            _ = engine.consume(r(100), now: now)
            switch interruption {
            case 0: engine = Thresholds(sessions: engine.sessions, now: now)
            case 1: engine.invalidateContinuity()
            case 2: engine.retainContinuity(for: [])
            case 3: _ = engine.consume(r(100, state: .unknown), now: now)
            default: _ = engine.consume(r(100, at: now.addingTimeInterval(-100)), now: now)
            }
            XCTAssertEqual(engine.consume(r(100, state: .unknown, full: true), now: now), [], "interruption \(interruption)")
        }
    }

}
