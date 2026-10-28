import XCTest
import AppKit
import UserNotifications
@testable import MagicCharger

@MainActor
final class DeviceControlsIntegrationTests: XCTestCase {
    private final class Target: NSObject, NotificationSettingsReading {
        var deviceSettings = DeviceSettings()
        var lifecycle = AlertLifecycle()
        var collectionMessage: String?
        var commands: [(String, Bool)] = []
        var policyReplies: [(NotificationReadiness) -> Void] = []
        func setDeviceMuted(_ muted: Bool, for id: String) {
            commands.append((id, muted)); deviceSettings.setMuted(muted, for: id); lifecycle.invalidateDevice(id)
        }
        func readNotificationReadiness(_ completion: @escaping (NotificationReadiness) -> Void) { policyReplies.append(completion) }
    }
    private func reading(_ id: String, percent: Int = 79, state: Charging = .charging) -> Reading {
        Reading(id: id, name: "SIMULATED personal name must not appear", symbol: "magicmouse", percent: percent,
            state: state, sampled: Date(), evidence: "SIMULATED")
    }
    private func id(_ digit: String) -> String { "device:" + String(repeating: digit, count: 64) }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func make(_ target: Target) -> ControlsWindow {
        ControlsWindow(target: target, enable: #selector(NSApplication.terminate(_:)), test: #selector(NSApplication.terminate(_:)),
            updates: #selector(NSApplication.terminate(_:)), loginSettings: #selector(NSApplication.terminate(_:)), quit: #selector(NSApplication.terminate(_:)),
            preferences: MenuBarPreferences(), alerts: NotificationPreferences(), onChange: { _ in }, onAlertsChange: { _ in }, onLoginChange: { _ in },
            onDeviceMuteChange: { [weak target] id, muted in target?.setDeviceMuted(muted, for: id) })
    }
    private func update(_ controller: ControlsWindow, _ readings: [Reading], from target: Target) {
        controller.update(readings: readings, notificationStatus: "Notifications enabled.", feedback: "Test submitted to macOS.", diagnostic: "SIMULATED", deviceSettings: target.deviceSettings, collectionMessage: target.collectionMessage)
    }
    private func mute(_ label: String, in controller: ControlsWindow) throws -> NSButton {
        try XCTUnwrap(descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "Mute automatic alerts for " + label
        })
    }

    func testNativeMuteTargetsPrivateIdentityAcrossReorderingAndRetainsOtherChoices() throws {
        let target = Target(), a = reading(id("1")), b = reading(id("2"))
        target.deviceSettings.register([b, a])
        let controller = make(target)
        defer { controller.window?.close() }
        update(controller, [b, a], from: target)
        let first = try mute("Magic Mouse 1", in: controller), second = try mute("Magic Mouse 2", in: controller)
        first.performClick(nil)
        XCTAssertEqual(target.commands.map { $0.0 }, [a.id]); XCTAssertTrue(target.commands[0].1)
        XCTAssertTrue(target.deviceSettings.isMuted(a.id)); XCTAssertFalse(target.deviceSettings.isMuted(b.id))
        update(controller, [reading(b.id, percent: 81), reading(a.id, percent: 80)], from: target)
        XCTAssertTrue(try mute("Magic Mouse 1", in: controller) === first)
        XCTAssertTrue(try mute("Magic Mouse 2", in: controller) === second)
        XCTAssertEqual(first.state, .on); XCTAssertEqual(second.state, .off)
        first.performClick(nil)
        XCTAssertFalse(target.deviceSettings.isMuted(a.id)); XCTAssertFalse(target.commands[1].1)
        let fields = descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSTextField }
        XCTAssertFalse(fields.contains { $0.stringValue.contains("personal name") })
        let global = descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSButton }.filter { AlertKind.allCases.map(\.title).contains($0.title) }
        XCTAssertEqual(global.count, 4); XCTAssertTrue(global.allSatisfy { $0.state == .on })
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testFailureIsDistinctFromEmptySuccessAndClearsOnRecovery() throws {
        let target = Target(), accessory = reading(id("1"))
        target.deviceSettings.register([accessory])
        let controller = make(target)
        defer { controller.window?.close() }
        update(controller, [accessory], from: target)
        target.collectionMessage = CollectionOutcome.failure(.registryUnavailable).message
        update(controller, [], from: target)
        func visibleText() throws -> [String] {
            descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSTextField }
                .filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue)
        }
        XCTAssertTrue(try visibleText().contains(try XCTUnwrap(target.collectionMessage)))
        XCTAssertFalse(try visibleText().contains { $0.hasPrefix("No Magic accessories detected") })
        target.collectionMessage = nil
        update(controller, [], from: target)
        XCTAssertTrue(try visibleText().contains { $0.hasPrefix("No Magic accessories detected") })
        update(controller, [accessory], from: target)
        XCTAssertEqual(try mute("Magic Mouse 1", in: controller).state, .off)
        XCTAssertFalse(try visibleText().contains(CollectionFailure.registryUnavailable.message))
    }

    func testTransientChoiceIsExplainedAndReadinessReplyDoesNotRebuildMuteControl() async throws {
        let target = Target(), accessory = reading("registry:SIMULATED")
        target.deviceSettings.register([accessory])
        let controller = make(target)
        defer { controller.window?.close() }
        update(controller, [accessory], from: target)
        let button = try mute("Magic Mouse 1", in: controller)
        button.performClick(nil)
        XCTAssertTrue(target.deviceSettings.isMuted(accessory.id))
        let fields = descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSTextField }
        XCTAssertTrue(fields.contains { !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == "Temporary choice · may reset after reconnecting or quitting." })
        let reply = try XCTUnwrap(target.policyReplies.first)
        reply(NotificationReadiness(authorization: .provisional, alerts: .disabled, style: .none,
            notificationCenter: .enabled, sound: .disabled, scheduledDelivery: .disabled))
        // Drain the main-queue policy update, without sending any notification.
        let applied = expectation(description: "Policy callback")
        DispatchQueue.main.async { applied.fulfill() }
        await fulfillment(of: [applied], timeout: 1)
        update(controller, [reading(accessory.id, percent: 80)], from: target)
        XCTAssertTrue(try mute("Magic Mouse 1", in: controller) === button)
        XCTAssertEqual(button.state, .on)
        XCTAssertTrue(fields.contains { $0.stringValue.contains("Quiet delivery") })
        XCTAssertTrue(fields.contains { $0.stringValue.contains("Sound: off") })
    }

    func testReadFailureAnnouncementsDoNotClaimDeviceDisconnectsOrRepeat() {
        let accessory = reading(id("1"))
        var messages: [String] = []
        let cards = DeviceCards(announce: { messages.append($0) }, isActive: { _ in true })
        cards.update([accessory])
        cards.update([], collectionMessage: CollectionFailure.registryUnavailable.message)
        cards.update([], collectionMessage: CollectionFailure.registryUnavailable.message)
        XCTAssertEqual(messages, [CollectionFailure.registryUnavailable.message])
        cards.update([accessory])
        XCTAssertEqual(messages.last, "Accessory information is available again.")
        XCTAssertEqual(messages.count, 2)
    }
    func testCombinedLargerTextLayoutIncludesMuteHelpReadinessAndRecovery() async throws {
        let target = Target(), a = reading(id("1")), b = reading("registry:SIMULATED")
        target.deviceSettings.register([a, b])
        let controller = make(target)
        defer { controller.window?.close() }
        update(controller, [a, b], from: target)
        let reply = try XCTUnwrap(target.policyReplies.first)
        reply(NotificationReadiness(authorization: .authorized, alerts: .enabled, style: .banner,
            notificationCenter: .enabled, sound: .disabled, scheduledDelivery: .disabled))
        let applied = expectation(description: "Readiness shown")
        DispatchQueue.main.async { applied.fulfill() }
        await fulfillment(of: [applied], timeout: 1)
        controller.updateLogin(status: .requiresApproval)
        let window = try XCTUnwrap(controller.window), content = try XCTUnwrap(window.contentView)
        let help = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }.first { $0.title == "How It Works & Help" })
        help.performClick(nil)
        for control in descendants(content).compactMap({ $0 as? NSControl }) { control.font = .systemFont(ofSize: 22) }
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: window))
        window.setContentSize(NSSize(width: 360, height: 400))
        update(controller, [b, a], from: target)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentLayoutRect.size, NSSize(width: 360, height: 400))
        let scroll = try XCTUnwrap(descendants(content).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.frame.height, scroll.contentSize.height)
        for control in descendants(document).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
            let frame = control.convert(control.bounds, to: document)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, document.bounds.width + 1, "\(control)")
            if let field = control as? NSTextField, field.cell?.wraps == true {
                XCTAssertLessThanOrEqual(field.cell!.cellSize(forBounds: field.bounds).height, field.bounds.height + 1, "\(field.stringValue)")
            }
        }
        let first = try mute("Magic Mouse 1", in: controller)
        var current: NSView? = first, visited = Set<ObjectIdentifier>(), muteOrder: [String] = []
        while let next = current, visited.insert(ObjectIdentifier(next)).inserted {
            if let button = next as? NSButton, button.title == "Mute automatic alerts", !button.isHiddenOrHasHiddenAncestor {
                muteOrder.append(button.accessibilityLabel() ?? "")
            }
            current = next.nextKeyView
        }
        XCTAssertEqual(muteOrder, ["Mute automatic alerts for Magic Mouse 1", "Mute automatic alerts for Magic Mouse 2"])
        target.collectionMessage = CollectionFailure.propertiesUnavailable.message
        update(controller, [], from: target)
        XCTAssertTrue(descendants(content).compactMap { $0 as? NSTextField }.contains {
            !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == CollectionFailure.propertiesUnavailable.message
        })
        XCTAssertFalse(window.isVisible)
    }

    func testMuteClickFeedsCoreLifecycleWithoutReplayingMutedCrossings() throws {
        let target = Target(), a = reading(id("1"), percent: 77), b = reading(id("2"), percent: 77)
        target.deviceSettings.register([a, b])
        let controller = make(target)
        defer { controller.window?.close() }
        func observe(_ readings: [Reading]) -> [SelectedAlert] {
            target.lifecycle.observe(readings, now: Date(), preferences: NotificationPreferences(),
                allowsDevice: { !target.deviceSettings.isMuted($0) })
        }
        XCTAssertTrue(observe([a, b]).isEmpty)
        update(controller, [a, b], from: target)
        let muteA = try mute("Magic Mouse 1", in: controller)
        muteA.performClick(nil)
        let crossings = [reading(a.id, percent: 81), reading(b.id, percent: 81)]
        let selected = observe(crossings)
        XCTAssertEqual(selected.map { $0.reading.id }, [b.id])
        XCTAssertTrue(target.lifecycle.thresholds.sessions[a.id]?.sent.contains(80) == true)
        let alertB = try XCTUnwrap(selected.first)
        let ticketB = target.lifecycle.ticket(for: alertB.reading, kind: alertB.kind)
        update(controller, crossings, from: target)
        muteA.performClick(nil)
        XCTAssertTrue(target.lifecycle.validates(ticketB, now: Date()), "The other device's held alert must remain valid")
        XCTAssertTrue(observe([reading(a.id, percent: 82), reading(b.id, percent: 82)]).isEmpty)
        update(controller, [reading(a.id, percent: 82), reading(b.id, percent: 82)], from: target)
        XCTAssertEqual(try mute("Magic Mouse 1", in: controller).state, .off)
    }

}
