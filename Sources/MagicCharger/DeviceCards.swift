import AppKit

/// Keeps existing views and their accessibility elements attached across telemetry updates.
final class DeviceCards {
    let view = NSStackView()
    private var cards: [String: DeviceCard] = [:]
    private var orderedIDs: [String] = []
    private let empty = NSTextField(wrappingLabelWithString: "No Magic accessories detected.\nConnect a Magic Keyboard or Magic Mouse to get started.")
    private let announce: (String) -> Void
    private let isActive: (NSView) -> Bool
    private var hasUpdated = false

    init(announce: @escaping (String) -> Void = { message in
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }, isActive: @escaping (NSView) -> Bool = { $0.window?.isKeyWindow == true && NSApplication.shared.isActive }) {
        self.announce = announce
        self.isActive = isActive
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 10
        empty.font = .preferredFont(forTextStyle: .body); empty.textColor = .secondaryLabelColor
        view.addArrangedSubview(empty)
        empty.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    func update(_ readings: [Reading]) {
        let shouldAnnounce = hasUpdated && isActive(view)
        defer { hasUpdated = true }
        let readings = reconciled(readings)
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
            let card = DeviceCard(reading)
            cards[reading.id] = card; orderedIDs.append(reading.id)
            view.addArrangedSubview(card.view)
            card.view.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
            changes.append("\(reading.name) detected. \(card.state.stringValue).")
        }
        for id in orderedIDs {
            guard let reading = byID[id], let card = cards[id] else { continue }
            if let change = card.update(reading) { changes.append(change) }
        }
        empty.isHidden = !orderedIDs.isEmpty
        // Do not announce percentages, startup baselines or background polling.
        if shouldAnnounce, !changes.isEmpty { announce(changes.joined(separator: " ")) }
    }
}

private final class DeviceCard {
    let view = NSBox()
    let name = NSTextField(wrappingLabelWithString: "")
    let state = NSTextField(wrappingLabelWithString: "")
    private let image = NSImageView()
    private let percent = NSTextField(labelWithString: "")
    private var lastSymbol: String?
    private var lastState: String?

    init(_ reading: Reading) {
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
        view.contentView!.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.contentView!.leadingAnchor), row.trailingAnchor.constraint(equalTo: view.contentView!.trailingAnchor),
            row.topAnchor.constraint(equalTo: view.contentView!.topAnchor), row.bottomAnchor.constraint(equalTo: view.contentView!.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 68)
        ])
        update(reading)
    }

    @discardableResult func update(_ reading: Reading) -> String? {
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
