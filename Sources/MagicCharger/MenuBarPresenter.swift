import AppKit

final class MenuBarPresenter {
    private var items: [String: NSStatusItem] = [:]
    private var itemImageSignatures: [String: String] = [:]

    func clear() {
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        items.removeAll()
        itemImageSignatures.removeAll()
    }

    func retainChargingItems(for readings: [Reading]) -> Set<String> {
        // Reuse items so an open menu is not destroyed on each telemetry update.
        let activeIDs = Set(readings.filter { $0.active }.map { $0.id })
        for id in Array(items.keys) where !activeIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(items.removeValue(forKey: id)!)
            itemImageSignatures.removeValue(forKey: id)
        }
        return activeIDs
    }

    func present(_ r: Reading, preferences: MenuBarPreferences, target: AppDelegate) {
        guard let content = MenuBarContent(r, preferences: preferences) else { return }
        let item: NSStatusItem
        if let existing = items[r.id] { item = existing }
        else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            items[r.id] = item
            let menu = NSMenu(); menu.addItem(withTitle: "\(r.name) — \(content.status)", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings), keyEquivalent: ",").target = target
            menu.addItem(withTitle: "Quit Magic Charger", action: #selector(AppDelegate.quit), keyEquivalent: "q").target = target
            item.menu = menu
        }
        item.menu?.items.first?.title = "\(r.name) — \(content.status)"
        if item.button?.title != content.title { item.button?.title = content.title }
        item.button?.imagePosition = .imageLeft
        let imageSignature = "\(r.symbol):\(preferences.deviceGlyph)"
        if itemImageSignatures[r.id] != imageSignature {
            item.button?.image = preferences.deviceGlyph ? MenuBarIcon.image(symbol: r.symbol) : nil
            itemImageSignatures[r.id] = imageSignature
        }
        let description = content.accessibilityLabel
        if item.button?.toolTip != description {
            item.button?.setAccessibilityLabel(description)
            item.button?.toolTip = description
        }
    }
}
