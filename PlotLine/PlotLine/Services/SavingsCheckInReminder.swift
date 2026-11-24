//
//  SavingsCheckInReminder.swift
//  PlotLine
//
//  Once a month (the 28th, 6 PM): "Did you move this month's savings?" for the emergency fund and
//  goals the budget sets money aside for that no linked account tracks. Tapping it opens Budget →
//  Plan, where one tap adds what was moved. Never asks for notification permission itself.
//

import Foundation
import UserNotifications

enum SavingsCheckInReminder {
    static let identifier = "savings-checkin"

    /// `total`: what the budget sets aside a month for untracked savings (0: no reminder)
    static func update(total: Double) {
        let center = UNUserNotificationCenter.current()
        guard total > 0 else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Did you move this month's savings?"
            content.body = "Your budget sets aside \(total.dollars()) for your emergency fund and goals. Tap to add it to your Plan."
            content.sound = .default
            content.userInfo = ["destination": "plan"]
            var day = DateComponents()
            day.day = 28
            day.hour = 18
            center.add(UNNotificationRequest(identifier: identifier, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: day, repeats: true)))
        }
    }
}
