import AppKit

/// Optional, inline help; opening controls never starts a permission flow.
final class HelpControls: NSObject {
    let view: NSStackView
    private let button = NSButton(title: "How It Works & Help", target: nil, action: nil)
    private let explanation = NSTextField(wrappingLabelWithString: "Magic Charger monitors supported accessories in the background. Menu-bar items appear only with verified charging evidence and disappear when none qualify. Unknown readings stay hidden.\n\nClosing this window keeps monitoring. Reopen Magic Charger from Finder or Spotlight for controls or Quit Magic Charger to stop monitoring. There is no permanent Dock icon.\n\nAlerts are optional. Choose the alerts you want, then enable notification permission if desired. Magic Charger cannot stop charging automatically.\n\nLocal labels such as Magic Mouse 1 distinguish accessories without showing their system names. Mute automatic alerts on a card to silence only that accessory; monitoring and menu-bar items continue. For accessories recognized only during the current connection, labels and mute choices may reset after reconnecting or quitting.\n\nMissing an accessory? Connect it and check its charge state. Unsupported, conflicting or stale readings can remain unknown.\n\nMissing an alert? Check the alert switches and Notification Settings, including banners and sound. Focus or screen sharing may suppress presentation. Send Test submits one labeled test; it does not simulate charging or confirm visible delivery.")
    var onLayoutChange: (() -> Void)?

    override init() {
        button.bezelStyle = .inline
        button.setAccessibilityHelp("Show or hide guidance about background monitoring, charging detection and notifications.")
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabelColor
        explanation.isSelectable = true
        explanation.isHidden = true
        view = NSStackView(views: [button, explanation])
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
        super.init()
        button.target = self; button.action = #selector(toggleHelp)
        explanation.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    @objc private func toggleHelp() {
        explanation.isHidden.toggle()
        button.title = explanation.isHidden ? "How It Works & Help" : "Hide Help"
        onLayoutChange?()
    }
}
