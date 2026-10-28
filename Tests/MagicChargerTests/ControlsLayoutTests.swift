import XCTest
import AppKit
import ServiceManagement
@testable import MagicCharger

@MainActor
final class ControlsLayoutTests: XCTestCase {
    func testNarrowWindowWithLargerTextKeepsContentInsideScrollableDocumentAndPreservesUserSize() throws {
        let application = NSApplication.shared
        let controller = ControlsWindow(target: application, enable: #selector(NSApplication.terminate(_:)),
            test: #selector(NSApplication.terminate(_:)), updates: #selector(NSApplication.terminate(_:)),
            loginSettings: #selector(NSApplication.terminate(_:)), quit: #selector(NSApplication.terminate(_:)),
            preferences: MenuBarPreferences(), alerts: NotificationPreferences(),
            onChange: { _ in }, onAlertsChange: { _ in }, onLoginChange: { _ in })
        let reading = Reading(id: "SIMULATED-LAYOUT", name: "Magic Keyboard with an intentionally long display label", symbol: "keyboard",
            percent: 100, state: .unknown, sampled: Date(), evidence: "SIMULATED", fullChargeEvidence: true)
        controller.update(readings: [reading], notificationStatus: "Notifications enabled.", feedback: "Test submitted to macOS.", diagnostic: "SIMULATED")
        controller.updateLogin(status: .requiresApproval)
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for control in descendants(content).compactMap({ $0 as? NSControl }) { control.font = .systemFont(ofSize: 22) }
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: window))
        window.setContentSize(NSSize(width: 360, height: 400))
        controller.update(readings: [reading], notificationStatus: "Notifications enabled.", feedback: "Test submitted to macOS.", diagnostic: "SIMULATED")
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentLayoutRect.width, 360)
        XCTAssertEqual(window.contentLayoutRect.height, 400)
        let scroll = try XCTUnwrap(descendants(content).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.frame.height, scroll.contentSize.height)
        for control in descendants(document).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
            let frame = control.convert(control.bounds, to: document)
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(control)")
            XCTAssertLessThanOrEqual(frame.maxX, document.bounds.width + 1, "\(control)")
            if let field = control as? NSTextField, field.cell?.wraps == true {
                XCTAssertLessThanOrEqual(field.cell!.cellSize(forBounds: field.bounds).height, field.bounds.height + 1, "\(field.stringValue)")
            }
        }
        let buttons = descendants(document).compactMap { $0 as? NSButton }
        let first = try XCTUnwrap(buttons.first { $0.title == "Device icon" })
        var keyView: NSView? = first
        var keyTitles: [String] = []
        var visited = Set<ObjectIdentifier>()
        while let current = keyView, visited.insert(ObjectIdentifier(current)).inserted {
            if let button = current as? NSButton, !button.isHiddenOrHasHiddenAncestor { keyTitles.append(button.title) }
            keyView = current.nextKeyView
        }
        XCTAssertEqual(Array(keyTitles.prefix(7)), ["Device icon", "Percentage", "Status emoji"] + AlertKind.allCases.map(\.title))
        XCTAssertFalse(window.isVisible)
        window.close()
    }

}
