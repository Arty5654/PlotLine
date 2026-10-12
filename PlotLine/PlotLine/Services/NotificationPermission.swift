//
//  NotificationPermission.swift
//  PlotLine
//
//  One place that asks for notification permission. The Get Started card asks at its last step;
//  otherwise the question comes when someone turns on something that needs notifications (a
//  reminder, subscription alerts). If they said no before, iPhone won't ask again, so the app
//  explains how to turn notifications on in Settings instead of silently doing nothing.
//

import UIKit
import UserNotifications

enum NotificationPermission {

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    /// For something the person just turned on that needs notifications ("event reminders").
    /// Asks the first time; if notifications are off, offers to open Settings. Returns whether
    /// notifications can be shown.
    @MainActor
    @discardableResult
    static func ensure(for feature: String) async -> Bool {
        switch await status() {
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { PushRegistration.register() }
            return granted // they just answered the system question: no second alert
        case .denied:
            showTurnOnInSettings(for: feature)
            return false
        default:
            PushRegistration.register()
            return true
        }
    }

    /// "Notifications are off. To get event reminders, turn on notifications for PlotLine in Settings."
    @MainActor
    static func showTurnOnInSettings(for feature: String) {
        let alert = UIAlertController(
            title: "Notifications Are Off",
            message: "To get \(feature), turn on notifications for PlotLine in Settings.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        topViewController()?.present(alert, animated: true)
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
