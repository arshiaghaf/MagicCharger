import XCTest
@testable import MagicCharger
final class MenuBarPreferencesTests: XCTestCase {
    func testIndependentPersistentCombinationsAndInvalidRecovery() throws {
        let suite = "MagicChargerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(MenuBarPreferences.load(defaults), MenuBarPreferences())
        defaults.set(false, forKey: "menu.batteryBar")
        XCTAssertFalse(MenuBarPreferences.load(defaults).statusEmoji)
        for bits in 1...7 {
            let preference = MenuBarPreferences(deviceGlyph: bits & 1 != 0, percentage: bits & 2 != 0, statusEmoji: bits & 4 != 0)
            preference.save(defaults)
            XCTAssertEqual(MenuBarPreferences.load(defaults), preference)
        }
        defaults.set(false, forKey: "menu.deviceGlyph"); defaults.set(false, forKey: "menu.percentage"); defaults.set(false, forKey: "menu.batteryBar")
        XCTAssertEqual(MenuBarPreferences.load(defaults), MenuBarPreferences())
    }
}
