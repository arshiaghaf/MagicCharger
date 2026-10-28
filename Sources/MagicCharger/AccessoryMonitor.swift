import Foundation
import IOKit

enum CollectionFailure: String, Error {
    case registryUnavailable, propertiesUnavailable
    var message: String {
        switch self {
        case .registryUnavailable: return "Accessory information could not be read. Monitoring will retry automatically."
        case .propertiesUnavailable: return "Some accessory information is unavailable. Monitoring will retry automatically."
        }
    }
}
enum CollectionOutcome {
    case success([Reading])
    case failure(CollectionFailure)
    var readings: [Reading] { if case .success(let readings) = self { return readings }; return [] }
    var message: String? { if case .failure(let failure) = self { return failure.message }; return nil }
}

// One registry dictionary is copied per service. Decode only these selected keys;
// never retain or log the dictionary, personal product names or raw addresses.
enum AccessoryProperties {
    static func supports(product: String?, vendor: Int?) -> Bool {
        guard let product = product, product.localizedCaseInsensitiveContains("Magic"),
              vendor == 76 || vendor == 1452 else { return false }
        return product.localizedCaseInsensitiveContains("Keyboard") || product.localizedCaseInsensitiveContains("Mouse")
    }
    static func reading(_ properties: [String: Any], entryID: UInt64, identityKey: Data,
                        sampled: Date, os: OperatingSystemVersion) -> Reading? {
        guard let product = properties["Product"] as? String, let vendor = properties["VendorID"] as? Int,
              supports(product: product, vendor: vendor) else { return nil }
        let keyboard = product.localizedCaseInsensitiveContains("Keyboard")
        let productID = properties["ProductID"] as? Int ?? 0
        let stableID = DeviceIdentity.stable(address: properties["DeviceAddress"] as? String, productID: productID, key: identityKey)
        let id = stableID ?? "registry:\(productID):\(entryID)"
        let percent = (properties["BatteryPercent"] as? Int).flatMap { (0...100).contains($0) ? $0 : nil }
        func boolean(_ key: String) -> Bool? {
            guard let number = properties[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        let first = boolean("BatteryCharging"), second = boolean("IsCharging")
        let flags = properties["BatteryStatusFlags"] as? Int
        let transport = properties["Transport"] as? String
        let state = ChargingDecoder.decode(vendor: vendor, product: productID, transport: transport,
            os: os, percent: percent, flags: flags, batteryCharging: first, isCharging: second)
        let fullEvidence = ChargingDecoder.fullChargeEvidence(vendor: vendor, product: productID, transport: transport,
            os: os, percent: percent, flags: flags, batteryCharging: first, isCharging: second)
        return Reading(id: id, name: keyboard ? "Magic Keyboard" : "Magic Mouse", symbol: keyboard ? "keyboard" : "magicmouse",
            percent: percent, state: state, sampled: sampled,
            evidence: "Transport: \(transport ?? "unknown"); flags: \(flags.map(String.init) ?? "unknown"); charging: \(state.rawValue). Driver freshness unavailable. Identity: \(stableID == nil ? "registry only" : "private stable digest").",
            fullChargeEvidence: fullEvidence)
    }
}

func snapshot(identityKey: Data) -> CollectionOutcome {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return .failure(.registryUnavailable) }
    defer { IOObjectRelease(iterator) }
    var result: [Reading] = []
    while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        defer { IOObjectRelease(service) }
        // Metadata preflight avoids copying an unsupported service's table.
        // The copied table revalidates this gate; charging values are never mixed
        // with these separate metadata queries.
        let product = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        let vendor = IORegistryEntryCreateCFProperty(service, "VendorID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        guard AccessoryProperties.supports(product: product, vendor: vendor) else { continue }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return .failure(.propertiesUnavailable) }
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return .failure(.propertiesUnavailable) }
        if let reading = AccessoryProperties.reading(dictionary, entryID: entryID, identityKey: identityKey,
                sampled: Date(), os: ProcessInfo.processInfo.operatingSystemVersion) { result.append(reading) }
    }
    return .success(reconciled(result))
}

struct RegistryService {
    let id: UInt64
    let object: io_service_t
}

// Keep native handles behind injectable operations so fault paths can be tested
// without creating devices, changing hardware or registering real callbacks.
struct RegistryOperations {
    var createPort: () -> IONotificationPortRef?
    var matching: (IONotificationPortRef, String, UnsafeMutableRawPointer) -> io_iterator_t?
    var services: () -> [RegistryService]?
    var interest: (IONotificationPortRef, io_service_t, UnsafeMutableRawPointer) -> io_object_t?
    var release: (io_object_t) -> Void
    var destroyPort: (IONotificationPortRef) -> Void

    static let live = RegistryOperations(createPort: {
        let port = IONotificationPortCreate(kIOMainPortDefault)
        if let port = port { IONotificationPortSetDispatchQueue(port, .main) }
        return port
    }, matching: { port, kind, context in
        var iterator: io_iterator_t = 0
        let code = IOServiceAddMatchingNotification(port, kind, IOServiceMatching("AppleDeviceManagementHIDEventService"), { context, iterator in
            while true { let object = IOIteratorNext(iterator); if object == 0 { break }; IOObjectRelease(object) }
            guard let context = context else { return }
            Unmanaged<AccessoryMonitor>.fromOpaque(context).takeUnretainedValue().registryChanged()
        }, context, &iterator)
        guard code == KERN_SUCCESS else { if iterator != 0 { IOObjectRelease(iterator) }; return nil }
        while true { let object = IOIteratorNext(iterator); if object == 0 { break }; IOObjectRelease(object) }
        return iterator
    }, services: {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var result: [RegistryService] = []
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else {
                IOObjectRelease(service); result.forEach { IOObjectRelease($0.object) }; return nil
            }
            result.append(RegistryService(id: id, object: service))
        }
        return result
    }, interest: { port, service, context in
        var interest: io_object_t = 0
        let code = IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { context, _, _, _ in
            guard let context = context else { return }
            Unmanaged<AccessoryMonitor>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, context, &interest)
        guard code == KERN_SUCCESS else { if interest != 0 { IOObjectRelease(interest) }; return nil }
        return interest
    }, release: { IOObjectRelease($0) }, destroyPort: { IONotificationPortDestroy($0) })
}

final class AccessoryMonitor {
    var onChange: (() -> Void)?
    private var matchingIterators: [String: io_iterator_t] = [:]
    private var port: IONotificationPortRef?
    private var interests: [UInt64: io_object_t] = [:]
    private var recovery = ObservationRecovery()
    private let now: () -> Date
    private let operations: RegistryOperations
    init(now: @escaping () -> Date = Date.init, operations: RegistryOperations = .live) {
        self.now = now; self.operations = operations
    }
    func registryChanged() { recovery.invalidate(); onChange?() }
    func observeRegistry() {
        let time = now()
        guard recovery.shouldAttempt(at: time) else { return }
        var succeeded = true
        if port == nil { port = operations.createPort() }
        guard let port = port else { recovery.finish(success: false, now: time); return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] where matchingIterators[kind] == nil {
            if let iterator = operations.matching(port, kind, context) { matchingIterators[kind] = iterator }
            else { succeeded = false }
        }
        guard let services = operations.services() else { recovery.finish(success: false, now: time); return }
        defer { services.forEach { operations.release($0.object) } }
        var present = Set<UInt64>()
        for service in services {
            present.insert(service.id)
            guard interests[service.id] == nil else { continue }
            if let interest = operations.interest(port, service.object, context) { interests[service.id] = interest }
            else { succeeded = false }
        }
        for id in Array(interests.keys) where !present.contains(id) { operations.release(interests.removeValue(forKey: id)!) }
        recovery.finish(success: succeeded, now: time)
    }
    deinit {
        interests.values.forEach(operations.release)
        matchingIterators.values.forEach(operations.release)
        if let port = port { operations.destroyPort(port) }
    }
}
