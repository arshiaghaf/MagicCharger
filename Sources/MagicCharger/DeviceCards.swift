import AppKit

/// Keeps existing views and their accessibility elements attached across telemetry updates.
final class DeviceCards {
    let view = NSStackView()
    private var cards: [String: DeviceCard] = [:]
    private var orderedIDs: [String] = []
    private let empty = NSTextField(wrappingLabelWithString: "No Magic accessories detected.\nConnect a Magic Keyboard or Magic Mouse to get started.")
    private let collectionNotice = NSTextField(wrappingLabelWithString: "")
    private var lastCollectionMessage: String?
    private let onMuteChange: (String, Bool) -> Void
    private let announce: (String) -> Void
    private let isActive: (NSView) -> Bool
    private var hasUpdated = false

    init(announce: @escaping (String) -> Void = { message in
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }, isActive: @escaping (NSView) -> Bool = { $0.window?.isKeyWindow == true && NSApplication.shared.isActive },
         onMuteChange: @escaping (String, Bool) -> Void = { _, _ in }) {
        self.announce = announce
        self.onMuteChange = onMuteChange
        self.isActive = isActive
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 10
        empty.font = .preferredFont(forTextStyle: .body); empty.textColor = .secondaryLabelColor
        collectionNotice.font = .preferredFont(forTextStyle: .body); collectionNotice.isHidden = true
        view.addArrangedSubview(collectionNotice)
        collectionNotice.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        view.addArrangedSubview(empty)
        empty.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    func update(_ readings: [Reading], settings: DeviceSettings? = nil, collectionMessage: String? = nil) {
        let active = hasUpdated && isActive(view)
        let shouldAnnounce = active && collectionMessage == nil && lastCollectionMessage == nil
        defer { hasUpdated = true; lastCollectionMessage = collectionMessage }
        let notice = collectionMessage ?? ""
        if collectionNotice.stringValue != notice { collectionNotice.stringValue = notice }
        collectionNotice.isHidden = collectionMessage == nil
        let readings = reconciled(settings?.labeled(readings) ?? readings)
        let byID = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        var changes: [String] = []
        for id in orderedIDs where byID[id] == nil {
            guard let card = cards.removeValue(forKey: id) else { continue }
            changes.append("\(card.name.stringValue) no longer detected.")
            view.removeArrangedSubview(card.view); card.view.removeFromSuperview()
        }
        orderedIDs.removeAll { byID[$0] == nil }
        // Existing cards keep their reading order, even if a label changes.
        let additions = readings.filter { cards[$0.id] == nil }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
        for reading in additions {
            let card = DeviceCard(reading, muted: settings.map { $0.isMuted(reading.id) }, onMuteChange: onMuteChange)
            cards[reading.id] = card; orderedIDs.append(reading.id)
            view.addArrangedSubview(card.view)
            card.view.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
            changes.append("\(reading.name) detected. \(card.state.stringValue).")
        }
        for id in orderedIDs {
            guard let reading = byID[id], let card = cards[id] else { continue }
            if let change = card.update(reading, muted: settings.map { $0.isMuted(id) }) { changes.append(change) }
        }
        empty.isHidden = !orderedIDs.isEmpty || collectionMessage != nil
        // Do not announce percentages, startup baselines or background polling.
        if active, collectionMessage != lastCollectionMessage {
            announce(collectionMessage ?? "Accessory information is available again.")
        } else if shouldAnnounce, !changes.isEmpty { announce(changes.joined(separator: " ")) }
    }
}

private final class DeviceCard: NSObject {
    let view = NSBox()
    let name = NSTextField(wrappingLabelWithString: "")
    let state = NSTextField(wrappingLabelWithString: "")
    private let image = NSImageView()
    private let percent = NSTextField(labelWithString: "")
    private let content = NSStackView()
    private let mute = NSButton(checkboxWithTitle: "Mute automatic alerts", target: nil, action: nil)
    private let muteHint = NSTextField(wrappingLabelWithString: "Temporary choice · may reset after reconnecting or quitting.")
    private let id: String
    private let onMuteChange: (String, Bool) -> Void
    private var lastSymbol: String?
    private var lastState: String?

    init(_ reading: Reading, muted: Bool?, onMuteChange: @escaping (String, Bool) -> Void) {
        id = reading.id; self.onMuteChange = onMuteChange
        super.init()
        view.boxType = .custom; view.cornerRadius = 12; view.borderWidth = 0
        view.fillColor = .controlBackgroundColor; view.contentViewMargins = NSSize(width: 16, height: 12)
        image.setAccessibilityHidden(true)
        image.cell?.setAccessibilityHidden(true)
        image.contentTintColor = .labelColor; image.imageScaling = .scaleProportionallyDown
        image.widthAnchor.constraint(equalToConstant: 32).isActive = true
        image.heightAnchor.constraint(equalToConstant: 30).isActive = true
        name.font = .preferredFont(forTextStyle: .headline)
        state.font = .preferredFont(forTextStyle: .body); state.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [name, state])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 4
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        state.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        percent.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular); percent.alignment = .right
        percent.setContentHuggingPriority(.required, for: .horizontal)
        percent.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [image, labels, percent])
        row.spacing = 14; row.alignment = .centerY; row.translatesAutoresizingMaskIntoConstraints = false
        mute.font = .preferredFont(forTextStyle: .body); mute.target = self; mute.action = #selector(changeMute)
        muteHint.font = .preferredFont(forTextStyle: .body); muteHint.textColor = .secondaryLabelColor
        content.addArrangedSubview(row)
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 8; content.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        view.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.contentView!.leadingAnchor), content.trailingAnchor.constraint(equalTo: view.contentView!.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.contentView!.topAnchor), content.bottomAnchor.constraint(equalTo: view.contentView!.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 68)
        ])
        update(reading, muted: muted)
    }

    @objc private func changeMute() { onMuteChange(id, mute.state == .on) }

    @discardableResult func update(_ reading: Reading, muted: Bool?) -> String? {
        if muted != nil, mute.superview == nil {
            content.addArrangedSubview(mute); content.addArrangedSubview(muteHint)
            muteHint.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        mute.isHidden = muted == nil
        muteHint.isHidden = muted == nil || DeviceIdentity.isPersistent(id)
        if let muted = muted {
            let value: NSControl.StateValue = muted ? .on : .off
            if mute.state != value { mute.state = value }
            let label = "Mute automatic alerts for \(reading.name)"
            if mute.accessibilityLabel() != label { mute.setAccessibilityLabel(label) }
            let help = DeviceIdentity.isPersistent(id)
                ? "Silence this accessory's automatic alerts. The choice is saved only on this Mac; monitoring continues."
                : "Silence this accessory's automatic alerts for its current connection. This choice may reset after reconnecting or quitting. Monitoring continues."
            if mute.accessibilityHelp() != help { mute.setAccessibilityHelp(help) }
        }
        if name.stringValue != reading.name { name.stringValue = reading.name }
        if lastSymbol != reading.symbol {
            image.image = NSImage(systemSymbolName: reading.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26, weight: .regular))
            lastSymbol = reading.symbol
        }
        let status: String
        switch reading.state {
        case .charging: status = "Charging"
        case .idle: status = "Not charging"
        case .unknown: status = reading.fullChargeEvidence ? "100% reported · charging state unknown" : "Charging state unknown"
        }
        let changedState = lastState != nil && lastState != status
        if state.stringValue != status { state.stringValue = status }; lastState = status
        let percentage = reading.percent.map { "\($0)%" } ?? "—"
        if percent.stringValue != percentage { percent.stringValue = percentage }
        let description = reading.percent.map { "\($0) percent" } ?? "Battery level unknown"
        if percent.accessibilityLabel() != description { percent.setAccessibilityLabel(description) }
        return changedState ? "\(reading.name): \(status)." : nil
    }
}
