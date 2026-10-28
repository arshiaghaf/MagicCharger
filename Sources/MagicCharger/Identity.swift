import Foundation
import CryptoKit

// Only a supported accessory's address is read. Persist a locally keyed digest,
// never the address; the key prevents matching hashes between installations.
enum DeviceIdentity {
    static func isPersistent(_ id: String) -> Bool {
        let digest = id.dropFirst("device:".count)
        return id.hasPrefix("device:") && digest.count == 64 && digest.allSatisfy { $0.isHexDigit }
    }
    static func stable(address: String?, productID: Int, key: Data) -> String? {
        guard let address = address else { return nil }
        let normalized = address.lowercased().filter { $0 != ":" && $0 != "-" }
        guard normalized.count == 12, normalized.allSatisfy({ $0.isHexDigit }) else { return nil }
        let digest = HMAC<SHA256>.authenticationCode(for: Data("\(productID):\(normalized)".utf8), using: SymmetricKey(data: key))
        return "device:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
