import Foundation

enum Charging: String, Codable { case charging, idle, unknown }
struct Reading {
    let id: String
    let name: String
    let symbol: String
    let percent: Int?
    let state: Charging
    let sampled: Date
    let evidence: String
    var fullChargeEvidence = false
    func fresh(at now: Date) -> Bool { (0..<90).contains(now.timeIntervalSince(sampled)) }
    var active: Bool { state == .charging && fresh(at: Date()) }
}
struct Session: Codable {
    var sent: Set<Int> = []
    var lastSeen: Date
    var lastPercent: Int?
    var ended = false
    var lastAlert: [Int: Date] = [:]
}
struct Thresholds {
    var sessions: [String: Session] = [:]
    private var continuousCharging = Set<String>()
    init(sessions: [String: Session] = [:], now: Date = Date()) {
        self.sessions = sessions
        prune(now: now)
    }
    mutating func invalidateContinuity() { continuousCharging.removeAll() }
    mutating func retainContinuity(for ids: Set<String>) { continuousCharging.formIntersection(ids) }
    @discardableResult mutating func prune(now: Date = Date()) -> Bool {
        let count = sessions.count
        sessions = sessions.filter { (0..<30 * 86400).contains(now.timeIntervalSince($0.value.lastSeen)) }
        return count != sessions.count
    }
    mutating func consume(_ r: Reading, now: Date = Date(), enabled: Set<Int> = [78,80,100]) -> [Int] {
        prune(now: now)
        guard r.fresh(at: now) else { continuousCharging.remove(r.id); return [] }
        let full = r.percent == 100 && r.fullChargeEvidence
        let priorCharging = continuousCharging.contains(r.id)
        if r.state == .charging, let percent = r.percent, (0...100).contains(percent) { continuousCharging.insert(r.id) }
        else if !full { continuousCharging.remove(r.id) }
        guard r.state != .unknown || full else { return [] }
        if r.state == .idle {
            var s = sessions[r.id] ?? Session(lastSeen: r.sampled)
            s.ended = true; s.lastSeen = r.sampled; s.lastPercent = nil
            sessions[r.id] = s
            return []
        }
        guard let reportedPercent = r.percent, (0...100).contains(reportedPercent) else {
            continuousCharging.remove(r.id)
            return []
        }
        // A Boolean charging indication at 100% is not the supported full-state
        // evidence required by the full milestone. Keep that crossing available.
        let percent = reportedPercent == 100 && !full ? 99 : reportedPercent
        var s = sessions[r.id] ?? Session(lastSeen: r.sampled)
        if s.ended { s.sent = []; s.lastPercent = nil; s.ended = false }
        // Establish a baseline on first observation, never send historical alerts.
        guard let previous = s.lastPercent, (0..<90).contains(r.sampled.timeIntervalSince(s.lastSeen)), priorCharging else {
            s.sent.formUnion([78, 80, 100].filter { percent >= $0 })
            s.lastSeen = r.sampled; s.lastPercent = percent; sessions[r.id] = s
            return []
        }
        let crossed = [78, 80, 100].filter { previous < $0 && percent >= $0 && !s.sent.contains($0) }
        s.sent.formUnion(crossed)
        // A short persisted cooldown also protects against noisy idle/charging flips.
        let eligible = crossed.filter { enabled.contains($0) && now.timeIntervalSince(s.lastAlert[$0] ?? .distantPast) >= 300 }
        if let highest = eligible.max() { for threshold in eligible { s.lastAlert[threshold] = now }; s.lastAlert[highest] = now }
        s.lastSeen = r.sampled; s.lastPercent = percent; sessions[r.id] = s
        return eligible.max().map { [$0] } ?? []
    }
}

// Process-local continuity is intentional: a restart must establish a new
// baseline, never replay a historical "started" event from persisted state.
struct ChargingStarts {
    private var armedIdle: [String: Reading] = [:]
    private(set) var lastDecisions: [String] = []
    mutating func invalidate() { armedIdle.removeAll(); lastDecisions.removeAll() }
    mutating func consume(_ readings: [Reading], now: Date = Date()) -> [Reading] {
        // A short transport gap is not proof that a fresh observed idle ended.
        // Only a same-identity idle sample can arm a start, and it expires in90s.
        armedIdle = armedIdle.filter { $0.value.fresh(at: now) }
        lastDecisions = []
        var result: [Reading] = []
        for r in reconciled(readings) {
            guard r.fresh(at: now) else {
                armedIdle.removeValue(forKey: r.id)
                lastDecisions.append("\(r.name): stale observation; start not armed")
                continue
            }
            switch r.state {
            case .idle:
                armedIdle[r.id] = r
                lastDecisions.append("\(r.name): idle observed; next fresh charging transition armed")
            case .unknown:
                lastDecisions.append("\(r.name): unknown; \(armedIdle[r.id] == nil ? "no verified idle baseline" : "recent idle retained briefly")")
            case .charging:
                let idle = armedIdle.removeValue(forKey: r.id)
                guard let idle = idle, idle.fresh(at: now) else {
                    lastDecisions.append("\(r.name): charging baseline; no new idle transition")
                    continue
                }
                guard let percent = r.percent, (0...100).contains(percent) else {
                    lastDecisions.append("\(r.name): start skipped; battery percentage unavailable")
                    continue
                }
                result.append(r)
                lastDecisions.append("\(r.name): verified charging start selected")
            }
        }
        return result
    }
}

// Selection and asynchronous submission use the same evidence requirements.
enum AlertEvidence {
    static func allows(_ reading: Reading, kind: AlertKind, now: Date) -> Bool {
        guard reading.fresh(at: now), let percent = reading.percent, (0...100).contains(percent) else { return false }
        if kind == .full { return percent == 100 && reading.fullChargeEvidence }
        if kind == .soon && percent < 78 { return false }
        if kind == .target && percent < 80 { return false }
        return reading.state == .charging || (percent == 100 && reading.fullChargeEvidence)
    }
}
