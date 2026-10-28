import Foundation

/// Retry only failed registration/enumeration work, including on stable topology.
struct ObservationRecovery {
    private(set) var dirty = true
    private(set) var failures = 0
    private(set) var retryAt = Date.distantPast
    mutating func invalidate() { dirty = true }
    func shouldAttempt(at now: Date) -> Bool { dirty && now >= retryAt }
    mutating func finish(success: Bool, now: Date) {
        dirty = !success
        if success { failures = 0; retryAt = .distantPast }
        else {
            failures = min(failures + 1, 6)
            retryAt = now.addingTimeInterval(min(60, pow(2, Double(failures - 1))))
        }
    }
}
