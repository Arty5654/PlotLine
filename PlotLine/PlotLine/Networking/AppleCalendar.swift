//
//  AppleCalendar.swift
//  PlotLine
//
//  Reads the phone's calendars with EventKit: Apple Calendar (iCloud), plus any other accounts
//  added in iPhone Settings (Google, Outlook...). Import only: PlotLine never changes them.
//  The calendars the user picked are remembered per PlotLine account on this phone.
//

import EventKit
import UIKit

enum AppleCalendar {
    static let store = EKEventStore()

    /// imported events are stored as "apple_<calendar item>_<start time>", so the server can replace them all at once
    static let idPrefix = "apple_"

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// the person said no (or a parent/MDM blocked it): only iPhone Settings can change that
    static var accessDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted || status == .writeOnly
    }

    static func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    // MARK: - Chosen calendars

    private static func selectionKey(_ username: String) -> String { "appleCalendarIDs.\(username.lowercased())" }

    /// the calendars this account imports; empty means Apple Calendar isn't connected
    static func selectedCalendarIDs(for username: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: selectionKey(username)) ?? [])
    }

    static func setSelectedCalendarIDs(_ ids: Set<String>, for username: String) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: selectionKey(username))
        } else {
            UserDefaults.standard.set(Array(ids), forKey: selectionKey(username))
        }
    }

    static func isConnected(for username: String) -> Bool {
        hasAccess && !selectedCalendarIDs(for: username).isEmpty
    }

    // MARK: - Calendars and events

    /// the phone's event calendars, grouped by account (iCloud, Gmail, ...), in a stable order
    static func calendarsByAccount() -> [(account: String, calendars: [EKCalendar])] {
        let grouped = Dictionary(grouping: store.calendars(for: .event)) { $0.source?.title ?? "Other" }
        return grouped
            .map { (account: $0.key, calendars: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.account.localizedCaseInsensitiveCompare($1.account) == .orderedAscending }
    }

    /// Ticked the first time: the person's own calendars. Off: birthdays, holidays and other
    /// subscriptions, and Google calendars when Google is already linked in PlotLine (they'd show twice).
    static func isOnByDefault(_ calendar: EKCalendar, googleLinked: Bool) -> Bool {
        switch calendar.type {
        case .birthday, .subscription: return false
        default: break
        }
        if googleLinked, isGoogleAccount(calendar) { return false }
        return true
    }

    static func isGoogleAccount(_ calendar: EKCalendar) -> Bool {
        let account = (calendar.source?.title ?? "").lowercased()
        return account.contains("gmail") || account.contains("google")
    }

    /// Events from the chosen calendars, one per occurrence (repeating events are expanded),
    /// from a month ago to six months ahead: the same window as Google Calendar sync.
    static func events(for username: String, now: Date = Date()) -> [Event] {
        let chosen = selectedCalendarIDs(for: username)
        let calendars = store.calendars(for: .event).filter { chosen.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let cal = Calendar.current
        let from = cal.date(byAdding: .month, value: -1, to: now)!
        let to = cal.date(byAdding: .month, value: 6, to: now)!
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)

        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { e in
                let title = e.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Event(id: "\(idPrefix)\(e.calendarItemIdentifier)_\(Int(e.startDate.timeIntervalSince1970))",
                             title: title.isEmpty ? "Untitled event" : title,
                             description: e.notes ?? "",
                             startDate: e.startDate, endDate: e.endDate,
                             eventType: "user", recurrence: "none", invitedFriends: [])
            }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
