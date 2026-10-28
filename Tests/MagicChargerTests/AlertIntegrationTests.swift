import XCTest
@testable import MagicCharger

final class AlertIntegrationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func r(_ percent: Int, state: Charging = .charging) -> Reading {
        Reading(id: "fixture", name: "Simulation", symbol: "keyboard", percent: percent,
                state: state, sampled: now, evidence: "SIMULATED")
    }
    func testHeldAuthorizationCannotEscapeInterruptedLifecycleOrPreferenceOffOn() throws {
        for interruption in 0...6 {
            var lifecycle = AlertLifecycle()
            var settings = AlertSettings(preferences: NotificationPreferences())
            _ = lifecycle.observe([r(77)], now: now, preferences: settings.preferences)
            let selected = try XCTUnwrap(lifecycle.observe([r(81)], now: now, preferences: settings.preferences).first)
            let ticket = lifecycle.ticket(for: selected.reading, kind: selected.kind)
            let token = settings.token(selected.kind)
            var authorization: ((Bool) -> Void)?
            var sent = 0
            let delivery = AlertDelivery(authorize: { authorization = $0 }, schedule: { $0() })
            delivery.submit(isValid: { lifecycle.validates(ticket, now: self.now) && settings.canSubmit(selected.kind, token: token) },
                            send: { completion in sent += 1; completion(true) }, feedback: { _ in })
            switch interruption {
            case 0: lifecycle.suspend(); lifecycle.resume()
            case 1: _ = lifecycle.observe([], now: now, preferences: settings.preferences)
            case 2: _ = lifecycle.observe([r(81, state: .unknown)], now: now, preferences: settings.preferences)
            case 3: _ = lifecycle.observe([r(81, state: .idle)], now: now, preferences: settings.preferences)
            case 4:
                var preferences = settings.preferences; preferences.target = false; settings.update(preferences)
                preferences.target = true; settings.update(preferences)
            case 5: _ = lifecycle.observe([r(75)], now: now, preferences: settings.preferences)
            default:
                let stale = Reading(id: "fixture", name: "Simulation", symbol: "keyboard", percent: 81,
                    state: .charging, sampled: now.addingTimeInterval(-100), evidence: "SIMULATED")
                _ = lifecycle.observe([stale], now: now, preferences: settings.preferences)
            }
            _ = lifecycle.observe([r(82)], now: now, preferences: settings.preferences)
            authorization?(true)
            XCTAssertEqual(sent, 0, "interruption \(interruption)")
        }
    }
    func testCollectionReconciliationSelectionAndDelayedSubmission() throws {
        var lifecycle = AlertLifecycle()
        let preferences = NotificationPreferences()
        _ = lifecycle.observe([r(77), r(77)], now: now, preferences: preferences)
        let alerts = lifecycle.observe([r(81), r(81)], now: now, preferences: preferences)
        XCTAssertEqual(alerts.count, 1)
        let selected = try XCTUnwrap(alerts.first)
        XCTAssertEqual(selected.kind, .target)
        let ticket = lifecycle.ticket(for: selected.reading, kind: selected.kind)
        var tasks: [() -> Void] = [], sent = 0, messages: [String] = []
        let delivery = AlertDelivery(authorize: { $0(true) }, schedule: { tasks.append($0) })
        delivery.submit(isValid: { lifecycle.validates(ticket, now: self.now) }, send: { completion in sent += 1; completion(true) }, feedback: { messages.append($0) })
        XCTAssertEqual(sent, 0)
        tasks.removeFirst()()
        XCTAssertEqual(sent, 1)
        tasks.removeFirst()()
        XCTAssertEqual(messages, ["Automatic notification submitted to macOS."])
        XCTAssertTrue(lifecycle.observe([r(82)], now: now, preferences: preferences).isEmpty)
        // A conflicting duplicate transport cannot keep a selected request alive.
        _ = lifecycle.observe([r(82), r(82, state: .idle)], now: now, preferences: preferences)
        XCTAssertFalse(lifecycle.validates(ticket, now: now))
    }
    func testDeniedFailedAndLateCompletionDoNotReplayOrUpdateNewLifecycle() throws {
        for allowed in [false, true] {
            var lifecycle = AlertLifecycle()
            _ = lifecycle.observe([r(77)], now: now, preferences: NotificationPreferences())
            let alert = try XCTUnwrap(lifecycle.observe([r(81)], now: now, preferences: NotificationPreferences()).first)
            let ticket = lifecycle.ticket(for: alert.reading, kind: alert.kind)
            var sent = 0, messages: [String] = []
            let delivery = AlertDelivery(authorize: { $0(allowed) }, schedule: { $0() })
            delivery.submit(isValid: { lifecycle.validates(ticket, now: self.now) }, send: { done in sent += 1; done(false) }, feedback: { messages.append($0) })
            XCTAssertEqual(sent, allowed ? 1 : 0)
            XCTAssertEqual(messages.count, 1)
            XCTAssertTrue(lifecycle.observe([r(82)], now: now, preferences: NotificationPreferences()).isEmpty)
            var completion: ((Bool) -> Void)?
            delivery.submit(isValid: { lifecycle.validates(ticket, now: self.now) }, send: { completion = $0 }, feedback: { messages.append($0) })
            lifecycle.suspend(); lifecycle.resume(); completion?(true)
            XCTAssertEqual(messages.count, allowed ? 1 : 2)
        }
    }
    func testLoadPrunesAndPersistsWithoutAnyCollection() throws {
        let suite = "MagicChargerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SessionStore(defaults: defaults)
        let expired = "device:" + String(repeating: "0", count: 64)
        let fresh = "device:" + String(repeating: "1", count: 64)
        store.save([expired: Session(lastSeen: now.addingTimeInterval(-31 * 86400)), fresh: Session(lastSeen: now)])
        XCTAssertEqual(store.load(now: now).sessions.count, 1)
        let persisted = try JSONDecoder().decode([String: Session].self, from: XCTUnwrap(defaults.data(forKey: "chargingSessions.v2")))
        XCTAssertNil(persisted[expired])
        XCTAssertNotNil(persisted[fresh])
    }
}
