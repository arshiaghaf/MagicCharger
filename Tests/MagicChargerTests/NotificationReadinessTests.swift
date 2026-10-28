import XCTest
import AppKit
import UserNotifications
@testable import MagicCharger

final class NotificationReadinessTests: XCTestCase {
    private func policy(_ authorization: UNAuthorizationStatus = .authorized, alerts: UNNotificationSetting = .enabled,
                        style: UNAlertStyle = .banner, center: UNNotificationSetting = .enabled,
                        sound: UNNotificationSetting = .enabled, scheduled: UNNotificationSetting = .disabled) -> NotificationReadiness {
        NotificationReadiness(authorization: authorization, alerts: alerts, style: style,
            notificationCenter: center, sound: sound, scheduledDelivery: scheduled)
    }

    func testQuietAndBannerOffDoNotClaimBannersAreReady() {
        XCTAssertEqual(policy(.provisional).summary, "Quiet delivery · Provisional permission does not enable banners.")
        XCTAssertTrue(policy(.provisional).canSubmit)
        XCTAssertEqual(policy(alerts: .disabled).summary, "Banners and alerts are off in macOS.")
        XCTAssertEqual(policy(style: .none).summary, "Banners and alerts are off in macOS.")
        XCTAssertEqual(policy(alerts: .notSupported).summary, "Banner and alert availability is unknown.")
        XCTAssertEqual(policy(style: .alert).summary, "Alerts enabled in macOS.")
    }

    func testSoundAndCenterAreIndependentAndFocusIsNeverPromisedAway() {
        let readiness = policy(center: .disabled, sound: .disabled, scheduled: .enabled)
        XCTAssertEqual(readiness.summary, "Banners enabled in macOS.")
        XCTAssertTrue(readiness.detail.contains("Notification Center: off · Sound: off"))
        XCTAssertTrue(readiness.detail.contains("Scheduled delivery may delay alerts"))
        XCTAssertTrue(readiness.detail.contains("Focus and screen sharing may suppress presentation"))
    }

    func testNoPermissionDisablesSubmissionAndSeparatesFirstRequest() {
        XCTAssertFalse(policy(.denied).canSubmit)
        XCTAssertFalse(policy(.denied).needsPermission)
        XCTAssertFalse(policy(.notDetermined).canSubmit)
        XCTAssertTrue(policy(.notDetermined).needsPermission)
    }

    @MainActor func testControlsKeepSubmissionSeparateFromVisibleDelivery() {
        let controls = NotificationControls(target: NSApplication.shared, enable: #selector(NSApplication.terminate(_:)),
            test: #selector(NSApplication.terminate(_:)), alerts: NotificationPreferences(), onAlertsChange: { _ in }, readSettings: { _ in })
        controls.apply(policy(.provisional, sound: .disabled))
        controls.update(status: "Notifications enabled.", message: "Test submitted to macOS.")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = descendants(controls.view)
        XCTAssertTrue(all.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Submission does not confirm a banner or sound") })
        XCTAssertEqual(all.compactMap { $0 as? NSButton }.first { $0.title == "Send Test" }?.isEnabled, true)
        controls.apply(policy(.denied))
        XCTAssertEqual(all.compactMap { $0 as? NSButton }.first { $0.title == "Send Test" }?.isEnabled, false)
    }
    @MainActor func testPolicyRefreshIsNotPolledAndOlderRepliesCannotOverwriteNewerPolicy() async {
        var replies: [(NotificationReadiness) -> Void] = []
        let controls = NotificationControls(target: NSApplication.shared, enable: #selector(NSApplication.terminate(_:)),
            test: #selector(NSApplication.terminate(_:)), alerts: NotificationPreferences(), onAlertsChange: { _ in },
            readSettings: { replies.append($0) })
        controls.update(status: "Notifications enabled.", message: "")
        controls.update(status: "Notifications enabled.", message: "")
        XCTAssertEqual(replies.count, 1, "Repeated telemetry renders must not poll notification settings")
        controls.refreshSettings()
        XCTAssertEqual(replies.count, 2)
        let applied = expectation(description: "Newest policy applied")
        controls.onLayoutChange = { applied.fulfill() }
        replies[1](policy(.denied))
        replies[0](policy())
        await fulfillment(of: [applied], timeout: 1)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let buttons = descendants(controls.view).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.first { $0.title == "Send Test" }?.isEnabled, false)
    }

}
