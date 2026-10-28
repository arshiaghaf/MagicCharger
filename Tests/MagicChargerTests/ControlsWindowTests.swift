import XCTest
import AppKit
import CoreServices
import ServiceManagement
@testable import MagicCharger
@MainActor
final class ControlsWindowTests: XCTestCase {
    func testLoginOpenEventIsQuietButOrdinaryLaunchAndReopenAreNot() {
        XCTAssertTrue(AppLaunch.isLoginItem(eventID: kAEOpenApplication, launchData: keyAELaunchedAsLogInItem))
        XCTAssertFalse(AppLaunch.isLoginItem(eventID: kAEOpenApplication, launchData: nil))
        XCTAssertFalse(AppLaunch.isLoginItem(eventID: kAEReopenApplication, launchData: keyAELaunchedAsLogInItem))
    }

    func testWindowHeightLeavesRoomForChromeAndScrolling() {
        XCTAssertEqual(ControlsWindow.boundedContentHeight(requested: 800, visible: 600, chrome: 30), 530)
        XCTAssertEqual(ControlsWindow.boundedContentHeight(requested: 500, visible: 800, chrome: 30), 500)
    }

    func testLoginApprovalHasDistinctPresentationState() {
        let pending = LoginItemViewState(.requiresApproval)
        XCTAssertEqual(pending.toggle, .mixed)
        XCTAssertFalse(pending.canToggle)
        XCTAssertTrue(pending.needsApproval)
        let enabled = LoginItemViewState(.enabled)
        XCTAssertEqual(enabled.toggle, .on)
        XCTAssertTrue(enabled.canToggle)
        XCTAssertFalse(enabled.needsApproval)
        XCTAssertEqual(LoginItemViewState(.notRegistered).toggle, .off)
        let notFound = LoginItemViewState(.notFound)
        XCTAssertEqual(notFound.toggle, .off)
        XCTAssertTrue(notFound.canToggle)
        XCTAssertFalse(notFound.needsApproval)
    }

    func testFourAlertLayoutBuildsWithoutPrematureCrossHierarchyConstraints() throws {
        let application = NSApplication.shared
        let controller = ControlsWindow(target: application, enable: #selector(NSApplication.terminate(_:)),
            test: #selector(NSApplication.terminate(_:)), updates: #selector(NSApplication.terminate(_:)),
            loginSettings: #selector(NSApplication.terminate(_:)), quit: #selector(NSApplication.terminate(_:)),
            preferences: MenuBarPreferences(), alerts: NotificationPreferences(),
            onChange: { _ in }, onAlertsChange: { _ in }, onLoginChange: { _ in })
        controller.update(readings: [], notificationStatus: "Notifications enabled.", feedback: "", diagnostic: "SIMULATED")
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentLayoutRect.width, 500)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize.width, 360)
        XCTAssertFalse(window.isVisible)
        window.close()
    }

    func testDeviceCardExposesEachReadingOnceAndKeepsControls() throws {
        let application = NSApplication.shared
        let controller = ControlsWindow(target: application, enable: #selector(NSApplication.terminate(_:)),
            test: #selector(NSApplication.terminate(_:)), updates: #selector(NSApplication.terminate(_:)),
            loginSettings: #selector(NSApplication.terminate(_:)), quit: #selector(NSApplication.terminate(_:)),
            preferences: MenuBarPreferences(), alerts: NotificationPreferences(),
            onChange: { _ in }, onAlertsChange: { _ in }, onLoginChange: { _ in })
        let reading = Reading(id: "SIMULATED", name: "Magic Mouse", symbol: "magicmouse", percent: 79,
            state: .charging, sampled: Date(), evidence: "SIMULATED")
        controller.update(readings: [reading], notificationStatus: "Notifications enabled.", feedback: "", diagnostic: "SIMULATED")
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        func findBox(_ view: NSView) -> NSBox? {
            if let box = view as? NSBox { return box }
            return view.subviews.lazy.compactMap(findBox).first
        }
        let box = try XCTUnwrap(findBox(try XCTUnwrap(window.contentView)))
        XCTAssertEqual(box.accessibilityRole(), .group)
        XCTAssertNil(box.accessibilityLabel())
        let cells = try XCTUnwrap(box.accessibilityChildren() as? [NSCell])
        XCTAssertEqual(cells.compactMap { $0 as? NSImageCell }.count, 1)
        XCTAssertTrue(try XCTUnwrap(cells.compactMap { $0 as? NSImageCell }.first).isAccessibilityHidden())
        XCTAssertEqual(cells.filter { !$0.isAccessibilityHidden() }.compactMap { $0.accessibilityValue() as? String },
            ["Magic Mouse", "Charging", "79%"])
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let all = descendants(try XCTUnwrap(window.contentView))
        XCTAssertEqual(all.compactMap { $0 as? NSTextField }.first { $0.stringValue == "79%" }?.accessibilityLabel(), "79 percent")
        let buttonTitles = Set(all.compactMap { $0 as? NSButton }.map(\.title))
        XCTAssertTrue(buttonTitles.isSuperset(of: ["Send Test", "Quit Magic Charger", "Launch at Login", "Device icon", "Percentage", "Status emoji"]))
        window.close()
    }
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
