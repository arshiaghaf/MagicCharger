import AppKit
import UserNotifications
import CryptoKit
import ServiceManagement
import CoreServices

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let accessoryMonitor = AccessoryMonitor()
    let menuBar = MenuBarPresenter()
    var displayPreferences = MenuBarPreferences.load(.standard)
    var alertSettings = AlertSettings(preferences: .load(.standard))
    var alertPreferences: NotificationPreferences { alertSettings.preferences }
    var window: NSWindow!
    var controls: ControlsWindow!
    var timer: Timer?
    var engine = Thresholds()
    var starts = ChargingStarts()
    var latestReadings: [String: Reading] = [:]
    var lastPersistedAt = Date.distantPast
    var lastSessionSignature = ""
    var observations: [NSObjectProtocol] = []
    var suspended = false
    var refreshing = false
    var refreshPending = false
    var generation = 0
    var identityKey = Data()
    var notificationStatus = "Notifications have not been enabled."
    var notificationFeedback = ""
    var notificationDetails = "Notification policy has not been read."
    var foregroundPresentation = "No foreground presentation callback observed in this process."
    var pollInterval: TimeInterval = 30
    let telemetryQueue = DispatchQueue(label: "local.magiccharger.telemetry", qos: .utility)
    let center = UNUserNotificationCenter.current()
    let storage = "chargingSessions.v2"
    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = AppLaunch.isLoginItem(eventID: launchEvent?.eventID,
            launchData: launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue)
        NSApp.setActivationPolicy(.accessory)
        center.delegate = self
        let defaults = UserDefaults.standard
        if let key = defaults.data(forKey: "identityKey.v1"), key.count == 32 { identityKey = key }
        else { identityKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }; defaults.set(identityKey, forKey: "identityKey.v1") }
        updateNotificationStatus()
        if let data = UserDefaults.standard.data(forKey: storage), let sessions = try? JSONDecoder().decode([String: Session].self, from: data) { engine.sessions = sessions }
        makeWindow(); accessoryMonitor.onChange = { [weak self] in self?.refresh() }; refresh()
        if !launchedAtLogin { showSettings() }
        schedulePolling(30)
        let nc = NSWorkspace.shared.notificationCenter
        observations.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspended = true; self?.generation += 1; self?.starts.invalidate(); self?.engine.invalidateContinuity(); self?.menuBar.clear() })
        observations.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.suspended = false; self?.generation += 1; self?.refresh() })
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard controls != nil else { return }
        controls.updateLogin(status: SMAppService.mainApp.status)
        updateNotificationStatus()
    }
    func schedulePolling(_ interval: TimeInterval) {
        if timer != nil && pollInterval == interval { return }
        timer?.invalidate(); pollInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = interval == 10 ? 1 : 5
    }
    func refresh() {
        guard !suspended else { return }
        guard !refreshing else { refreshPending = true; return }
        refreshing = true
        let requestGeneration = generation, key = identityKey
        accessoryMonitor.observeRegistry()
        telemetryQueue.async {
            let readings = snapshot(identityKey: key)
            DispatchQueue.main.async {
                self.refreshing = false
                if !self.suspended && requestGeneration == self.generation { self.render(readings) }
                if self.refreshPending { self.refreshPending = false; self.refresh() }
            }
        }
    }
    func render(_ readings: [Reading]) {
        latestReadings = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        engine.retainContinuity(for: Set(readings.map { $0.id }))
        for started in starts.consume(readings) where alertPreferences.started { notifyStarted(started) }
        let activeIDs = menuBar.retainChargingItems(for: readings)
        schedulePolling(activeIDs.isEmpty ? 30 : 10)
        var diagnostic = readings.isEmpty ? "No supported accessories detected.\nMonitoring every 30 seconds." : readings.map { "\($0.name): \($0.percent.map { "\($0)%" } ?? "unknown") — \($0.state.rawValue)\n\($0.evidence)" }.joined(separator: "\n\n")
        diagnostic += "\n\nMenu-bar items: \(activeIDs.count); polling: \(Int(pollInterval)) seconds.\n" + notificationStatus
        if !notificationFeedback.isEmpty { diagnostic += "\n" + notificationFeedback }
        diagnostic += "\n" + starts.lastDecisions.joined(separator: "\n")
        diagnostic += "\n\n" + notificationDetails + "\n" + foregroundPresentation
        controls.update(readings: readings, notificationStatus: notificationStatus, feedback: notificationFeedback, diagnostic: diagnostic)
        for r in readings {
            let thresholds = engine.consume(r, enabled: alertPreferences.milestones)
            if !thresholds.isEmpty { notify(r, threshold: thresholds.max()!) }
            menuBar.present(r, preferences: displayPreferences, target: self)
        }
        let signature = engine.sessions.sorted { $0.key < $1.key }.map {
            "\($0.key):\($0.value.sent.sorted()):\($0.value.lastPercent ?? -1):\($0.value.ended)"
        }.joined(separator: ";")
        if signature != lastSessionSignature || (!activeIDs.isEmpty && Date().timeIntervalSince(lastPersistedAt) >= 60) {
            persistSessions(); lastSessionSignature = signature
        }
    }
    func persistSessions() {
        if let data = try? JSONEncoder().encode(engine.sessions) {
            UserDefaults.standard.set(data, forKey: storage); lastPersistedAt = Date()
        }
    }
    func applicationWillTerminate(_ notification: Notification) { persistSessions() }
    func makeWindow() {
        controls = ControlsWindow(target: self, enable: #selector(permissions), test: #selector(testNotification), updates: #selector(viewReleases), loginSettings: #selector(openLoginItemsSettings), quit: #selector(quit), preferences: displayPreferences, alerts: alertPreferences, onChange: { [weak self] preferences in
            self?.displayPreferences = preferences
            preferences.save(.standard)
            self?.refresh()
        }, onAlertsChange: { [weak self] preferences in
            self?.updateAlertPreferences(preferences)
        }, onLoginChange: { [weak self] enabled in self?.changeLaunchAtLogin(enabled) })
        window = controls.window
    }
    @objc func viewReleases() {
        let releases = URL(string: "https://github.com/arshiaghaf/magic-charger/releases")!
        controls.updateFeedbackForUpdates(NSWorkspace.shared.open(releases) ? "" : "Couldn’t open the releases page. Try again from your browser.")
    }
    @objc func showSettings() {
        window.makeKeyAndOrderFront(nil)
        controls.updateLogin(status: SMAppService.mainApp.status)
        updateNotificationStatus()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
}
