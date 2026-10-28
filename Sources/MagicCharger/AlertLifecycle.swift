import Foundation

struct SelectedAlert {
    let reading: Reading
    let kind: AlertKind
}
struct AlertTicket {
    let reading: Reading
    let kind: AlertKind
    let generation: UInt64
    let revision: UInt64
}

/// Shared by collection, selection and asynchronous delivery on the main queue.
struct AlertLifecycle {
    var thresholds = Thresholds()
    var starts = ChargingStarts()
    private(set) var latest: [String: Reading] = [:]
    private(set) var suspended = false
    private var generation: UInt64 = 0
    private var revisions: [String: UInt64] = [:]

    mutating func suspend() {
        suspended = true; generation += 1
        latest.removeAll(); starts.invalidate(); thresholds.invalidateContinuity()
    }
    mutating func resume() { suspended = false; generation += 1 }
    mutating func observe(_ input: [Reading], now: Date, preferences: NotificationPreferences,
                          allowsDevice: (String) -> Bool = { _ in true }) -> [SelectedAlert] {
        thresholds.prune(now: now)
        guard !suspended else { return [] }
        let readings = reconciled(input)
        let current = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        // Interrupting evidence invalidates selected alerts even if a later
        // reconnect is charging before the authorization callback returns.
        for (id, old) in latest {
            if let new = current[id], old.fresh(at: now), new.fresh(at: now),
               old.state == new.state, old.fullChargeEvidence == new.fullChargeEvidence,
               (new.percent ?? -1) >= (old.percent ?? -1) { continue }
            revisions[id, default: 0] += 1
        }
        latest = current
        thresholds.retainContinuity(for: Set(current.keys))
        var selected = starts.consume(readings, now: now)
            .filter { preferences.started && allowsDevice($0.id) }
            .map { SelectedAlert(reading: $0, kind: .started) }
        for reading in readings {
            let enabled = allowsDevice(reading.id) ? preferences.milestones : []
            selected += thresholds.consume(reading, now: now, enabled: enabled)
                .map { SelectedAlert(reading: reading, kind: .milestone($0)) }
        }
        return selected
    }
    func ticket(for reading: Reading, kind: AlertKind) -> AlertTicket {
        AlertTicket(reading: reading, kind: kind, generation: generation, revision: revisions[reading.id] ?? 0)
    }
    func validates(_ ticket: AlertTicket, now: Date) -> Bool {
        guard !suspended, ticket.generation == generation,
              ticket.revision == (revisions[ticket.reading.id] ?? 0),
              AlertEvidence.allows(ticket.reading, kind: ticket.kind, now: now),
              let current = latest[ticket.reading.id] else { return false }
        return AlertEvidence.allows(current, kind: ticket.kind, now: now)
    }
}

/// Tests hold/reorder these callbacks without posting native notifications.
final class AlertDelivery {
    typealias Authorization = (@escaping (Bool) -> Void) -> Void
    typealias Submission = (@escaping (Bool) -> Void) -> Void
    private let authorize: Authorization
    private let schedule: (@escaping () -> Void) -> Void
    init(authorize: @escaping Authorization, schedule: @escaping (@escaping () -> Void) -> Void) {
        self.authorize = authorize; self.schedule = schedule
    }
    func submit(isValid: @escaping () -> Bool, send: @escaping Submission, feedback: @escaping (String) -> Void) {
        guard isValid() else { return }
        authorize { allowed in
            self.schedule {
                guard isValid() else { feedback("Automatic alert canceled: charging evidence or notification choice changed."); return }
                guard allowed else { feedback("Automatic alert not submitted: notification permission unavailable."); return }
                send { success in
                    self.schedule {
                        guard isValid() else { return }
                        feedback(success ? "Automatic notification submitted to macOS." : "Automatic notification submission failed; check notification settings.")
                    }
                }
            }
        }
    }
}
