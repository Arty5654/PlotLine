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

    /// Events from the chosen calendars, from a month ago to a year ahead (the same window as Google
    /// Calendar sync). A repeating event is one repeating PlotLine event, not one event per date.
    static func events(for username: String, now: Date = Date()) -> [Event] {
        let chosen = selectedCalendarIDs(for: username)
        let calendars = store.calendars(for: .event).filter { chosen.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let window = ImportedSeries.window(now: now)
        let predicate = store.predicateForEvents(withStart: window.from, end: window.to, calendars: calendars)
        let dates = store.events(matching: predicate).filter { $0.status != .canceled }

        // a repeating event comes back as each of its dates: put them back together as one series
        var events: [Event] = []
        for (itemId, group) in Dictionary(grouping: dates, by: \.calendarItemIdentifier) {
            let instances = group.map(instance)
            if let sample = group.first(where: { !$0.isDetached }) ?? group.first,
               let rules = sample.recurrenceRules, rules.count == 1,
               let rule = Self.rule(from: rules[0]),
               let first = sample.eventIdentifier.flatMap({ store.event(withIdentifier: $0) }) {  // the series' first date
                let series = ImportedSeries.Series(id: "\(idPrefix)\(itemId)", start: first.startDate, end: first.endDate,
                                                   rule: rule, title: title(of: first), description: first.notes ?? "",
                                                   location: Self.location(of: first))
                events += ImportedSeries.events(series: series, instances: instances, window: window)
            } else {
                events += instances.map(ImportedSeries.oneOff)
            }
        }
        return events.sorted { $0.startDate < $1.startDate }
    }

    private static func title(of e: EKEvent) -> String {
        let title = e.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled event" : title
    }

    private static func instance(_ e: EKEvent) -> ImportedSeries.Instance {
        ImportedSeries.Instance(id: "\(idPrefix)\(e.calendarItemIdentifier)_\(Int(e.startDate.timeIntervalSince1970))",
                                start: e.startDate, end: e.endDate,
                                originalStart: e.occurrenceDate ?? e.startDate,
                                title: title(of: e), description: e.notes ?? "", location: location(of: e))
    }

    /// Apple's repeat rule as PlotLine's; nil for the few it can't follow (e.g. "the last weekday of the month")
    static func rule(from r: EKRecurrenceRule) -> RecurrenceRule? {
        if let positions = r.setPositions, !positions.isEmpty { return nil }
        if let weeks = r.weeksOfTheYear, !weeks.isEmpty { return nil }
        if let days = r.daysOfTheYear, !days.isEmpty { return nil }
        let frequency: RecurrenceRule.Frequency
        switch r.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }
        let rule = RecurrenceRule(
            frequency: frequency,
            interval: max(1, r.interval),
            weekdays: (r.daysOfTheWeek ?? []).map { .init(ordinal: $0.weekNumber, weekday: $0.dayOfTheWeek.rawValue) },
            monthDays: (r.daysOfTheMonth ?? []).map(\.intValue),
            months: (r.monthsOfTheYear ?? []).map(\.intValue),
            count: r.recurrenceEnd.flatMap { $0.occurrenceCount > 0 ? $0.occurrenceCount : nil },
            until: r.recurrenceEnd?.endDate)
        // the same checks as a Google rule
        return RecurrenceRule(rrule: rule.rrule)
    }

    /// the event's place: "Starbucks\n123 Main St" → "Starbucks, 123 Main St"
    static func location(of event: EKEvent) -> String? {
        let text = (event.location ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: ", ")
        return text.isEmpty ? nil : text
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
