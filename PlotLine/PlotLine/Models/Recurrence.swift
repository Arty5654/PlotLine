//
//  Recurrence.swift
//  PlotLine
//
//  How a repeating event repeats, and the dates it happens on.
//
//  PlotLine's own events repeat by name ("daily", "weekdays", "weekly", "biweekly", "monthly",
//  "yearly"), optionally until a day. Events imported from Apple or Google Calendar can repeat in
//  more ways ("every 3 weeks on Mon and Wed", "the 2nd Tuesday", "10 times"); those keep the
//  standard rule text (RRULE, as Google sends it) in `recurrenceRule`.
//
//  A single changed or removed date is kept in the series' `excludedDates` ("yyyy-MM-dd"); a
//  changed date is then its own one-off event.
//

import Foundation

struct RecurrenceRule: Equatable {
    enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

    /// "the 2nd Tuesday" (ordinal 2, weekday 3) or "the last Friday" (ordinal -1); weekdays are
    /// Calendar weekdays, 1 = Sunday ... 7 = Saturday
    struct NthWeekday: Equatable {
        var ordinal: Int   // 0 = every one of that weekday
        var weekday: Int
    }

    var frequency: Frequency
    var interval: Int = 1
    var weekdays: [NthWeekday] = []   // BYDAY
    var monthDays: [Int] = []         // BYMONTHDAY (negative = from the end of the month)
    var months: [Int] = []            // BYMONTH
    var count: Int?                   // COUNT
    var until: Date?                  // UNTIL

    // MARK: - PlotLine's named repeats

    /// "weekly" and an optional last day → the rule. nil for "none" or an unknown name.
    static func named(_ recurrence: String, until: Date? = nil) -> RecurrenceRule? {
        var rule: RecurrenceRule
        switch recurrence {
        case "daily": rule = RecurrenceRule(frequency: .daily)
        case "weekdays": rule = RecurrenceRule(frequency: .weekly, weekdays: (2...6).map { NthWeekday(ordinal: 0, weekday: $0) })
        case "weekly": rule = RecurrenceRule(frequency: .weekly)
        case "biweekly": rule = RecurrenceRule(frequency: .weekly, interval: 2)
        case "monthly": rule = RecurrenceRule(frequency: .monthly)
        case "yearly": rule = RecurrenceRule(frequency: .yearly)
        default: return nil
        }
        rule.until = until
        return rule
    }

    /// the PlotLine name for a rule the editor can show, else nil ("custom")
    var name: String? {
        guard count == nil, monthDays.isEmpty, months.isEmpty else { return nil }
        let days = weekdays.map(\.weekday)
        guard weekdays.allSatisfy({ $0.ordinal == 0 }) else { return nil }
        switch (frequency, interval) {
        case (.daily, 1) where days.isEmpty: return "daily"
        case (.weekly, 1) where days == [2, 3, 4, 5, 6]: return "weekdays"
        case (.weekly, 1) where days.count <= 1: return "weekly"
        case (.weekly, 2) where days.count <= 1: return "biweekly"
        case (.monthly, 1) where days.isEmpty: return "monthly"
        case (.yearly, 1) where days.isEmpty: return "yearly"
        default: return nil
        }
    }

    // MARK: - RRULE text

    private static let dayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    /// "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T235959Z" (an optional "RRULE:" in front).
    /// nil when it uses parts PlotLine can't follow (then the dates are imported one by one).
    init?(rrule text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("RRULE:") { text = String(text.dropFirst(6)) }
        var parts: [String: String] = [:]
        for pair in text.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            parts[kv[0].uppercased()] = kv[1]
        }
        guard let freq = parts.removeValue(forKey: "FREQ").flatMap({ Frequency(rawValue: $0.uppercased()) }) else { return nil }
        self.frequency = freq
        parts.removeValue(forKey: "WKST") // week start: weeks follow the phone's calendar
        if let i = parts.removeValue(forKey: "INTERVAL") {
            guard let n = Int(i), n >= 1 else { return nil }
            interval = n
        }
        if let c = parts.removeValue(forKey: "COUNT") {
            guard let n = Int(c), n >= 1 else { return nil }
            count = n
        }
        if let u = parts.removeValue(forKey: "UNTIL") {
            guard let date = Self.parseUntil(u) else { return nil }
            until = date
        }
        if let days = parts.removeValue(forKey: "BYDAY") {
            for code in days.split(separator: ",") {
                let s = String(code).uppercased()
                guard s.count >= 2, let weekday = Self.dayCodes.firstIndex(of: String(s.suffix(2))) else { return nil }
                let prefix = s.dropLast(2)
                let ordinal = prefix.isEmpty ? 0 : Int(prefix) ?? 99
                guard abs(ordinal) <= 5 else { return nil }
                weekdays.append(NthWeekday(ordinal: ordinal, weekday: weekday + 1))
            }
        }
        if let days = parts.removeValue(forKey: "BYMONTHDAY") {
            for d in days.split(separator: ",") {
                guard let n = Int(d), n != 0, abs(n) <= 31 else { return nil }
                monthDays.append(n)
            }
        }
        if let ms = parts.removeValue(forKey: "BYMONTH") {
            for m in ms.split(separator: ",") {
                guard let n = Int(m), (1...12).contains(n) else { return nil }
                months.append(n)
            }
        }
        guard parts.isEmpty else { return nil } // BYSETPOS, BYHOUR, ...: not supported
        // "the 2nd Tuesday" only makes sense monthly or yearly
        if frequency == .daily, !weekdays.isEmpty || !monthDays.isEmpty { return nil }
        if frequency == .weekly, weekdays.contains(where: { $0.ordinal != 0 }) || !monthDays.isEmpty { return nil }
    }

    init(frequency: Frequency, interval: Int = 1, weekdays: [NthWeekday] = [], monthDays: [Int] = [],
         months: [Int] = [], count: Int? = nil, until: Date? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.months = months
        self.count = count
        self.until = until
    }

    var rrule: String {
        var parts = ["FREQ=\(frequency.rawValue)"]
        if interval != 1 { parts.append("INTERVAL=\(interval)") }
        if !weekdays.isEmpty {
            parts.append("BYDAY=" + weekdays.map { ($0.ordinal == 0 ? "" : "\($0.ordinal)") + Self.dayCodes[$0.weekday - 1] }.joined(separator: ","))
        }
        if !monthDays.isEmpty { parts.append("BYMONTHDAY=" + monthDays.map(String.init).joined(separator: ",")) }
        if !months.isEmpty { parts.append("BYMONTH=" + months.map(String.init).joined(separator: ",")) }
        if let count { parts.append("COUNT=\(count)") }
        if let until { parts.append("UNTIL=" + Self.untilFormatter.string(from: until)) }
        return parts.joined(separator: ";")
    }

    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    private static func parseUntil(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for (format, zone) in [("yyyyMMdd'T'HHmmss'Z'", TimeZone(identifier: "UTC")), ("yyyyMMdd'T'HHmmss", TimeZone.current)] {
            f.dateFormat = format
            f.timeZone = zone
            if let d = f.date(from: text) { return d }
        }
        // a plain day: the whole day counts
        f.dateFormat = "yyyyMMdd"
        f.timeZone = .current
        return f.date(from: text).flatMap { Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: $0) }
    }

    // MARK: - In words

    /// "Every week on Mon, Wed until Dec 31, 2026"
    var summary: String {
        let unit: String
        switch frequency {
        case .daily: unit = "day"
        case .weekly: unit = "week"
        case .monthly: unit = "month"
        case .yearly: unit = "year"
        }
        var text: String
        if name == "weekdays" {
            text = "Every weekday"
        } else {
            text = interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)s"
            if !weekdays.isEmpty {
                let symbols = Calendar.current.shortWeekdaySymbols
                let ordinals = [1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 5: "5th", -1: "last", -2: "2nd to last"]
                text += " on " + weekdays.map { day in
                    (day.ordinal == 0 ? "" : "the \(ordinals[day.ordinal] ?? "\(day.ordinal)th") ") + symbols[day.weekday - 1]
                }.joined(separator: ", ")
            }
            if !monthDays.isEmpty {
                text += " on day " + monthDays.map { $0 == -1 ? "last" : String($0) }.joined(separator: ", ")
            }
        }
        if let count { text += ", \(count) times" }
        if let until { text += " until \(until.formatted(date: .abbreviated, time: .omitted))" }
        return text
    }
}

enum Recurrence {

    /// "yyyy-MM-dd" in the phone's time zone: how a single date of a series is named
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The start times of a series from `start`, between `from` and `to`, skipping `excluded` days.
    /// Removed dates still count toward a "10 times" rule, as in Apple and Google Calendar.
    static func occurrences(start: Date, rule: RecurrenceRule, excluded: Set<String> = [],
                            from windowStart: Date, to windowEnd: Date,
                            calendar cal: Calendar = .current) -> [Date] {
        let time = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: start)
        let startDay = cal.startOfDay(for: start)
        let startComps = cal.dateComponents([.year, .month, .day, .weekday], from: start)

        func at(_ year: Int, _ month: Int, _ day: Int) -> Date? {
            var c = DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute,
                                   second: time.second, nanosecond: time.nanosecond)
            c.calendar = cal
            guard let date = cal.date(from: c),
                  cal.component(.month, from: date) == month else { return nil } // "Feb 30" doesn't exist
            return date
        }
        func daysIn(_ year: Int, _ month: Int) -> Int {
            let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
            return cal.range(of: .day, in: .month, for: first)?.count ?? 28
        }
        /// dates in a month for a weekday rule: "every Tuesday" (0), "the 2nd Tuesday" (2), "the last Friday" (-1)
        func weekdayDates(_ year: Int, _ month: Int, _ day: RecurrenceRule.NthWeekday) -> [Int] {
            let count = daysIn(year, month)
            let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
            let firstWeekday = cal.component(.weekday, from: first)
            let all = stride(from: 1 + (day.weekday - firstWeekday + 7) % 7, through: count, by: 7).map { $0 }
            if day.ordinal == 0 { return all }
            let index = day.ordinal > 0 ? day.ordinal - 1 : all.count + day.ordinal
            return all.indices.contains(index) ? [all[index]] : []
        }
        func monthDates(_ year: Int, _ month: Int) -> [Date] {
            var days: [Int] = []
            if !rule.weekdays.isEmpty {
                days = rule.weekdays.flatMap { weekdayDates(year, month, $0) }
            } else if !rule.monthDays.isEmpty {
                let count = daysIn(year, month)
                days = rule.monthDays.compactMap { $0 > 0 ? ($0 <= count ? $0 : nil) : count + $0 + 1 }
            } else {
                days = [startComps.day ?? 1]
            }
            return days.sorted().compactMap { at(year, month, $0) }
        }

        var result: [Date] = []
        var counted = 0
        let maxPeriods = 5000

        periods: for p in 0..<maxPeriods {
            var candidates: [Date] = []
            switch rule.frequency {
            case .daily:
                guard let day = cal.date(byAdding: .day, value: p * rule.interval, to: startDay) else { break periods }
                let c = cal.dateComponents([.year, .month, .day], from: day)
                if let d = at(c.year!, c.month!, c.day!) { candidates = [d] }
            case .weekly:
                guard let weekStart = cal.dateInterval(of: .weekOfYear, for: start)?.start,
                      let week = cal.date(byAdding: .weekOfYear, value: p * rule.interval, to: weekStart) else { break periods }
                let weekdays = rule.weekdays.isEmpty ? [startComps.weekday!] : rule.weekdays.map(\.weekday)
                candidates = weekdays
                    .map { (($0 - cal.firstWeekday) + 7) % 7 }
                    .sorted()
                    .compactMap { offset in
                        guard let day = cal.date(byAdding: .day, value: offset, to: week) else { return nil }
                        let c = cal.dateComponents([.year, .month, .day], from: day)
                        return at(c.year!, c.month!, c.day!)
                    }
            case .monthly:
                guard let month = cal.date(byAdding: .month, value: p * rule.interval,
                                           to: cal.date(from: DateComponents(year: startComps.year, month: startComps.month, day: 1))!) else { break periods }
                let c = cal.dateComponents([.year, .month], from: month)
                candidates = monthDates(c.year!, c.month!)
            case .yearly:
                let year = startComps.year! + p * rule.interval
                let months = rule.months.isEmpty ? [startComps.month!] : rule.months.sorted()
                candidates = months.flatMap { month -> [Date] in
                    if rule.weekdays.isEmpty && rule.monthDays.isEmpty { return at(year, month, startComps.day!).map { [$0] } ?? [] }
                    return monthDates(year, month)
                }
            }

            for date in candidates {
                if date < start { continue }                       // before the series begins
                if let until = rule.until, date > until { break periods }
                if let count = rule.count, counted >= count { break periods }
                counted += 1
                if date > windowEnd { break periods }
                if date >= windowStart, !excluded.contains(dayKey(date, calendar: cal)) { result.append(date) }
            }
        }
        return result
    }
}

// MARK: - Events

extension Event {

    /// how this event repeats; nil for a one-off (or a rule PlotLine can't follow)
    var repeatRule: RecurrenceRule? {
        if let text = recurrenceRule, !text.isEmpty { return RecurrenceRule(rrule: text) }
        return RecurrenceRule.named(recurrence, until: recurrenceEnd.flatMap(Self.endOfDay))
    }

    var isRepeating: Bool { repeatRule != nil || seriesId != nil }

    /// the series this date belongs to (itself for a one-off)
    var seriesKey: String { seriesId ?? id }

    /// from Apple or Google Calendar: those details are changed there, not here
    var importedFrom: String? {
        if id.hasPrefix("apple_") { return "Apple Calendar" }
        if id.hasPrefix("gcal_") { return "Google Calendar" }
        return nil
    }

    /// "2026-12-31" → the end of that day
    static func endOfDay(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: key) else { return nil }
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: day)
    }

    /// Each date of a repeating event between `from` and `to` (the event itself if it doesn't
    /// repeat). Every date gets its own id ("<series>::2026-10-12") and knows its series.
    func occurrences(from: Date, to: Date) -> [Event] {
        guard let rule = repeatRule else { return [self] }
        let duration = endDate.timeIntervalSince(startDate)
        return Recurrence.occurrences(start: startDate, rule: rule, excluded: Set(excludedDates), from: from, to: to)
            .map { date in
                var e = self
                e.id = date == startDate ? id : "\(id)::\(Recurrence.dayKey(date))"
                e.startDate = date
                e.endDate = date.addingTimeInterval(duration)
                e.seriesId = id
                e.occurrenceStart = date
                return e
            }
    }
}
