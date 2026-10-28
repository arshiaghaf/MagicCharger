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
            onChange: { _ in }, onAlertsChange: { _ in }, onLoginChange: { _ in }, notificationSettingsReader: { _ in })
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
            onChange: { _ in }, onAlertsChange: { _ in }, onLoginChange: { _ in }, notificationSettingsReader: { _ in })
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
    func testHelpIsOptionalInlineAndDoesNotOpenAWindowOrRequestPermission() throws {
        let help = HelpControls()
        let button = try XCTUnwrap(help.view.arrangedSubviews.first as? NSButton)
        let explanation = try XCTUnwrap(help.view.arrangedSubviews.last as? NSTextField)
        var layouts = 0
        help.onLayoutChange = { layouts += 1 }
        XCTAssertTrue(explanation.isHidden)
        XCTAssertNil(help.view.window)
        button.performClick(nil)
        XCTAssertFalse(explanation.isHidden)
        XCTAssertTrue(explanation.stringValue.contains("Reopen Magic Charger from Finder or Spotlight"))
        XCTAssertTrue(explanation.stringValue.contains("cannot stop charging automatically"))
        button.performClick(nil)
        XCTAssertTrue(explanation.isHidden)
        XCTAssertEqual(layouts, 2)
        XCTAssertNil(help.view.window)
    }

}
