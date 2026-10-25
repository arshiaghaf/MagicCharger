import XCTest
@testable import MagicCharger

final class MenuBarContentTests: XCTestCase {
    private func reading(percent: Int? = 79, state: Charging = .charging,
                         sampled: Date = Date(), full: Bool = false, mouse: Bool = false) -> Reading {
        Reading(id: "SIMULATED", name: mouse ? "Magic Mouse" : "Magic Keyboard",
                symbol: mouse ? "magicmouse" : "keyboard", percent: percent, state: state,
                sampled: sampled, evidence: "SIMULATED", fullChargeEvidence: full)
    }

    func testChargingToFullAndBackUpdatesEmojiAndAccessibleState() throws {
        for mouse in [false, true] {
            let name = mouse ? "Magic Mouse" : "Magic Keyboard"
            for (percent, title, status) in [(99, "99% ⚡️", "Charging"), (100, "100% 🔋", "Fully charged"), (79, "79% ⚡️", "Charging")] {
                let content = try XCTUnwrap(MenuBarContent(reading(percent: percent, mouse: mouse), preferences: .init()))
                XCTAssertEqual(content.title, title)
                XCTAssertEqual(content.status, status)
                XCTAssertEqual(content.accessibilityLabel, "\(name), \(status.lowercased()), \(percent) percent")
            }
        }
        let unknownLevel = try XCTUnwrap(MenuBarContent(reading(percent: nil), preferences: .init()))
        XCTAssertEqual(unknownLevel.title, "? ⚡️")
        XCTAssertEqual(unknownLevel.accessibilityLabel, "Magic Keyboard, charging, battery level unknown")
    }

    func testFullPercentageDoesNotMakeIdleUnknownOrStaleReadingsVisible() {
        for state in [Charging.idle, .unknown] {
            for percent in [nil, 79, 100] as [Int?] {
                for full in [false, true] {
                    XCTAssertNil(MenuBarContent(reading(percent: percent, state: state, full: full), preferences: .init()))
                }
            }
        }
        XCTAssertNil(MenuBarContent(reading(percent: 100, sampled: Date().addingTimeInterval(-91), full: true), preferences: .init()))
    }

    func testIndependentDisplayChoicesPreserveTextOrderAndSpacing() throws {
        for bits in 1...7 {
            let preferences = MenuBarPreferences(deviceGlyph: bits & 1 != 0, percentage: bits & 2 != 0, statusEmoji: bits & 4 != 0)
            let content = try XCTUnwrap(MenuBarContent(reading(), preferences: preferences))
            let expected = [preferences.percentage ? "79%" : nil, preferences.statusEmoji ? "⚡️" : nil].compactMap { $0 }.joined(separator: " ")
            XCTAssertEqual(content.title, expected)
            XCTAssertEqual(content.title, content.title.trimmingCharacters(in: .whitespaces))
            XCTAssertEqual(content.accessibilityLabel, "Magic Keyboard, charging, 79 percent")
        }
    }
}
