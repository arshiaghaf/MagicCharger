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
    var lifecycle = AlertLifecycle()
    var engine: Thresholds { get { lifecycle.thresholds } set { lifecycle.thresholds = newValue } }
    var starts: ChargingStarts { lifecycle.starts }
    var latestReadings: [String: Reading] { lifecycle.latest }
    var lastPersistedAt = Date.distantPast
    var lastSessionSignature = ""
    var observations: [NSObjectProtocol] = []
    var identityKey = Data()
    var collectionMessage: String?
    var notificationStatus = "Notifications have not been enabled."
    var notificationFeedback = ""
    var notificationDetails = "Notification policy has not been read."
    var foregroundPresentation = "No foreground presentation callback observed in this process."
    var pollInterval: TimeInterval = 30
    let telemetryQueue = DispatchQueue(label: "local.magiccharger.telemetry", qos: .utility)
    let center = UNUserNotificationCenter.current()
    lazy var collectionScheduler = CollectionScheduler(collect: { [weak self] completion in
        guard let self = self else { return }
        self.accessoryMonitor.observeRegistry()
        let key = self.identityKey
        self.telemetryQueue.async {
            let outcome = snapshot(identityKey: key)
            DispatchQueue.main.async { completion(outcome) }
        }
    }, schedule: { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) },
       receive: { [weak self] outcome in self?.render(outcome) })
    let sessionStore = SessionStore(defaults: .standard)
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
        engine = sessionStore.load()
        makeWindow(); accessoryMonitor.onChange = { [weak self] in self?.refresh() }; refresh()
        if !launchedAtLogin { showSettings() }
        schedulePolling(30)
        let nc = NSWorkspace.shared.notificationCenter
        observations.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.lifecycle.suspend(); self?.collectionScheduler.suspend(); self?.menuBar.clear() })
        observations.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.lifecycle.resume(); self?.collectionScheduler.resume() })
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
    func refresh() { collectionScheduler.request() }
    func render(_ outcome: CollectionOutcome) {
        let readings = outcome.readings
        collectionMessage = outcome.message
        window.subtitle = outcome.message ?? ""
        let selected = lifecycle.observe(readings, now: Date(), preferences: alertPreferences)
        for alert in selected {
            if alert.kind == .started { notifyStarted(alert.reading) }
            else { notify(alert.reading, threshold: alert.kind == .soon ? 78 : (alert.kind == .target ? 80 : 100)) }
        }
        let activeIDs = menuBar.retainChargingItems(for: readings)
        schedulePolling(activeIDs.isEmpty ? 30 : 10)
        var diagnostic = readings.isEmpty ? (outcome.message ?? "No supported accessories detected.\nMonitoring every 30 seconds.") : readings.map { "\($0.name): \($0.percent.map { "\($0)%" } ?? "unknown") — \($0.state.rawValue)\n\($0.evidence)" }.joined(separator: "\n\n")
        diagnostic += "\n\nMenu-bar items: \(activeIDs.count); polling: \(Int(pollInterval)) seconds.\n" + notificationStatus
        if !notificationFeedback.isEmpty { diagnostic += "\n" + notificationFeedback }
        diagnostic += "\n" + starts.lastDecisions.joined(separator: "\n")
        diagnostic += "\n\n" + notificationDetails + "\n" + foregroundPresentation
        controls.update(readings: readings, notificationStatus: notificationStatus, feedback: notificationFeedback, diagnostic: diagnostic)
        for r in readings {
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
        sessionStore.save(engine.sessions); lastPersistedAt = Date()
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
