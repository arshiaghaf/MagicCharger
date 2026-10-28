import Foundation

/// Only locally keyed identities, generic model labels and alert choices are saved.
struct DeviceSettings {
    struct Entry: Codable {
        var family: String
        var ordinal: Int
        var muted = false
    }
    private(set) var entries: [String: Entry] = [:]
    private var revisions: [String: UInt64] = [:]
    private let defaults: UserDefaults?
    private static let storage = "deviceSettings.v1"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storage),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded.filter { DeviceIdentity.isPersistent($0.key) && $0.value.ordinal > 0 && ["Magic Keyboard", "Magic Mouse"].contains($0.value.family) }
        }
    }
    mutating func register(_ readings: [Reading]) {
        var changed = false
        for r in readings.sorted(by: { $0.id < $1.id }) where entries[r.id] == nil {
            let family = r.symbol == "keyboard" ? "Magic Keyboard" : "Magic Mouse"
            let ordinal = (entries.values.filter { $0.family == family }.map { $0.ordinal }.max() ?? 0) + 1
            entries[r.id] = Entry(family: family, ordinal: ordinal)
            changed = true
        }
        if changed { save() }
    }
    func displayName(for r: Reading) -> String {
        guard let entry = entries[r.id] else { return r.symbol == "keyboard" ? "Magic Keyboard" : "Magic Mouse" }
        return "\(entry.family) \(entry.ordinal)"
    }
    func isMuted(_ id: String) -> Bool { entries[id]?.muted ?? false }
    func revision(for id: String) -> UInt64 { revisions[id] ?? 0 }
    mutating func setMuted(_ muted: Bool, for id: String) {
        guard entries[id] != nil, entries[id]?.muted != muted else { return }
        entries[id]?.muted = muted
        revisions[id, default: 0] += 1
        save()
    }
    func labeled(_ readings: [Reading]) -> [Reading] {
        readings.map { r in
            Reading(id: r.id, name: displayName(for: r), symbol: r.symbol, percent: r.percent,
                    state: r.state, sampled: r.sampled, evidence: r.evidence, fullChargeEvidence: r.fullChargeEvidence)
        }
    }
    private func save() {
        let stable = entries.filter { DeviceIdentity.isPersistent($0.key) }
        if let data = try? JSONEncoder().encode(stable) { defaults?.set(data, forKey: Self.storage) }
    }
}
