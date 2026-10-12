//
//  EventReminders.swift
//  PlotLine
//
//  "Dinner starts in 15 minutes": the reminders someone picks on a calendar event.
//
//  The choice belongs to the event: for a repeating one (PlotLine's own, or from Apple or Google
//  Calendar) every date gets the reminders, not just the date that was open. iPhone only keeps 64
//  scheduled notifications per app, so the soonest few weeks are scheduled and topped up each time
//  the calendar loads.
//
//  The scheduled notifications are worked out from the events every time ("reconciled"), so a
//  deleted event stops reminding (it didn't before), a moved or renamed one is rescheduled, and
//  signing out clears them.
//

import Foundation
import UserNotifications

enum EventReminders {

    static let prefix = "reminder_"
    /// how far ahead dates get their notifications, and at most how many (iPhone's limit is 64 for the whole app)
    static let horizonDays = 45
    static let maxScheduled = 40

    // MARK: - The choice

    private static func savedKey(_ key: String) -> String { "event_reminders_\(key)" }

    /// The reminders picked for an event (seconds before its start). `event`: a date shown in the
    /// calendar; for a repeating event the choice is the series'.
    static func saved(for event: Event) -> Set<TimeInterval> {
        // an older choice may have been saved for just the date that was open
        saved(forKey: event.seriesKey).union(event.id == event.seriesKey ? [] : saved(forKey: event.id))
    }

    static func saved(forKey key: String) -> Set<TimeInterval> {
        Set((UserDefaults.standard.array(forKey: savedKey(key)) as? [Double] ?? []).map { TimeInterval($0) })
    }

    /// Saves the reminders for an event (a repeating one: every date of it). They're scheduled at the
    /// next reconcile, which the calendar does after saving.
    static func set(_ offsets: Set<TimeInterval>, forKey key: String) {
        if offsets.isEmpty {
            UserDefaults.standard.removeObject(forKey: savedKey(key))
        } else {
            UserDefaults.standard.set(Array(offsets), forKey: savedKey(key))
        }
    }

    /// The reminders chosen while a date of `event` was open: for the whole series, replacing a
    /// choice saved earlier for just that date.
    static func set(_ offsets: Set<TimeInterval>, for event: Event) {
        set(offsets, forKey: event.seriesKey)
        if event.id != event.seriesKey { UserDefaults.standard.removeObject(forKey: savedKey(event.id)) }
    }

    // MARK: - What should be scheduled

    struct Planned: Equatable {
        let identifier: String     // "reminder_<date id>_<seconds>"
        let eventId: String
        let title: String
        let start: Date
        let secondsBefore: TimeInterval
        let friend: String?
        var fireDate: Date { start.addingTimeInterval(-secondsBefore) }
    }

    static func identifier(eventId: String, secondsBefore: TimeInterval) -> String {
        "\(prefix)\(eventId)_\(Int(secondsBefore))"
    }

    /// "reminder_abc::2026-10-12_900" → "abc::2026-10-12"
    static func eventId(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(prefix), let underscore = identifier.lastIndex(of: "_") else { return nil }
        let id = identifier[identifier.index(identifier.startIndex, offsetBy: prefix.count)..<underscore]
        return id.isEmpty ? nil : String(id)
    }

    /// Every reminder that should be waiting: for each date (of every event, every repeat) in the
    /// next few weeks, its event's reminders that are still ahead; the soonest `maxScheduled`.
    static func planned(ownEvents: [Event], friendEvents: [String: [Event]],
                        offsets: (Event) -> Set<TimeInterval> = saved(for:), now: Date = Date()) -> [Planned] {
        let horizon = now.addingTimeInterval(TimeInterval(horizonDays) * 86400)
        var result: [String: Planned] = [:]
        func add(_ events: [Event], friend: String?) {
            for event in events where event.startDate > now && event.startDate <= horizon {
                for seconds in offsets(event) {
                    let planned = Planned(identifier: identifier(eventId: event.id, secondsBefore: seconds), eventId: event.id,
                                          title: event.title, start: event.startDate, secondsBefore: seconds, friend: friend)
                    if planned.fireDate > now { result[planned.identifier] = planned }
                }
            }
        }
        add(ownEvents, friend: nil)
        for (friend, events) in friendEvents { add(events, friend: friend) }
        return Array(result.values.sorted { $0.fireDate < $1.fireDate }.prefix(maxScheduled))
    }

    /// what to remove and add so the scheduled notifications match `planned`. Reminders on a friend's
    /// calendar that hasn't loaded (and old untagged friend ones) are left alone.
    static func reconcile(pending: [(identifier: String, userInfo: [AnyHashable: Any])], planned: [Planned],
                          loadedFriends: Set<String>) -> (remove: [String], add: [Planned]) {
        let iso = ISO8601DateFormatter()
        let wanted = Dictionary(planned.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        var remove: [String] = []
        var upToDate = Set<String>()
        for request in pending where request.identifier.hasPrefix(prefix) {
            if let friend = request.userInfo["friend"] as? String, !loadedFriends.contains(friend) { continue }
            if request.userInfo["navigateTo"] == nil && request.userInfo["friend"] == nil { continue } // older friend reminder
            if let want = wanted[request.identifier],
               request.userInfo["eventDate"] as? String == iso.string(from: want.start),
               request.userInfo["eventTitle"] as? String == want.title {
                upToDate.insert(request.identifier)
            } else {
                remove.append(request.identifier) // event gone, moved, renamed, or reminder turned off
            }
        }
        return (remove, planned.filter { !upToDate.contains($0.identifier) })
    }

    // MARK: - Scheduling

    @MainActor private static var lastOwn: [Event] = []
    @MainActor private static var lastFriends: [String: [Event]] = [:]

    /// Makes the scheduled notifications match the events (after each calendar load).
    @MainActor
    static func sync(ownEvents: [Event], friendEvents: [String: [Event]]) {
        lastOwn = ownEvents
        lastFriends = friendEvents
        let planned = planned(ownEvents: ownEvents, friendEvents: friendEvents)
        let loadedFriends = Set(friendEvents.keys)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let pending = requests.map { (identifier: $0.identifier, userInfo: $0.content.userInfo) }
            let change = reconcile(pending: pending, planned: planned, loadedFriends: loadedFriends)
            if !change.remove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: change.remove) }
            for item in change.add { center.add(request(for: item)) }
        }
    }

    /// again with the events from the last load (after a reminder choice changed)
    @MainActor
    static func refresh() {
        sync(ownEvents: lastOwn, friendEvents: lastFriends)
    }

    static func request(for item: Planned) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Event"
        content.body = body(title: item.title, secondsBefore: item.secondsBefore)
        content.sound = .default
        var info: [String: Any] = [
            "eventTitle": item.title,
            "eventDate": ISO8601DateFormatter().string(from: item.start),
            "navigateTo": "calendar",
            "secondsBefore": item.secondsBefore,
            "showDayView": item.secondsBefore < 24 * 60 * 60,
        ]
        if let friend = item.friend { info["friend"] = friend }
        content.userInfo = info
        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
        comps.second = 0
        return UNNotificationRequest(identifier: item.identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    /// seconds before the start → how it's described in the notification
    static func body(title: String, secondsBefore: TimeInterval) -> String {
        let name = title.isEmpty ? "Event" : title
        switch secondsBefore {
        case 0: return "\(name) is starting now!"
        case 15 * 60: return "\(name) starts in 15 minutes"
        case 60 * 60: return "\(name) starts in 1 hour"
        default: return "\(name) starts in 24 hours"
        }
    }

    /// The event was deleted: its reminders go now (not at the next load). With `series`, every
    /// date of a repeating event.
    static func cancel(eventId: String, series: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { identifier in
                guard let id = Self.eventId(fromIdentifier: identifier) else { return false }
                return id == eventId || (series && id.hasPrefix(eventId + "::"))
            }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        if series { UserDefaults.standard.removeObject(forKey: savedKey(eventId)) }
    }

    /// signing out: the next person on this phone shouldn't get these
    @MainActor
    static func removeAll() {
        lastOwn = []
        lastFriends = [:]
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("event_reminders_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
