import AppKit

final class NotificationControls: NSObject {
    let view: NSStackView
    private let notificationLabel = NSTextField(wrappingLabelWithString: "Checking permission…")
    private let enableButton: NSButton
    private let testButton: NSButton
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var alertToggles: [AlertKind: NSButton] = [:]
    private let onAlertsChange: (NotificationPreferences) -> Void

    init(target: AnyObject, enable: Selector, test: Selector, alerts: NotificationPreferences,
         onAlertsChange: @escaping (NotificationPreferences) -> Void) {
        self.onAlertsChange = onAlertsChange
        enableButton = NSButton(title: "Enable Notifications…", target: target, action: enable)
        testButton = NSButton(title: "Send Test", target: target, action: test)
        let notificationTitle = NSTextField(labelWithString: "Notifications"); notificationTitle.font = .preferredFont(forTextStyle: .headline)
        notificationLabel.font = .preferredFont(forTextStyle: .body); notificationLabel.textColor = .secondaryLabelColor
        let notificationHeading = NSStackView(views: [notificationTitle, notificationLabel]); notificationHeading.orientation = .vertical; notificationHeading.alignment = .leading; notificationHeading.spacing = 4
        notificationLabel.widthAnchor.constraint(equalTo: notificationHeading.widthAnchor).isActive = true
        let controls = NSStackView(views: [enableButton, testButton]); controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 8
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
        for kind in AlertKind.allCases { alertOptions.addArrangedSubview(alertToggles[kind]!) }
        feedback.font = .preferredFont(forTextStyle: .body); feedback.textColor = .secondaryLabelColor; feedback.isHidden = true
        view = NSStackView(views: [notificationHeading, alertOptions, controls, feedback]); view.orientation = .vertical; view.alignment = .leading; view.spacing = 10
        super.init()
        for toggle in alertToggles.values { toggle.target = self; toggle.action = #selector(changeAlerts) }
        notificationHeading.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        alertOptions.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        feedback.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    func update(status: String, message: String) {
        let enabled = status == "Notifications enabled."
        notificationLabel.stringValue = enabled ? "Allowed by macOS" : (status.contains("denied") ? "Blocked by macOS · Open Notification Settings to allow alerts" : (status.contains("not requested") ? "Off · Enable Notifications to receive alerts" : "Permission unavailable · Open Notification Settings"))
        enableButton.title = status.contains("not requested") ? "Enable Notifications…" : "Notification Settings…"
        enableButton.isHidden = false
        testButton.isEnabled = enabled
        if message.hasPrefix("Test submitted") { feedback.stringValue = "Test sent to macOS. Check Notification Center if needed."; feedback.isHidden = false }
        else if message.hasPrefix("Open Notifications") || message.hasPrefix("System Settings") { feedback.stringValue = message; feedback.isHidden = false }
        else if message.hasPrefix("Test not sent") || message.contains("failed") { feedback.stringValue = "Notification wasn’t sent. Open Notification Settings, then try again."; feedback.isHidden = false }
        else { feedback.isHidden = true }
    }

    @objc private func changeAlerts() {
        onAlertsChange(NotificationPreferences(started: alertToggles[.started]?.state == .on,
            soon: alertToggles[.soon]?.state == .on, target: alertToggles[.target]?.state == .on,
            full: alertToggles[.full]?.state == .on))
    }
}
