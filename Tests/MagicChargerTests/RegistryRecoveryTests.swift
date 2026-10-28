import XCTest
import IOKit
@testable import MagicCharger

final class RegistryRecoveryTests: XCTestCase {
    func testPartialRegistrationAndEnumerationFailuresRecoverWithoutDuplicateHandles() throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        var matchingAttempts: [String: Int] = [:], interestAttempts: [io_service_t: Int] = [:]
        var enumerateAttempts = 0, released: [io_object_t] = [], destroyed = 0
        var present: [RegistryService] = [RegistryService(id: 1, object: 11), RegistryService(id: 2, object: 12)]
        let operations = RegistryOperations(createPort: { OpaquePointer(bitPattern: 1) }, matching: { _, kind, _ in
            matchingAttempts[kind, default: 0] += 1
            if kind == kIOFirstMatchNotification && matchingAttempts[kind] == 1 { return nil }
            return kind == kIOFirstMatchNotification ? 101 : 102
        }, services: {
            enumerateAttempts += 1
            return enumerateAttempts == 1 ? nil : present
        }, interest: { _, object, _ in
            interestAttempts[object, default: 0] += 1
            if object == 11 && interestAttempts[object] == 1 { return nil }
            return object + 200
        }, release: { released.append($0) }, destroyPort: { _ in destroyed += 1 })
        var monitor: AccessoryMonitor? = AccessoryMonitor(now: { time }, operations: operations)
        monitor?.observeRegistry() // one failed match + failed enumeration
        XCTAssertEqual(matchingAttempts[kIOTerminatedNotification], 1)
        time.addTimeInterval(0.5); monitor?.observeRegistry()
        XCTAssertEqual(enumerateAttempts, 1) // bounded backoff
        time.addTimeInterval(0.5); monitor?.observeRegistry() // match recovers, one interest fails
        XCTAssertEqual(matchingAttempts[kIOFirstMatchNotification], 2)
        XCTAssertEqual(matchingAttempts[kIOTerminatedNotification], 1)
        XCTAssertEqual(interestAttempts[12], 1)
        time.addTimeInterval(2); monitor?.observeRegistry() // stable topology, failed interest recovers
        XCTAssertEqual(interestAttempts[11], 2)
        XCTAssertEqual(interestAttempts[12], 1)
        XCTAssertEqual(matchingAttempts[kIOFirstMatchNotification], 2)
        time.addTimeInterval(60); monitor?.observeRegistry() // success leaves topology clean
        XCTAssertEqual(enumerateAttempts, 3)
        present = [RegistryService(id: 2, object: 12)]
        monitor?.registryChanged(); monitor?.observeRegistry()
        XCTAssertEqual(released.filter { $0 == 211 }.count, 1) // removed interest released once
        XCTAssertEqual(interestAttempts[12], 1)
        monitor = nil
        XCTAssertEqual(released.filter { $0 == 212 }.count, 1)
        XCTAssertEqual(released.filter { $0 == 101 }.count, 1)
        XCTAssertEqual(released.filter { $0 == 102 }.count, 1)
        XCTAssertEqual(released.filter { $0 == 11 }.count, 2) // each enumeration's retained service
        XCTAssertEqual(released.filter { $0 == 12 }.count, 3)
        XCTAssertEqual(destroyed, 1)
    }
    func testPortCreationFailureRetriesOnStableTopologyAndDoesNotDestroyMissingPort() {
        var time = Date(timeIntervalSince1970: 2_000_000_000), attempts = 0, destroyed = 0
        let operations = RegistryOperations(createPort: { attempts += 1; return nil }, matching: { _, _, _ in XCTFail(); return nil },
            services: { XCTFail(); return nil }, interest: { _, _, _ in XCTFail(); return nil },
            release: { _ in XCTFail() }, destroyPort: { _ in destroyed += 1 })
        var monitor: AccessoryMonitor? = AccessoryMonitor(now: { time }, operations: operations)
        monitor?.observeRegistry(); monitor?.observeRegistry()
        XCTAssertEqual(attempts, 1)
        time.addTimeInterval(1); monitor?.observeRegistry()
        XCTAssertEqual(attempts, 2)
        monitor = nil
        XCTAssertEqual(destroyed, 0)
    }
}
