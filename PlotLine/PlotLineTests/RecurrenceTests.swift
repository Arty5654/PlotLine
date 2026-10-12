//
//  RecurrenceTests.swift
//  PlotLineTests
//
//  Repeating events: which dates they happen on.
//

import Testing
import Foundation
@testable import PlotLine

struct RecurrenceTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func days(_ dates: [Date]) -> [String] { dates.map { Recurrence.dayKey($0, calendar: cal) } }

    private func run(_ rule: RecurrenceRule, from start: Date, until end: Date, excluded: Set<String> = []) -> [String] {
        days(Recurrence.occurrences(start: start, rule: rule, excluded: excluded, from: start, to: end, calendar: cal))
    }

    @Test("Every week, every other week, and a removed date")
    func weekly() {
        let start = date(2026, 10, 12) // a Monday
        #expect(run(.named("weekly")!, from: start, until: date(2026, 11, 2)) == ["2026-10-12", "2026-10-19", "2026-10-26", "2026-11-02"])
        #expect(run(.named("biweekly")!, from: start, until: date(2026, 11, 9)) == ["2026-10-12", "2026-10-26", "2026-11-09"])
        #expect(run(.named("weekly")!, from: start, until: date(2026, 10, 26), excluded: ["2026-10-19"]) == ["2026-10-12", "2026-10-26"])
    }

    @Test("Every Year works (it used to freeze the app) and keeps the time of day")
    func yearly() {
        let start = date(2026, 3, 5, 14)
        let dates = Recurrence.occurrences(start: start, rule: .named("yearly")!, from: start, to: date(2029, 12, 31), calendar: cal)
        #expect(days(dates) == ["2026-03-05", "2027-03-05", "2028-03-05", "2029-03-05"])
        #expect(dates.allSatisfy { cal.component(.hour, from: $0) == 14 })
    }

    @Test("Every day and every weekday; an end date stops it")
    func dailyAndWeekdays() {
        let fri = date(2026, 10, 16)
        #expect(run(.named("weekdays")!, from: fri, until: date(2026, 10, 21)) == ["2026-10-16", "2026-10-19", "2026-10-20", "2026-10-21"])
        #expect(run(.named("daily", until: date(2026, 10, 18, 23))!, from: fri, until: date(2026, 12, 1)) == ["2026-10-16", "2026-10-17", "2026-10-18"])
    }

    @Test("Monthly on the 31st skips shorter months")
    func monthly31st() {
        #expect(run(.named("monthly")!, from: date(2026, 1, 31), until: date(2026, 5, 31)) == ["2026-01-31", "2026-03-31", "2026-05-31"])
    }

    @Test("Imported rules: every 3 weeks on Mon and Wed, 5 times; the 2nd Tuesday; the last Friday")
    func importedRules() throws {
        let start = date(2026, 10, 12)
        let threeWeeks = try #require(RecurrenceRule(rrule: "RRULE:FREQ=WEEKLY;INTERVAL=3;BYDAY=MO,WE;COUNT=5"))
        #expect(run(threeWeeks, from: start, until: date(2027, 6, 1)) == ["2026-10-12", "2026-10-14", "2026-11-02", "2026-11-04", "2026-11-23"])

        let secondTuesday = try #require(RecurrenceRule(rrule: "FREQ=MONTHLY;BYDAY=2TU"))
        #expect(run(secondTuesday, from: date(2026, 10, 13), until: date(2026, 12, 31)) == ["2026-10-13", "2026-11-10", "2026-12-08"])

        let lastFriday = try #require(RecurrenceRule(rrule: "FREQ=MONTHLY;BYDAY=-1FR;UNTIL=20261130T000000Z"))
        #expect(run(lastFriday, from: date(2026, 10, 30), until: date(2027, 3, 1)) == ["2026-10-30", "2026-11-27"])
    }

    @Test("Rules PlotLine can't follow aren't guessed at")
    func unsupported() {
        #expect(RecurrenceRule(rrule: "FREQ=MONTHLY;BYDAY=MO,TU;BYSETPOS=-1") == nil)
        #expect(RecurrenceRule(rrule: "FREQ=HOURLY") == nil)
        #expect(RecurrenceRule(rrule: "FREQ=WEEKLY;BYDAY=MO,WE")?.name == nil)        // custom
        #expect(RecurrenceRule(rrule: "FREQ=WEEKLY;INTERVAL=2")?.name == "biweekly")
        #expect(RecurrenceRule(rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")?.name == "weekdays")
    }

    @Test("Each date of a series has its own id and knows its series")
    func eventOccurrences() {
        let start = Date(timeIntervalSinceNow: 3600)
        let event = Event(id: "abc", title: "Gym", description: "", startDate: start, endDate: start.addingTimeInterval(3600),
                          eventType: "user", recurrence: "weekly", invitedFriends: [])
        let dates = event.occurrences(from: start.addingTimeInterval(-60), to: start.addingTimeInterval(15 * 86400))
        #expect(dates.count == 3)
        #expect(dates[0].id == "abc")
        #expect(dates[1].id == "abc::" + Recurrence.dayKey(dates[1].startDate))
        #expect(Set(dates.map(\.id)).count == 3)
        #expect(dates.allSatisfy { $0.seriesKey == "abc" && $0.endDate.timeIntervalSince($0.startDate) == 3600 })

        let once = Event(id: "x", title: "Once", description: "", startDate: start, endDate: start,
                         eventType: "user", recurrence: "none", invitedFriends: [])
        #expect(once.occurrences(from: .distantPast, to: .distantFuture).map(\.id) == ["x"])
        #expect(!once.isRepeating)
    }
}

/// Repeating events from Apple/Google Calendar become one series again.
struct ImportedSeriesTests {
    private func at(_ day: Int, _ hour: Int = 18) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func instance(_ day: Int, hour: Int = 18, originalDay: Int? = nil, title: String = "Soccer") -> ImportedSeries.Instance {
        ImportedSeries.Instance(id: "apple_x_\(day)", start: at(day, hour), end: at(day, hour + 1),
                                originalStart: at(originalDay ?? day), title: title, description: "", location: "Field 3")
    }

    @Test("Weekly dates become one weekly event; a moved date is its own event and a deleted date is left out")
    func collapse() throws {
        // every Monday from Sep 7; in the window: Oct 5, 12, 19, 26
        let series = ImportedSeries.Series(id: "apple_x", start: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 18))!,
                                           end: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 19))!,
                                           rule: try #require(RecurrenceRule(rrule: "FREQ=WEEKLY")), title: "Soccer", description: "", location: "Field 3")
        let window = (from: at(1), to: at(31))
        let events = ImportedSeries.events(series: series, instances: [
            instance(5),
            instance(12, hour: 20),        // moved to 8pm
            // Oct 19 deleted in Apple Calendar
            instance(26),
        ], window: window)

        let repeating = try #require(events.first { $0.id == "apple_x" })
        #expect(repeating.startDate == at(5))                 // starts at its first date in the window
        #expect(repeating.recurrence == "weekly")
        #expect(repeating.location == "Field 3")
        #expect(repeating.excludedDates == ["2026-10-12", "2026-10-19"])
        let moved = try #require(events.first { $0.id == "apple_x_12" })
        #expect(moved.startDate == at(12, 20) && moved.recurrence == "none")

        // what the calendar shows: Oct 5, the moved Oct 12 at 8pm, Oct 26
        let shown = events.flatMap { $0.occurrences(from: window.from, to: window.to) }.map(\.startDate).sorted()
        #expect(shown == [at(5), at(12, 20), at(26)])
    }

    @Test("A rule PlotLine can't follow keeps the dates as separate events (as before)")
    func unsupportedStaysSeparate() {
        let events = ImportedSeries.events(
            series: ImportedSeries.Series(id: "apple_y", start: at(1), end: at(1, 19),
                                          rule: RecurrenceRule(frequency: .weekly), title: "Class", description: "", location: nil),
            instances: [instance(3, title: "Class")], window: (from: at(10), to: at(10, 20)))
        #expect(events.map(\.id) == ["apple_x_3"])
    }

    @Test("Google: a series is built from its RRULE line")
    func googleSeries() throws {
        let master = GoogleCalendarEvent(id: "abc", title: "Standup", description: "", start: at(12, 9), end: at(12, 10),
                                         isAllDay: false, recurrence: ["EXDATE;TZID=America/New_York:20261014T090000", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"])
        let series = try #require(GoogleCalendarAPI.series(master))
        #expect(series.id == "gcal_abc")
        #expect(series.rule.weekdays.map(\.weekday) == [2, 4, 6])
        let item: [String: Any] = ["id": "abc_20261014T130000Z", "summary": "Standup", "recurringEventId": "abc",
                                   "start": ["dateTime": "2026-10-14T13:00:00Z"], "end": ["dateTime": "2026-10-14T14:00:00Z"],
                                   "originalStartTime": ["dateTime": "2026-10-14T13:00:00Z"]]
        let parsed = try #require(GoogleCalendarAPI.parseEvent(item))
        #expect(parsed.recurringEventId == "abc")
        #expect(parsed.originalStart == parsed.start)
    }
}

/// Editing a repeating event "for all events".
struct SeriesEditTests {
    private func at(_ day: Int, _ hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private var series: Event {
        Event(id: "s", title: "Gym", description: "", startDate: at(5, 7), endDate: at(5, 8),
              eventType: "user", recurrence: "weekly", invitedFriends: [], excludedDates: ["2026-10-19"])
    }

    @Test("Moving one date's time to 8am moves every date; removed dates stay removed")
    func newTime() {
        var edited = series
        edited.startDate = at(12, 8)
        edited.endDate = at(12, 9)
        let updated = CalendarViewModel.seriesAfterEdit(series: series, occurrenceStart: at(12, 7), edited: edited)
        #expect(updated.id == "s")
        #expect(updated.startDate == at(5, 8) && updated.endDate == at(5, 9))
        #expect(updated.excludedDates.isEmpty) // the dates moved, so old removals no longer line up

        var renamed = series
        renamed.title = "Gym class"
        renamed.startDate = at(12, 7)
        renamed.endDate = at(12, 8)
        let same = CalendarViewModel.seriesAfterEdit(series: series, occurrenceStart: at(12, 7), edited: renamed)
        #expect(same.title == "Gym class" && same.startDate == at(5, 7) && same.excludedDates == ["2026-10-19"])
    }

    @Test("Turning off repeat leaves a single event on the date being edited")
    func stopRepeating() {
        var edited = series
        edited.recurrence = "none"
        edited.startDate = at(12, 7)
        edited.endDate = at(12, 8)
        let updated = CalendarViewModel.seriesAfterEdit(series: series, occurrenceStart: at(12, 7), edited: edited)
        #expect(updated.startDate == at(12, 7) && !updated.isRepeating)
    }
}

/// Reminders follow their event: every date of a repeating one, gone when it's gone, moved when it moves.
struct EventReminderSyncTests {
    private let iso = ISO8601DateFormatter()
    private let now = Date()

    private func event(_ id: String, inHours hours: Double, title: String = "Dinner") -> Event {
        let start = now.addingTimeInterval(hours * 3600)
        return Event(id: id, title: title, description: "", startDate: start, endDate: start, eventType: "user", recurrence: "none", invitedFriends: [])
    }

    @Test("Reminders on a repeating event (here from Apple and from Google) go on every upcoming date, not just one")
    func everyDate() {
        let window = (from: now, to: now.addingTimeInterval(400 * 86400))
        for id in ["apple_soccer", "gcal_standup", "mine"] {
            let weekly = Event(id: id, title: "Soccer", description: "", startDate: now.addingTimeInterval(3600),
                               endDate: now.addingTimeInterval(7200), eventType: "user", recurrence: "custom", invitedFriends: [],
                               recurrenceRule: "FREQ=WEEKLY")
            let dates = weekly.occurrences(from: window.from, to: window.to)
            // the choice was made while one date was open: it's the series' choice
            let planned = EventReminders.planned(ownEvents: dates, friendEvents: [:],
                                                 offsets: { $0.seriesKey == id ? [15 * 60] : [] }, now: now)
            #expect(planned.count == 7)  // the next 45 days: 7 Mondays
            #expect(Set(planned.map(\.eventId)).count == 7)
            #expect(planned.allSatisfy { $0.secondsBefore == 15 * 60 })
        }
    }

    @Test("Only reminders still ahead, soonest first, at most 40")
    func limits() {
        let daily = Event(id: "d", title: "Pills", description: "", startDate: now.addingTimeInterval(600), endDate: now.addingTimeInterval(600),
                          eventType: "user", recurrence: "daily", invitedFriends: [])
        let dates = daily.occurrences(from: now, to: now.addingTimeInterval(100 * 86400))
        let planned = EventReminders.planned(ownEvents: dates, friendEvents: [:], offsets: { _ in [0, 15 * 60, 60 * 60] }, now: now)
        #expect(planned.count == EventReminders.maxScheduled)
        #expect(!planned.contains { $0.eventId == "d" && $0.secondsBefore >= 15 * 60 }) // the first date's 15 min / 1 h reminders already passed
        #expect(planned.map(\.fireDate) == planned.map(\.fireDate).sorted())
    }

    @Test("A deleted event's reminders go; a moved or renamed one is redone; friends' are left alone unless loaded")
    func reconcile() {
        let kept = event("kept", inHours: 30)
        let moved = event("moved", inHours: 31)
        let planned = EventReminders.planned(ownEvents: [kept, moved], friendEvents: ["sam": []], offsets: { _ in [15 * 60] }, now: now)
        let at = { (hours: Double) in self.iso.string(from: self.now.addingTimeInterval(hours * 3600)) }
        let pending: [(identifier: String, userInfo: [AnyHashable: Any])] = [
            ("reminder_kept_900", ["navigateTo": "calendar", "eventDate": at(30), "eventTitle": "Dinner"]),
            ("reminder_deleted_900", ["navigateTo": "calendar", "eventDate": at(30), "eventTitle": "Lunch"]),
            ("reminder_moved_900", ["navigateTo": "calendar", "eventDate": at(20), "eventTitle": "Dinner"]),
            ("reminder_party_900", ["navigateTo": "calendar", "friend": "sam", "eventDate": at(5), "eventTitle": "Party"]),
            ("reminder_game_900", ["navigateTo": "calendar", "friend": "lee", "eventDate": at(5), "eventTitle": "Game"]),
            ("reminder_legacyFriend_900", [:]),
            ("goal_reminder_1", [:]),
        ]
        let change = EventReminders.reconcile(pending: pending, planned: planned, loadedFriends: ["sam"])
        #expect(Set(change.remove) == ["reminder_deleted_900", "reminder_moved_900", "reminder_party_900"])
        #expect(change.add.map(\.identifier) == ["reminder_moved_900"])
        #expect(EventReminders.eventId(fromIdentifier: "reminder_abc::2026-10-12_900") == "abc::2026-10-12")
        #expect(EventReminders.eventId(fromIdentifier: "reminder_apple_X_1760000000_0") == "apple_X_1760000000")
    }
}
