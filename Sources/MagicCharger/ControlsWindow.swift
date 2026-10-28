import AppKit
import ServiceManagement

private final class ControlsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class ControlsWindow: NSWindowController, NSWindowDelegate {
    private let scrollView = NSScrollView()
    private let documentView = ControlsDocumentView()
    private let stack = NSStackView()
    private let devices = DeviceCards()
    private let notifications: NotificationControls
    private let help = HelpControls()
    private let general: GeneralControls
    private let glyphToggle = NSButton(checkboxWithTitle: "Device icon", target: nil, action: nil)
    private let percentToggle = NSButton(checkboxWithTitle: "Percentage", target: nil, action: nil)
    private let emojiToggle = NSButton(checkboxWithTitle: "Status emoji", target: nil, action: nil)
    private let preferenceHint = NSTextField(wrappingLabelWithString: "Keep at least one item visible.")
    private let onPreferencesChange: (MenuBarPreferences) -> Void
    private var diagnostic = ""
    private var detailsWindow: NSWindow?
    private var hasUserResized = false
    private var adjustingLayout = false

    init(target: AnyObject, enable: Selector, test: Selector, updates: Selector, loginSettings: Selector, quit: Selector, preferences: MenuBarPreferences, alerts: NotificationPreferences, onChange: @escaping (MenuBarPreferences) -> Void, onAlertsChange: @escaping (NotificationPreferences) -> Void, onLoginChange: @escaping (Bool) -> Void, notificationSettingsReader: ((@escaping (NotificationReadiness) -> Void) -> Void)? = nil) {
        onPreferencesChange = onChange
        notifications = NotificationControls(target: target, enable: enable, test: test, alerts: alerts, onAlertsChange: onAlertsChange, readSettings: notificationSettingsReader)
        general = GeneralControls(target: target, updates: updates, loginSettings: loginSettings, onLoginChange: onLoginChange)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Magic Charger"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        help.onLayoutChange = { [weak self] in self?.resizeForContent() }
        notifications.onLayoutChange = { [weak self] in self?.resizeForContent() }
        NotificationCenter.default.addObserver(notifications, selector: #selector(NotificationControls.refreshSettings),
            name: NSWindow.didBecomeKeyNotification, object: window)
        window.center()
        let content = window.contentView!
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Magic Charger")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let introduction = NSTextField(wrappingLabelWithString: "Menu-bar items appear only while a supported accessory is charging. Reopen Magic Charger from Finder or Spotlight for controls.")
        introduction.font = .preferredFont(forTextStyle: .body); introduction.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, introduction]); heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 7
        introduction.widthAnchor.constraint(equalTo: heading.widthAnchor).isActive = true
        let menuTitle = NSTextField(labelWithString: "Menu Bar"); menuTitle.font = .preferredFont(forTextStyle: .headline)
        glyphToggle.state = preferences.deviceGlyph ? .on : .off
        percentToggle.state = preferences.percentage ? .on : .off
        emojiToggle.state = preferences.statusEmoji ? .on : .off
        for toggle in [glyphToggle, percentToggle, emojiToggle] { toggle.target = self; toggle.action = #selector(changePreferences(_:)) }
        let toggles = NSStackView(views: [glyphToggle, percentToggle, emojiToggle]); toggles.orientation = .vertical; toggles.alignment = .leading; toggles.spacing = 8
        preferenceHint.font = .preferredFont(forTextStyle: .body); preferenceHint.textColor = .secondaryLabelColor; preferenceHint.isHidden = true
        let menuOptions = NSStackView(views: [menuTitle, toggles, preferenceHint]); menuOptions.orientation = .vertical; menuOptions.alignment = .leading; menuOptions.spacing = 10
        let details = NSButton(title: "Technical Details…", target: self, action: #selector(showDetails)); details.bezelStyle = .inline
        let quitButton = NSButton(title: "Quit Magic Charger", target: target, action: quit); quitButton.keyEquivalent = "q"; quitButton.keyEquivalentModifierMask = .command
        let about = NSButton(title: "About", target: self, action: #selector(showAbout)); about.bezelStyle = .inline
        let footer = NSStackView(views: [details, about, quitButton]); footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 10
        for view in [heading, devices.view, menuOptions, notifications.view, general.view, footer] { stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.insertArrangedSubview(help.view, at: stack.arrangedSubviews.count - 1)
        help.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scrollView.hasVerticalScroller = true; scrollView.autohidesScrollers = true; scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        documentView.frame = NSRect(x: 0, y: 0, width: 500, height: 430)
        scrollView.documentView = documentView
        documentView.addSubview(stack)
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor), scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 26)
        ])
        useReadableFonts(in: stack)
        window.contentMinSize = NSSize(width: 360, height: 300)
        window.autorecalculatesKeyViewLoop = true
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(readings: [Reading], notificationStatus: String, feedback message: String, diagnostic: String) {
        self.diagnostic = diagnostic
        devices.update(readings)
        notifications.update(status: notificationStatus, message: message)
        resizeForContent()
    }

    func updateLogin(status: SMAppService.Status, feedback: String = "") {
        general.updateLogin(status: status, feedback: feedback)
        resizeForContent()
    }

    func updateFeedbackForUpdates(_ message: String) {
        general.updateFeedbackForUpdates(message)
        resizeForContent()
    }

    static func boundedContentHeight(requested: CGFloat, visible: CGFloat, chrome: CGFloat) -> CGFloat {
        min(requested, max(1, visible - chrome - 40))
    }

    func windowWillStartLiveResize(_ notification: Notification) { hasUserResized = true }
    func windowDidResize(_ notification: Notification) {
        if !adjustingLayout { hasUserResized = true }
        resizeForContent()
    }
    func windowDidChangeScreen(_ notification: Notification) { resizeForContent() }

    private func useReadableFonts(in view: NSView) {
        if let field = view as? NSTextField, let font = field.font,
           font.pointSize < NSFont.preferredFont(forTextStyle: .body).pointSize {
            field.font = NSFontManager.shared.convert(font, toSize: NSFont.preferredFont(forTextStyle: .body).pointSize)
        }
        for child in view.subviews { useReadableFonts(in: child) }
    }

    private func resizeForContent() {
        guard !adjustingLayout, let window = window, let content = window.contentView else { return }
        adjustingLayout = true
        defer { adjustingLayout = false }
        let chrome = window.frame.height - window.contentLayoutRect.height
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 500, height: 700)
        let maxWidth = max(1, visible.width - 40)
        let maxHeight = Self.boundedContentHeight(requested: .greatestFiniteMagnitude, visible: visible.height, chrome: chrome)
        window.contentMinSize = NSSize(width: min(360, maxWidth), height: min(300, maxHeight))
        window.contentMaxSize = NSSize(width: maxWidth, height: maxHeight)
        let width = min(window.contentLayoutRect.width, maxWidth)
        if abs(window.contentLayoutRect.width - width) > 1 {
            window.setContentSize(NSSize(width: width, height: min(window.contentLayoutRect.height, maxHeight)))
        }
        content.layoutSubtreeIfNeeded()
        documentView.setFrameSize(NSSize(width: max(1, scrollView.contentSize.width), height: documentView.frame.height))
        documentView.layoutSubtreeIfNeeded()
        let requested = max(CGFloat(430), stack.fittingSize.height + 48)
        documentView.setFrameSize(NSSize(width: documentView.frame.width, height: max(scrollView.contentSize.height, requested)))
        let height = min(hasUserResized ? window.contentLayoutRect.height : requested, maxHeight)
        var frame = window.frame
        let newHeight = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height)).height
        let top = frame.maxY
        frame.size.height = newHeight
        frame.origin.x = min(max(frame.minX, visible.minX + 20), visible.maxX - frame.width - 20)
        frame.origin.y = min(max(top - newHeight, visible.minY + 20), visible.maxY - newHeight - 20)
        if frame != window.frame { window.setFrame(frame, display: true) }
        window.recalculateKeyViewLoop()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Magic Charger",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .credits: NSAttributedString(string: "MIT License · Copyright © 2026 Arshia Ghaf\nLocal accessory charging notifications.")
        ])
    }

    @objc private func changePreferences(_ sender: NSButton) {
        let preferences = MenuBarPreferences(deviceGlyph: glyphToggle.state == .on, percentage: percentToggle.state == .on, statusEmoji: emojiToggle.state == .on)
        guard preferences.isValid else { sender.state = .on; preferenceHint.isHidden = false; resizeForContent(); return }
        preferenceHint.isHidden = true
        resizeForContent()
        onPreferencesChange(preferences)
    }

    @objc private func showDetails() {
        guard let parent = window else { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Technical Details"
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 60, width: 540, height: 280)); scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.string = diagnostic; text.textContainerInset = NSSize(width: 8, height: 8); scroll.documentView = text
        let done = NSButton(title: "Done", target: self, action: #selector(closeDetails)); done.keyEquivalent = "\r"; done.frame = NSRect(x: 490, y: 18, width: 70, height: 30)
        sheet.contentView!.addSubview(scroll); sheet.contentView!.addSubview(done)
        detailsWindow = sheet; parent.beginSheet(sheet)
    }
    @objc private func closeDetails() {
        if let sheet = detailsWindow { window?.endSheet(sheet); sheet.orderOut(nil); detailsWindow = nil }
    }
}
