import AppKit
import ServiceManagement

struct LoginItemViewState {
    let toggle: NSControl.StateValue
    let canToggle: Bool
    let needsApproval: Bool

    init(_ status: SMAppService.Status) {
        toggle = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        canToggle = status == .notRegistered || status == .notFound || status == .enabled
        needsApproval = status == .requiresApproval
    }
}

final class GeneralControls: NSObject {
    let view: NSStackView
    private let loginToggle = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let loginHint = NSTextField(wrappingLabelWithString: "")
    private let loginSettingsButton: NSButton
    private let cancelLoginButton = NSButton(title: "Cancel Login Request", target: nil, action: nil)
    private let updateFeedback = NSTextField(wrappingLabelWithString: "")
    private let onLoginChange: (Bool) -> Void

    init(target: AnyObject, updates: Selector, loginSettings: Selector,
         onLoginChange: @escaping (Bool) -> Void) {
        self.onLoginChange = onLoginChange
        loginSettingsButton = NSButton(title: "Open Login Items…", target: target, action: loginSettings)
        let generalTitle = NSTextField(labelWithString: "General"); generalTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        loginToggle.allowsMixedState = true
        loginToggle.setAccessibilityHelp("Start Magic Charger automatically when you sign in. Off until you enable it.")
        loginHint.font = .systemFont(ofSize: 11); loginHint.textColor = .secondaryLabelColor
        loginSettingsButton.bezelStyle = .inline; loginSettingsButton.isHidden = true
        loginSettingsButton.setAccessibilityHelp("Open macOS Login Items settings to approve Magic Charger.")
        cancelLoginButton.bezelStyle = .inline; cancelLoginButton.isHidden = true
        cancelLoginButton.setAccessibilityHelp("Remove the pending login item registration.")
        let updatesButton = NSButton(title: "View Releases…", target: target, action: updates)
        updatesButton.keyEquivalent = "u"; updatesButton.keyEquivalentModifierMask = .command
        updatesButton.setAccessibilityHelp("Open the official Magic Charger releases page in your browser.")
        updateFeedback.font = .systemFont(ofSize: 11); updateFeedback.textColor = .secondaryLabelColor; updateFeedback.isHidden = true
        view = NSStackView(views: [generalTitle, loginToggle, loginHint, loginSettingsButton, cancelLoginButton, updatesButton, updateFeedback]); view.orientation = .vertical; view.alignment = .leading; view.spacing = 7
        super.init()
        loginToggle.target = self; loginToggle.action = #selector(changeLogin(_:))
        cancelLoginButton.target = self; cancelLoginButton.action = #selector(cancelLogin)
        loginHint.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        updateFeedback.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    func updateLogin(status: SMAppService.Status, feedback: String = "") {
        let viewState = LoginItemViewState(status)
        loginToggle.state = viewState.toggle
        loginToggle.isEnabled = viewState.canToggle
        loginSettingsButton.isHidden = !viewState.needsApproval
        cancelLoginButton.isHidden = !viewState.needsApproval
        switch status {
        case .enabled: loginHint.stringValue = "Starts automatically when you sign in."
        case .notRegistered: loginHint.stringValue = feedback.isEmpty ? "Optional; currently off." : feedback
        case .requiresApproval: loginHint.stringValue = "Registered; approval needed in System Settings > General > Login Items."
        case .notFound: loginHint.stringValue = "Service not found. Enable to retry registration; failures will be shown."
        @unknown default: loginHint.stringValue = "Login item status unavailable."
        }
        if !feedback.isEmpty && status != .notRegistered { loginHint.stringValue = feedback }
    }

    func updateFeedbackForUpdates(_ message: String) {
        updateFeedback.stringValue = message
        updateFeedback.isHidden = message.isEmpty
    }

    @objc private func changeLogin(_ sender: NSButton) { onLoginChange(sender.state == .on) }
    @objc private func cancelLogin() { onLoginChange(false) }
}
