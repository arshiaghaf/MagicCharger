import Foundation

struct MenuBarPreferences: Equatable {
    var deviceGlyph = true
    var percentage = true
    var statusEmoji = true
    var isValid: Bool { deviceGlyph || percentage || statusEmoji }
    static func load(_ defaults: UserDefaults) -> Self {
        var value = Self()
        if defaults.object(forKey: "menu.deviceGlyph") != nil { value.deviceGlyph = defaults.bool(forKey: "menu.deviceGlyph") }
        if defaults.object(forKey: "menu.percentage") != nil { value.percentage = defaults.bool(forKey: "menu.percentage") }
        // Preserve the existing third display choice across the artwork change.
        if defaults.object(forKey: "menu.batteryBar") != nil { value.statusEmoji = defaults.bool(forKey: "menu.batteryBar") }
        return value.isValid ? value : Self()
    }
    func save(_ defaults: UserDefaults) {
        guard isValid else { return }
        defaults.set(deviceGlyph, forKey: "menu.deviceGlyph")
        defaults.set(percentage, forKey: "menu.percentage")
        defaults.set(statusEmoji, forKey: "menu.batteryBar")
    }
}
