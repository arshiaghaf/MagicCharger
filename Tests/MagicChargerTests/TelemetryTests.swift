import XCTest
@testable import MagicCharger

final class TelemetryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func testSnapshotDictionaryTransitionsMissingAndConflictingValues() throws {
        let os = OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0)
        var properties: [String: Any] = ["Product": "Magic Keyboard", "VendorID": 76, "ProductID": 801,
            "Transport": "Bluetooth", "BatteryPercent": 77, "BatteryStatusFlags": 4]
        func read(_ values: [String: Any]) throws -> Reading {
            try XCTUnwrap(AccessoryProperties.reading(values, entryID: 1, identityKey: Data(repeating: 1, count: 32), sampled: now, os: os))
        }
        XCTAssertEqual(try read(properties).state, .idle)
        properties["BatteryStatusFlags"] = 3
        XCTAssertEqual(try read(properties).state, .charging)
        properties["BatteryCharging"] = false
        XCTAssertEqual(try read(properties).state, .unknown)
        properties.removeValue(forKey: "BatteryCharging"); properties.removeValue(forKey: "BatteryStatusFlags")
        XCTAssertEqual(try read(properties).state, .unknown)
        properties["BatteryCharging"] = 1 // A non-Boolean number is not evidence.
        XCTAssertEqual(try read(properties).state, .unknown)
        properties["BatteryCharging"] = true; properties["IsCharging"] = false
        XCTAssertEqual(try read(properties).state, .unknown)
        XCTAssertFalse(AccessoryProperties.supports(product: "Magic Trackpad", vendor: 76))
        XCTAssertFalse(AccessoryProperties.supports(product: "Magic Keyboard", vendor: nil))
        XCTAssertFalse(AccessoryProperties.supports(product: nil, vendor: 76))
        properties["Product"] = "Unrelated HID"
        XCTAssertNil(AccessoryProperties.reading(properties, entryID: 1, identityKey: Data(), sampled: now, os: os))
    }
    func testFailuresRemainDistinctFromNoDevicesAndRecover() {
        XCTAssertTrue(CollectionOutcome.success([]).readings.isEmpty)
        XCTAssertNil(CollectionOutcome.success([]).message)
        XCTAssertNotNil(CollectionOutcome.failure(.registryUnavailable).message)
        XCTAssertNotNil(CollectionOutcome.failure(.propertiesUnavailable).message)
    }
    func testRegistrationAndEnumerationFailureBackoffOnStableTopology() {
        var recovery = ObservationRecovery()
        XCTAssertTrue(recovery.shouldAttempt(at: now))
        for attempt in 0..<10 {
            let time = now.addingTimeInterval(Double(attempt) * 61)
            XCTAssertTrue(recovery.shouldAttempt(at: time))
            recovery.finish(success: false, now: time)
            XCTAssertTrue(recovery.dirty)
            XCTAssertFalse(recovery.shouldAttempt(at: time))
            recovery.invalidate() // Events must not bypass failure backoff.
            XCTAssertFalse(recovery.shouldAttempt(at: time))
            XCTAssertTrue(recovery.shouldAttempt(at: time.addingTimeInterval(60)))
        }
        recovery.finish(success: true, now: now)
        XCTAssertFalse(recovery.dirty)
        XCTAssertFalse(recovery.shouldAttempt(at: now.addingTimeInterval(90)))
        recovery.invalidate()
        XCTAssertTrue(recovery.shouldAttempt(at: now))
    }
    func testBurstCoalescingRetainsFinalSnapshotAndBoundsLatency() {
        var scheduled: [() -> Void] = [], completions: [(CollectionOutcome) -> Void] = []
        var delays: [TimeInterval] = [], received = 0
        let scheduler = CollectionScheduler(collect: { completions.append($0) }, schedule: { delays.append($0); scheduled.append($1) }, receive: { _ in received += 1 })
        for _ in 0..<1000 { scheduler.request() }
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(delays, [0.25])
        scheduled.removeFirst()()
        for _ in 0..<1000 { scheduler.request() }
        XCTAssertEqual(completions.count, 1)
        completions.removeFirst()(.failure(.registryUnavailable))
        XCTAssertEqual(received, 1)
        XCTAssertEqual(scheduled.count, 1)
        scheduled.removeFirst()()
        completions.removeFirst()(.success([]))
        XCTAssertEqual(received, 2)
        XCTAssertEqual(scheduler.snapshotCount, 2)
        XCTAssertTrue(scheduled.isEmpty)
    }
    func testSleepCancelsScheduledAndInFlightGenerationsThenWakeCollectsFresh() {
        var scheduled: [() -> Void] = [], completions: [(CollectionOutcome) -> Void] = [], received = 0
        let scheduler = CollectionScheduler(collect: { completions.append($0) }, schedule: { _, action in scheduled.append(action) }, receive: { _ in received += 1 })
        scheduler.request(); scheduler.suspend(); scheduler.resume()
        scheduled.removeFirst()() // canceled pre-sleep work
        XCTAssertTrue(completions.isEmpty)
        scheduled.removeFirst()()
        XCTAssertEqual(completions.count, 1)
        scheduler.suspend(); scheduler.resume()
        completions.removeFirst()(.success([])) // pre-wake result is discarded
        XCTAssertEqual(received, 0)
        scheduled.removeFirst()()
        completions.removeFirst()(.success([]))
        XCTAssertEqual(received, 1)
    }
}
