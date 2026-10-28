import XCTest
@testable import MagicCharger

final class DeviceSettingsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func id(_ byte: UInt8) -> String { "device:" + String(repeating: String(format: "%02x", byte), count: 32) }
    func r(_ id: String, _ percent: Int = 77, state: Charging = .charging, symbol: String = "keyboard") -> Reading {
        Reading(id: id, name: "Personalized name must not persist", symbol: symbol, percent: percent,
                state: state, sampled: now, evidence: "SIMULATED")
    }
    func testStableOrdinalsAndMuteSurviveReconnectRestartAndReordering() throws {
        let suite = "MagicChargerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = DeviceSettings(defaults: defaults)
        let a = r(id(1)), b = r(id(2)), mouse = r(id(3), symbol: "magicmouse")
        settings.register([b, mouse, a])
        XCTAssertEqual(settings.displayName(for: a), "Magic Keyboard 1")
        XCTAssertEqual(settings.displayName(for: b), "Magic Keyboard 2")
        XCTAssertEqual(settings.displayName(for: mouse), "Magic Mouse 1")
        settings.setMuted(true, for: a.id)
        let revision = settings.revision(for: a.id)
        settings.setMuted(true, for: a.id)
        XCTAssertEqual(settings.revision(for: a.id), revision)
        var restart = DeviceSettings(defaults: defaults)
        restart.register([a]); restart.register([mouse, b, a])
        XCTAssertEqual(restart.displayName(for: a), "Magic Keyboard 1")
        XCTAssertEqual(restart.displayName(for: b), "Magic Keyboard 2")
        XCTAssertTrue(restart.isMuted(a.id)); XCTAssertFalse(restart.isMuted(b.id))
        XCTAssertEqual(restart.labeled([a, b]).map { $0.name }, ["Magic Keyboard 1", "Magic Keyboard 2"])
        let saved = try XCTUnwrap(defaults.data(forKey: "deviceSettings.v1"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("Personalized"))
        let entries = try JSONDecoder().decode([String: DeviceSettings.Entry].self, from: saved)
        XCTAssertEqual(entries.count, 3)
    }
    func testRegistryOnlyIdentityAndMuteRemainProcessLocal() throws {
        let suite = "MagicChargerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = DeviceSettings(defaults: defaults)
        let transient = r("registry:801:1")
        settings.register([transient]); settings.setMuted(true, for: transient.id)
        XCTAssertTrue(settings.isMuted(transient.id))
        let restart = DeviceSettings(defaults: defaults)
        XCTAssertFalse(restart.isMuted(transient.id))
        XCTAssertTrue(restart.entries.isEmpty)
    }
    func testMutedCrossingsConsumedAndUnmuteEstablishesBaselineWithoutBacklog() {
        var settings = DeviceSettings()
        let a = r(id(1)), b = r(id(2))
        settings.register([a, b])
        var lifecycle = AlertLifecycle()
        func observe(_ readings: [Reading]) -> [SelectedAlert] {
            lifecycle.observe(readings, now: now, preferences: NotificationPreferences(), allowsDevice: { !settings.isMuted($0) })
        }
        _ = observe([a, b])
        settings.setMuted(true, for: a.id); lifecycle.invalidateDevice(a.id)
        let selected = observe([r(a.id, 81), r(b.id, 81)])
        XCTAssertEqual(selected.map { $0.reading.id }, [b.id])
        XCTAssertTrue(lifecycle.thresholds.sessions[a.id]?.sent.contains(80) == true)
        settings.setMuted(false, for: a.id); lifecycle.invalidateDevice(a.id)
        XCTAssertTrue(observe([r(a.id, 82), r(b.id, 82)]).isEmpty)
        // An unobserved crossing during a mute is also baselined on unmute.
        var other = AlertLifecycle(); _ = other.observe([a], now: now, preferences: NotificationPreferences())
        other.invalidateDevice(a.id)
        XCTAssertTrue(other.observe([r(a.id, 81)], now: now, preferences: NotificationPreferences()).isEmpty)
    }
    func testMuteOffOnCancelsHeldSubmissionWithoutAffectingOtherDevice() throws {
        var lifecycle = AlertLifecycle(), settings = DeviceSettings()
        let a = r(id(1)), b = r(id(2))
        settings.register([a, b])
        _ = lifecycle.observe([a, b], now: now, preferences: NotificationPreferences())
        let alerts = lifecycle.observe([r(a.id, 81), r(b.id, 81)], now: now, preferences: NotificationPreferences())
        let tickets = alerts.map { lifecycle.ticket(for: $0.reading, kind: $0.kind) }
        settings.setMuted(true, for: a.id); lifecycle.invalidateDevice(a.id)
        settings.setMuted(false, for: a.id); lifecycle.invalidateDevice(a.id)
        XCTAssertFalse(lifecycle.validates(try XCTUnwrap(tickets.first { $0.reading.id == a.id }), now: now))
        XCTAssertTrue(lifecycle.validates(try XCTUnwrap(tickets.first { $0.reading.id == b.id }), now: now))
    }
    func testRegistrySessionKeysAreRemovedOnLoadAndNeverPersisted() throws {
        let suite = "MagicChargerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = ["registry:801:42": Session(lastSeen: now), id(1): Session(lastSeen: now)]
        let store = SessionStore(defaults: defaults)
        // Simulate history from an earlier preview, without a raw real identifier.
        defaults.set(try JSONEncoder().encode(sessions), forKey: "chargingSessions.v2")
        XCTAssertEqual(Set(store.load(now: now).sessions.keys), [id(1)])
        store.save(sessions)
        let saved = try JSONDecoder().decode([String: Session].self, from: XCTUnwrap(defaults.data(forKey: "chargingSessions.v2")))
        XCTAssertEqual(Set(saved.keys), [id(1)])
        XCTAssertFalse(DeviceIdentity.isPersistent("device:short"))
        XCTAssertFalse(DeviceIdentity.isPersistent("registry:801:42"))
    }

    func testMuteTransitionBaselinesPendingFullEvidenceWithoutReplay() {
        let a = r(id(1), 99)
        var lifecycle = AlertLifecycle()
        _ = lifecycle.observe([a], now: now, preferences: NotificationPreferences())
        XCTAssertTrue(lifecycle.observe([r(a.id, 100)], now: now, preferences: NotificationPreferences()).isEmpty)
        lifecycle.invalidateDevice(a.id) // mute or unmute
        let full = Reading(id: a.id, name: a.name, symbol: a.symbol, percent: 100,
            state: .unknown, sampled: now, evidence: "SIMULATED", fullChargeEvidence: true)
        XCTAssertTrue(lifecycle.observe([full], now: now, preferences: NotificationPreferences()).isEmpty)
    }

}
