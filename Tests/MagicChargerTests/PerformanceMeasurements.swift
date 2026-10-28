import XCTest
import Darwin
@testable import MagicCharger

/// Opt-in, read-only measurement harness. It never opens the app, posts alerts,
/// changes preferences or asks for permissions. No accessory identifiers escape.
final class PerformanceMeasurements: XCTestCase {
    private func usage() throws -> rusage_info_v4 {
        var info = rusage_info_v4()
        let code = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        XCTAssertEqual(code, 0)
        return info
    }
    private func measure(seconds: Double, bursts: Bool) throws {
        let monitor = AccessoryMonitor()
        let queue = DispatchQueue(label: "MagicChargerTests.performance", qos: .utility)
        var callbacks = 0, successful = 0, failures = 0
        let scheduler = CollectionScheduler(collect: { done in
            monitor.observeRegistry()
            queue.async {
                let outcome = snapshot(identityKey: Data(repeating: 7, count: 32))
                DispatchQueue.main.async { done(outcome) }
            }
        }, schedule: { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) }, receive: { outcome in
            switch outcome { case .success: successful += 1; case .failure: failures += 1 }
        })
        monitor.onChange = { callbacks += 1; scheduler.request() }
        let first = try usage(), start = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in scheduler.request() }
        timer.tolerance = 5
        defer { timer.invalidate(); scheduler.suspend(); monitor.onChange = nil }
        scheduler.request()
        if bursts {
            for burst in 0..<10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(burst) * 0.1) {
                    for _ in 0..<100 { scheduler.request() }
                }
            }
        }
        let finish = expectation(description: "sample duration")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish.fulfill() }
        wait(for: [finish], timeout: seconds + 5)
        let elapsed = Date().timeIntervalSince(start), last = try usage()
        let cpu = Double((last.ri_user_time - first.ri_user_time) + (last.ri_system_time - first.ri_system_time)) / 1_000_000_000
        print(String(format: "MEASUREMENT mode=%@ elapsed=%.3fs cpu=%.6fs oneCoreCPU=%.4f%% resident=%.2fMiB footprint=%.2fMiB interruptWakeups=%llu packageIdleWakeups=%llu snapshots=%d success=%d failures=%d registryCallbacks=%d injectedRequests=%d",
                     bursts ? "injected-burst" : "idle", elapsed, cpu, 100 * cpu / elapsed,
                     Double(last.ri_resident_size) / 1_048_576, Double(last.ri_phys_footprint) / 1_048_576,
                     last.ri_interrupt_wkups - first.ri_interrupt_wkups, last.ri_pkg_idle_wkups - first.ri_pkg_idle_wkups,
                     scheduler.snapshotCount, successful, failures, callbacks, bursts ? 1000 : 0))
        XCTAssertGreaterThan(successful, 0, "A live read must succeed to count as measurement evidence.")
    }
    func testOptimizedIdleMeasurement() throws {
        guard let value = ProcessInfo.processInfo.environment["MAGIC_CHARGER_PERFORMANCE_SECONDS"],
              let seconds = Double(value), (30...600).contains(seconds) else { throw XCTSkip("Opt-in live telemetry performance sample") }
        try measure(seconds: seconds, bursts: false)
    }
    func testOptimizedInjectedBurstMeasurement() throws {
        guard ProcessInfo.processInfo.environment["MAGIC_CHARGER_PERFORMANCE_SECONDS"] != nil else { throw XCTSkip("Opt-in live telemetry performance sample") }
        try measure(seconds: 3, bursts: true)
    }
}
