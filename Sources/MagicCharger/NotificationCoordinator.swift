import AppKit
import UserNotifications

extension AppDelegate {
    func submitNotification(_ content: UNMutableNotificationContent, reading: Reading, identifier: String, kind: AlertKind) {
        let ticket = lifecycle.ticket(for: reading, kind: kind)
        let requestToken = alertSettings.token(kind)
        let deviceToken = deviceSettings.revision(for: reading.id)
        let delivery = AlertDelivery(authorize: { callback in
            self.center.getNotificationSettings { settings in
                callback(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }, schedule: { DispatchQueue.main.async(execute: $0) })
        delivery.submit(isValid: {
            self.alertSettings.canSubmit(kind, token: requestToken) &&
            !self.deviceSettings.isMuted(reading.id) && self.deviceSettings.revision(for: reading.id) == deviceToken &&
            self.lifecycle.validates(ticket, now: Date())
        }, send: { completion in
            self.center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { completion($0 == nil) }
        }, feedback: { message in
            self.notificationFeedback = message; self.refresh()
        })
    }
    func notifyStarted(_ r: Reading) {
        guard let percent = r.percent, (0...100).contains(percent) else { return }
        let copy = NotificationCopy.started(name: r.name, percent: percent)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        submitNotification(content, reading: r, identifier: "started-\(r.id)-\(UUID().uuidString)", kind: .started)
    }
    func notify(_ r: Reading, threshold: Int) {
        let copy = NotificationCopy.milestone(name: r.name, percent: r.percent, threshold: threshold)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        submitNotification(content, reading: r, identifier: "milestone-\(threshold)-\(r.id)", kind: .milestone(threshold))
    }
    func updateAlertPreferences(_ preferences: NotificationPreferences) {
        let disabled = AlertKind.allCases.filter { !preferences.allows($0) }
        alertSettings.update(preferences); preferences.save(.standard)
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.filter { request in
                disabled.contains { kind in
                    switch kind {
                    case .started: return request.identifier.hasPrefix("started-")
                    case .soon: return request.identifier.hasPrefix("milestone-78-")
                    case .target: return request.identifier.hasPrefix("milestone-80-")
                    case .full: return request.identifier.hasPrefix("milestone-100-")
                    }
                }
            }.map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        refresh()
    }
    func updateNotificationStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                func setting(_ value: UNNotificationSetting) -> String {
                    switch value { case .enabled: return "enabled"; case .disabled: return "disabled"; case .notSupported: return "not supported"; @unknown default: return "unknown" }
                }
                let authorization: String
                switch settings.authorizationStatus {
                case .authorized: authorization = "authorized"
                case .provisional: authorization = "provisional (quiet delivery)"
                case .denied: authorization = "denied"
                case .notDetermined: authorization = "not requested"
                default: authorization = "other"
                }
                let style: String
                switch settings.alertStyle { case .banner: style = "banner"; case .alert: style = "alert"; case .none: style = "none"; @unknown default: style = "unknown" }
                self.notificationDetails = "Notification policy: authorization=\(authorization); alerts=\(setting(settings.alertSetting)); style=\(style); Notification Center=\(setting(settings.notificationCenterSetting)); sound=\(setting(settings.soundSetting)); scheduled delivery=\(setting(settings.scheduledDeliverySetting))."
                switch settings.authorizationStatus {
                case .authorized, .provisional: self.notificationStatus = "Notifications enabled."
                case .denied: self.notificationStatus = "Notifications denied. Change this in System Settings if desired."
                case .notDetermined: self.notificationStatus = "Notification permission not requested. Use Enable Notifications to allow alerts."
                default: self.notificationStatus = "Notification authorization unavailable."
                }
                self.refresh()
            }
        }
    }
    @objc func testNotification() {
        // User-triggered test only. Never inject a battery sample or touch dedup state.
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                DispatchQueue.main.async {
                    self.notificationFeedback = settings.authorizationStatus == .notDetermined
                        ? "Test not sent. Click Enable Notifications and answer the macOS prompt first."
                        : "Test not sent. Notification permission is not enabled."
                    self.updateNotificationStatus()
                }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Magic Charger — Test Notification"
            content.body = "This is a user-requested notification test. No battery threshold was crossed."
            content.sound = .default
            self.center.add(UNNotificationRequest(identifier: "test-" + UUID().uuidString, content: content, trigger: nil)) { error in
                DispatchQueue.main.async {
                    self.notificationFeedback = error == nil
                        ? "Test submitted to macOS. Confirm whether its banner appeared; Focus may suppress it."
                        : "Test submission failed. Check notification settings."
                    self.refresh()
                }
            }
        }
    }
    @objc func permissions() {
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                self.center.requestAuthorization(options: [.alert, .sound]) { _, error in
                    DispatchQueue.main.async {
                        if error != nil { self.notificationFeedback = "Notification permission request failed. See System Settings > Notifications." }
                        self.updateNotificationStatus()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.notificationFeedback = "Open Notifications in System Settings and select Magic Charger."
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        if error != nil { DispatchQueue.main.async { self.notificationFeedback = "System Settings could not be opened. Open Notifications manually."; self.refresh() } }
                    }
                    self.refresh()
                }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        DispatchQueue.main.async {
            self.foregroundPresentation = "Foreground delegate ran: requested banner, Notification Center and sound for \(notification.request.identifier.hasPrefix("test-") ? "test" : "automatic") notification."
            self.refresh()
        }
    }
}
