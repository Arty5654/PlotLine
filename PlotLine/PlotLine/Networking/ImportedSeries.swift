//
//  ImportedSeries.swift
//  PlotLine
//
//  Apple and Google Calendar hand over a repeating event as its separate dates. PlotLine used to
//  save each date as its own event, so a weekly class showed up as 26 unrelated events. Now the
//  dates become one repeating event again, using the series' rule; a date changed there (another
//  time or title) becomes its own one-off event, and a date deleted there is left out.
//

import Foundation

enum ImportedSeries {

    /// one date of a repeating event as Apple or Google gives it
    struct Instance {
        let id: String              // its own PlotLine id, used if it becomes a one-off event
        let start: Date
        let end: Date
        let originalStart: Date     // where the series put it (differs when moved)
        let title: String
        let description: String
        let location: String?
    }

    /// the series itself
    struct Series {
        let id: String              // PlotLine id for the whole series ("gcal_<id>", "apple_<id>")
        let start: Date             // its first date ever
        let end: Date
        let rule: RecurrenceRule
        let title: String
        let description: String
        let location: String?
    }

    /// The repeating event plus a one-off event for each changed date. `window` is the range the
    /// dates were read for: the series starts at its first date there.
    static func events(series: Series, instances: [Instance], window: (from: Date, to: Date)) -> [Event] {
        let expected = Recurrence.occurrences(start: series.start, rule: series.rule, from: window.from, to: window.to)
        guard let anchor = expected.first else { return instances.map(oneOff) }

        // start at the first date in the window; "10 times" becomes "until the 10th date" so
        // starting later doesn't make it longer
        var rule = series.rule
        if rule.count != nil {
            let all = Recurrence.occurrences(start: series.start, rule: series.rule, from: .distantPast, to: .distantFuture)
            rule.count = nil
            rule.until = all.last
        }
        let duration = series.end.timeIntervalSince(series.start)
        let expectedByDay = Dictionary(expected.map { (Recurrence.dayKey($0), $0) }, uniquingKeysWith: { first, _ in first })

        var matched = Set<String>()
        var oneOffs: [Event] = []
        for instance in instances {
            let day = Recurrence.dayKey(instance.originalStart)
            guard let planned = expectedByDay[day] else {
                oneOffs.append(oneOff(instance)) // a date the rule doesn't explain
                continue
            }
            matched.insert(day)
            let unchanged = abs(instance.start.timeIntervalSince(planned)) < 60
                && abs(instance.end.timeIntervalSince(instance.start) - duration) < 60
                && instance.title == series.title
                && instance.description == series.description
                && (instance.location ?? "") == (series.location ?? "")
            if !unchanged { oneOffs.append(oneOff(instance)) }
        }
        // changed dates are one-off events now; dates with nothing are the ones deleted there
        let changedDays = Set(oneOffs.compactMap { e in
            instances.first { $0.id == e.id }.map { Recurrence.dayKey($0.originalStart) }
        })
        let excluded = expected.map { Recurrence.dayKey($0) }
            .filter { !matched.contains($0) || changedDays.contains($0) }

        let repeating = Event(id: series.id, title: series.title, description: series.description,
                              startDate: anchor, endDate: anchor.addingTimeInterval(duration),
                              eventType: "user", recurrence: rule.name ?? "custom", invitedFriends: [],
                              location: series.location, recurrenceRule: rule.rrule,
                              excludedDates: Array(Set(excluded)).sorted())
        return [repeating] + oneOffs
    }

    static func oneOff(_ instance: Instance) -> Event {
        Event(id: instance.id, title: instance.title, description: instance.description,
              startDate: instance.start, endDate: instance.end,
              eventType: "user", recurrence: "none", invitedFriends: [], location: instance.location)
    }

    /// how far ahead and back Apple and Google Calendar are read (and shown)
    static func window(now: Date = Date()) -> (from: Date, to: Date) {
        let cal = Calendar.current
        return (cal.date(byAdding: .month, value: -1, to: now)!, cal.date(byAdding: .year, value: 1, to: now)!)
    }
}
