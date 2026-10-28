import Foundation

/// One background read at a time. A fixed coalescing window bounds event latency
/// even during continuous bursts; a burst during a read retains one final read.
final class CollectionScheduler {
    typealias Collection = (@escaping (CollectionOutcome) -> Void) -> Void
    private let collect: Collection
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let receive: (CollectionOutcome) -> Void
    private var scheduled = false
    private var running = false
    private var pending = false
    private var generation: UInt64 = 0
    private(set) var suspended = false
    private(set) var snapshotCount = 0

    init(collect: @escaping Collection, schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         receive: @escaping (CollectionOutcome) -> Void) {
        self.collect = collect; self.schedule = schedule; self.receive = receive
    }
    func request() {
        guard !suspended else { return }
        if running { pending = true; return }
        guard !scheduled else { return }
        scheduled = true
        let token = generation
        schedule(0.25) {
            guard token == self.generation, !self.suspended else { return }
            self.scheduled = false
            self.running = true
            self.snapshotCount += 1
            self.collect { outcome in
                self.running = false
                if token == self.generation && !self.suspended { self.receive(outcome) }
                if self.pending { self.pending = false; self.request() }
            }
        }
    }
    func suspend() { suspended = true; generation += 1; scheduled = false; pending = false }
    func resume() { suspended = false; generation += 1; request() }
}
