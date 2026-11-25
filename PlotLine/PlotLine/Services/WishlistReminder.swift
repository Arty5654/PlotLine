//
//  WishlistReminder.swift
//  PlotLine
//
//  "Can I afford it?" → wishlist: once an item's cooling-off period is over (2 or 30 days), a
//  reminder that morning: "Still want it?" Tapping it opens Budget → Plan, where the wishlist is.
//  One notification per item, kept in step with the list. Never asks for permission itself.
//

import Foundation
import UserNotifications

enum WishlistReminder {
    static let prefix = "wishlist-"

    /// reminders for these items (ones already due, or saved for, get none)
    static func update(_ items: [WishItem], now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let wanted = Set(items.filter { $0.goalId == nil && !$0.readyToDecide(now: now) }.map { prefix + $0.id })
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !wanted.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            let scheduled = Set(pending.map(\.identifier))
            center.getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
                for item in items where wanted.contains(prefix + item.id) && !scheduled.contains(prefix + item.id) {
                    guard let day = Plan.day(item.remindOn) else { continue }
                    var when = Calendar.current.dateComponents([.year, .month, .day], from: day)
                    when.hour = 10
                    let content = UNMutableNotificationContent()
                    content.title = "Still want the \(item.item)?"
                    content.body = "You put it on your wishlist on \(Plan.day(item.addedOn)?.formatted(.dateTime.month(.abbreviated).day()) ?? item.addedOn). Check if you can afford it now, or let it go."
                    content.sound = .default
                    content.userInfo = ["destination": "plan"]
                    center.add(UNNotificationRequest(identifier: prefix + item.id, content: content,
                                                     trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
                }
            }
        }
    }
}
