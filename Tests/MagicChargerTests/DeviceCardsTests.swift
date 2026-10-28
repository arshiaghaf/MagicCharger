import XCTest
import AppKit
@testable import MagicCharger

@MainActor
final class DeviceCardsTests: XCTestCase {
    private func reading(_ id: String, name: String = "Magic Mouse", percent: Int? = 79, state: Charging = .charging) -> Reading {
        Reading(id: id, name: name, symbol: "magicmouse", percent: percent, state: state, sampled: Date(), evidence: "SIMULATED")
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func boxes(_ cards: DeviceCards) -> [NSBox] { cards.view.arrangedSubviews.compactMap { $0 as? NSBox } }

    func testPercentageAndStateUpdatesPreserveCardAndAccessibleElementsByIdentity() throws {
        let cards = DeviceCards(announce: { _ in })
        cards.update([reading("SIMULATED-A")])
        let card = try XCTUnwrap(boxes(cards).first)
        let labels = descendants(card).compactMap { $0 as? NSTextField }
        cards.update([reading("SIMULATED-A", percent: 80, state: .idle)])
        XCTAssertTrue(boxes(cards).first === card)
        let updated = descendants(card).compactMap { $0 as? NSTextField }
        XCTAssertEqual(labels.map(ObjectIdentifier.init), updated.map(ObjectIdentifier.init))
        XCTAssertEqual(updated.map(\.stringValue), ["Magic Mouse", "Not charging", "80%"])
        XCTAssertEqual(updated.last?.accessibilityLabel(), "80 percent")
    }

    func testSameNameDevicesKeepTheirCardsAndOrderAcrossReorderedSamplesAndLabelChanges() throws {
        let cards = DeviceCards(announce: { _ in })
        cards.update([reading("SIMULATED-B"), reading("SIMULATED-A")])
        let original = boxes(cards)
        XCTAssertEqual(original.count, 2)
        cards.update([reading("SIMULATED-A", name: "Z label", percent: 81), reading("SIMULATED-B", name: "A label", percent: 42)])
        XCTAssertEqual(boxes(cards).map(ObjectIdentifier.init), original.map(ObjectIdentifier.init))
        XCTAssertEqual(original.map { descendants($0).compactMap { $0 as? NSTextField }.last?.stringValue }, ["81%", "42%"])
        cards.update([reading("SIMULATED-B", percent: 43)])
        XCTAssertEqual(boxes(cards).count, 1)
        XCTAssertTrue(boxes(cards).first === original[1])
    }

    func testAnnouncementsAreOnlyMeaningfulChangesInActiveControls() {
        var active = true
        var announcements: [String] = []
        let cards = DeviceCards(announce: { announcements.append($0) }, isActive: { _ in active })
        cards.update([reading("SIMULATED-A")])
        cards.update([reading("SIMULATED-A", percent: 80)])
        XCTAssertTrue(announcements.isEmpty, "Initial baselines and percentages must stay quiet")
        cards.update([reading("SIMULATED-A", percent: 80, state: .idle)])
        cards.update([reading("SIMULATED-A", percent: 80, state: .idle)])
        XCTAssertEqual(announcements, ["Magic Mouse: Not charging."])
        active = false
        cards.update([reading("SIMULATED-A", percent: 80)])
        XCTAssertEqual(announcements.count, 1)
        active = true
        cards.update([])
        XCTAssertEqual(announcements.last, "Magic Mouse no longer detected.")
        cards.update([])
        XCTAssertEqual(announcements.count, 2)
    }

    func testDuplicateConflictsRemainOneUnknownCard() throws {
        let cards = DeviceCards(announce: { _ in })
        cards.update([reading("SIMULATED-A", percent: 79), reading("SIMULATED-A", percent: 80)])
        XCTAssertEqual(boxes(cards).count, 1)
        let labels = descendants(try XCTUnwrap(boxes(cards).first)).compactMap { $0 as? NSTextField }
        XCTAssertEqual(labels.map(\.stringValue), ["Magic Mouse", "Charging state unknown", "—"])
    }
}
