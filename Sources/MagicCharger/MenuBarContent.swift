import Foundation

struct MenuBarContent {
    let title: String
    let status: String
    let accessibilityLabel: String

    init?(_ reading: Reading, preferences: MenuBarPreferences) {
        guard reading.active else { return nil }
        // Full takes precedence only for an already eligible charging reading.
        // A reported 100% never makes an idle, unknown or stale reading visible.
        let full = reading.percent == 100
        status = full ? "Fully charged" : "Charging"
        var components: [String] = []
        if preferences.percentage { components.append(reading.percent.map { "\($0)%" } ?? "?") }
        if preferences.statusEmoji { components.append(full ? "🔋" : "⚡️") }
        title = components.joined(separator: " ")
        accessibilityLabel = "\(reading.name), \(status.lowercased()), \(reading.percent.map { "\($0) percent" } ?? "battery level unknown")"
    }
}
