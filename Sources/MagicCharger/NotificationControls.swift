import AppKit
import UserNotifications

struct NotificationReadiness: Equatable {
    let authorization: UNAuthorizationStatus
    let alerts: UNNotificationSetting
    let style: UNAlertStyle
    let notificationCenter: UNNotificationSetting
    let sound: UNNotificationSetting
    let scheduledDelivery: UNNotificationSetting

    init(authorization: UNAuthorizationStatus, alerts: UNNotificationSetting, style: UNAlertStyle,
         notificationCenter: UNNotificationSetting, sound: UNNotificationSetting, scheduledDelivery: UNNotificationSetting) {
        self.authorization = authorization; self.alerts = alerts; self.style = style
        self.notificationCenter = notificationCenter; self.sound = sound; self.scheduledDelivery = scheduledDelivery
    }

    init(_ settings: UNNotificationSettings) {
        self.init(authorization: settings.authorizationStatus, alerts: settings.alertSetting, style: settings.alertStyle,
            notificationCenter: settings.notificationCenterSetting, sound: settings.soundSetting, scheduledDelivery: settings.scheduledDeliverySetting)
    }

    var canSubmit: Bool { authorization == .authorized || authorization == .provisional }
    var needsPermission: Bool { authorization == .notDetermined }
    var summary: String {
        switch authorization {
        case .notDetermined: return "Off · Enable Notifications to receive alerts."
        case .denied: return "Blocked by macOS · Allow notifications in Notification Settings."
        case .provisional: return "Quiet delivery · Provisional permission does not enable banners."
        case .authorized:
            guard alerts == .enabled else { return alerts == .disabled ? "Banners and alerts are off in macOS." : "Banner and alert availability is unknown." }
            switch style {
            case .banner: return "Banners enabled in macOS."
            case .alert: return "Alerts enabled in macOS."
            case .none: return "Banners and alerts are off in macOS."
            @unknown default: return "Banner and alert availability is unknown."
            }
        default: return "Notification permission unavailable · Open Notification Settings."
        }
    }
    var detail: String {
        guard canSubmit else { return "Notifications are optional. You choose which alerts to enable." }
        func state(_ setting: UNNotificationSetting) -> String {
            switch setting { case .enabled: return "on"; case .disabled: return "off"; case .notSupported: return "unavailable"; @unknown default: return "unknown" }
        }
        let scheduled = scheduledDelivery == .enabled ? " Scheduled delivery may delay alerts." : ""
        return "Notification Center: \(state(notificationCenter)) · Sound: \(state(sound)).\(scheduled) Focus and screen sharing may suppress presentation."
    }
}

protocol NotificationSettingsReading: AnyObject {
    func readNotificationReadiness(_ completion: @escaping (NotificationReadiness) -> Void)
}

extension AppDelegate: NotificationSettingsReading {
    func readNotificationReadiness(_ completion: @escaping (NotificationReadiness) -> Void) {
        center.getNotificationSettings { completion(NotificationReadiness($0)) }
    }
}

final class NotificationControls: NSObject {
    let view: NSStackView
    private let notificationLabel = NSTextField(wrappingLabelWithString: "Checking permission…")
    private let enableButton: NSButton
    private let testButton: NSButton
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var alertToggles: [AlertKind: NSButton] = [:]
    private let readSettings: (@escaping (NotificationReadiness) -> Void) -> Void
    private var lastStatus: String?
    private var settingsGeneration = 0
    var onLayoutChange: (() -> Void)?
    private let readinessDetail = NSTextField(wrappingLabelWithString: "")
    private let onAlertsChange: (NotificationPreferences) -> Void

    init(target: AnyObject, enable: Selector, test: Selector, alerts: NotificationPreferences,
         onAlertsChange: @escaping (NotificationPreferences) -> Void,
         readSettings: ((@escaping (NotificationReadiness) -> Void) -> Void)? = nil) {
        self.onAlertsChange = onAlertsChange
        self.readSettings = readSettings ?? { [weak target] completion in
            (target as? NotificationSettingsReading)?.readNotificationReadiness(completion)
        }
        enableButton = NSButton(title: "Enable Notifications…", target: target, action: enable)
        testButton = NSButton(title: "Send Test", target: target, action: test)
        testButton.isEnabled = false
        let notificationTitle = NSTextField(labelWithString: "Notifications"); notificationTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        notificationLabel.font = .systemFont(ofSize: 12); notificationLabel.textColor = .secondaryLabelColor
        readinessDetail.font = .systemFont(ofSize: 12); readinessDetail.textColor = .secondaryLabelColor
        let notificationHeading = NSStackView(views: [notificationTitle, notificationLabel, readinessDetail]); notificationHeading.orientation = .vertical; notificationHeading.alignment = .leading; notificationHeading.spacing = 4
        notificationLabel.widthAnchor.constraint(equalTo: notificationHeading.widthAnchor).isActive = true
        let controls = NSStackView(views: [enableButton, testButton]); controls.spacing = 10
        enableButton.keyEquivalent = "e"; enableButton.keyEquivalentModifierMask = .command
        testButton.keyEquivalent = "t"; testButton.keyEquivalentModifierMask = .command
        enableButton.setAccessibilityHelp("Request notification permission or open macOS notification settings.")
        testButton.setAccessibilityHelp("Send one labeled test notification without changing charging data.")
        let alertOptions = NSStackView(); alertOptions.orientation = .vertical; alertOptions.alignment = .leading; alertOptions.spacing = 8
        for kind in AlertKind.allCases {
            let toggle = NSButton(checkboxWithTitle: kind.title, target: nil, action: nil)
            toggle.state = alerts.allows(kind) ? .on : .off
            alertToggles[kind] = toggle
        }
        let kinds = AlertKind.allCases
        for offset in stride(from: 0, to: kinds.count, by: 2) {
            let row = NSStackView(views: [alertToggles[kinds[offset]]!, alertToggles[kinds[offset + 1]]!])
            row.spacing = 12; row.distribution = .fillEqually
            alertOptions.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: alertOptions.widthAnchor).isActive = true
        }
        feedback.font = .systemFont(ofSize: 11); feedback.textColor = .secondaryLabelColor; feedback.isHidden = true
        view = NSStackView(views: [notificationHeading, alertOptions, controls, feedback]); view.orientation = .vertical; view.alignment = .leading; view.spacing = 10
        super.init()
        for toggle in alertToggles.values { toggle.target = self; toggle.action = #selector(changeAlerts) }
        readinessDetail.widthAnchor.constraint(equalTo: notificationHeading.widthAnchor).isActive = true
        notificationHeading.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        alertOptions.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        feedback.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    func update(status: String, message: String) {
        if status != lastStatus { lastStatus = status; refreshSettings() }
        if message.hasPrefix("Test submitted") { feedback.stringValue = "Test submitted to macOS. Submission does not confirm a banner or sound. Check Notification Center and macOS settings."; feedback.isHidden = false }
        else if message.hasPrefix("Open Notifications") || message.hasPrefix("System Settings") { feedback.stringValue = message; feedback.isHidden = false }
        else if message.hasPrefix("Test not sent") || message.contains("failed") { feedback.stringValue = "Notification wasn’t sent. Open Notification Settings, then try again."; feedback.isHidden = false }
        else { feedback.isHidden = true }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func refreshSettings() {
        settingsGeneration += 1
        let generation = settingsGeneration
        readSettings { [weak self] readiness in
            DispatchQueue.main.async {
                guard let self = self, generation == self.settingsGeneration else { return }
                self.apply(readiness)
            }
        }
    }

    func apply(_ readiness: NotificationReadiness) {
        notificationLabel.stringValue = readiness.summary
        readinessDetail.stringValue = readiness.detail
        enableButton.title = readiness.needsPermission ? "Enable Notifications…" : "Notification Settings…"
        testButton.isEnabled = readiness.canSubmit
        onLayoutChange?()
    }

    @objc private func changeAlerts() {
        onAlertsChange(NotificationPreferences(started: alertToggles[.started]?.state == .on,
            soon: alertToggles[.soon]?.state == .on, target: alertToggles[.target]?.state == .on,
            full: alertToggles[.full]?.state == .on))
    }
}
