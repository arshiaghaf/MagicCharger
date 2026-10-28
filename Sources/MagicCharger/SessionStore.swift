import Foundation

struct SessionStore {
    let defaults: UserDefaults
    private let key = "chargingSessions.v2"
    func load(now: Date = Date()) -> Thresholds {
        let sessions = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Session].self, from: $0) } ?? [:]
        let result = Thresholds(sessions: sessions.filter { DeviceIdentity.isPersistent($0.key) }, now: now)
        save(result.sessions) // Expiration is persisted independently of telemetry.
        return result
    }
    func save(_ sessions: [String: Session]) {
        let persistent = sessions.filter { DeviceIdentity.isPersistent($0.key) }
        if let data = try? JSONEncoder().encode(persistent) { defaults.set(data, forKey: key) }
    }
}
