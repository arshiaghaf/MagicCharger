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
    static func reading(_ properties: [String: Any], entryID: UInt64, identityKey: Data,
                        sampled: Date, os: OperatingSystemVersion) -> Reading? {
        guard let product = properties["Product"] as? String, product.localizedCaseInsensitiveContains("Magic"),
              let vendor = properties["VendorID"] as? Int, vendor == 76 || vendor == 1452 else { return nil }
        let keyboard = product.localizedCaseInsensitiveContains("Keyboard")
        guard keyboard || product.localizedCaseInsensitiveContains("Mouse") else { return nil }
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

final class AccessoryMonitor {
    var onChange: (() -> Void)?
    private var matchingIterators: [String: io_iterator_t] = [:]
    private var port: IONotificationPortRef?
    private var interests: [UInt64: io_object_t] = [:]
    private var recovery = ObservationRecovery()
    private let now: () -> Date
    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func observeRegistry() {
        let time = now()
        guard recovery.shouldAttempt(at: time) else { return }
        var succeeded = true
        if port == nil {
            port = IONotificationPortCreate(kIOMainPortDefault)
            if let port = port { IONotificationPortSetDispatchQueue(port, .main) }
        }
        guard let port = port else { recovery.finish(success: false, now: time); return }
        for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] where matchingIterators[kind] == nil {
            var iterator: io_iterator_t = 0
            let code = IOServiceAddMatchingNotification(port, kind, IOServiceMatching("AppleDeviceManagementHIDEventService"), { context, iterator in
                while true { let object = IOIteratorNext(iterator); if object == 0 { break }; IOObjectRelease(object) }
                guard let context = context else { return }
                let owner = Unmanaged<AccessoryMonitor>.fromOpaque(context).takeUnretainedValue()
                owner.recovery.invalidate(); owner.onChange?()
            }, Unmanaged.passUnretained(self).toOpaque(), &iterator)
            if code == KERN_SUCCESS {
                matchingIterators[kind] = iterator
                while true { let object = IOIteratorNext(iterator); if object == 0 { break }; IOObjectRelease(object) }
            } else { if iterator != 0 { IOObjectRelease(iterator) }; succeeded = false }
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            recovery.finish(success: false, now: time); return
        }
        defer { IOObjectRelease(iterator) }
        var present = Set<UInt64>()
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { succeeded = false; continue }
            present.insert(id)
            guard interests[id] == nil else { continue }
            var interest: io_object_t = 0
            let code = IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { context, _, _, _ in
                guard let context = context else { return }
                let owner = Unmanaged<AccessoryMonitor>.fromOpaque(context).takeUnretainedValue()
                owner.onChange?()
            }, Unmanaged.passUnretained(self).toOpaque(), &interest)
            if code == KERN_SUCCESS { interests[id] = interest }
            else { if interest != 0 { IOObjectRelease(interest) }; succeeded = false }
        }
        for id in Array(interests.keys) where !present.contains(id) { IOObjectRelease(interests.removeValue(forKey: id)!) }
        recovery.finish(success: succeeded, now: time)
    }
    deinit {
        interests.values.forEach { IOObjectRelease($0) }
        matchingIterators.values.forEach { IOObjectRelease($0) }
        if let port = port { IONotificationPortDestroy(port) }
    }
}
