import Foundation
import GoogleSignIn

struct GoogleCalendarEvent {
    let id: String
    let title: String
    let description: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    var location: String? = nil
    var recurringEventId: String? = nil   // one date of a repeating event: the series' id
    var originalStart: Date? = nil        // where the series put this date (it may have been moved)
    var recurrence: [String] = []         // the series itself: "RRULE:FREQ=WEEKLY;BYDAY=MO", ...
    var calendarId: String = "primary"
}

struct GoogleCalendarAPI {

    static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"

    // Request the calendar scope (on top of existing auth) and return access token
    static func requestCalendarAccess() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleCalendarError.notSignedIn
        }

        // Refresh token first to make sure it's valid
        let refreshed = try await user.refreshTokensIfNeeded()

        // Check if calendar scope is already granted
        let grantedScopes = refreshed.grantedScopes ?? []
        if grantedScopes.contains(calendarScope) {
            return refreshed.accessToken.tokenString
        }

        // Request additional calendar scope
        guard let rootVC = await rootViewController() else {
            throw GoogleCalendarError.noRootViewController
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                GIDSignIn.sharedInstance.currentUser?.addScopes([calendarScope], presenting: rootVC) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let token = result?.user.accessToken.tokenString else {
                        continuation.resume(throwing: GoogleCalendarError.tokenMissing)
                        return
                    }
                    continuation.resume(returning: token)
                }
            }
        }
    }

    // Sign in fresh with calendar scope (for users not currently signed in via Google)
    static func signInWithCalendarScope() async throws -> String {
        guard let rootVC = await rootViewController() else {
            throw GoogleCalendarError.noRootViewController
        }

        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw GoogleCalendarError.missingClientID
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                GIDSignIn.sharedInstance.signIn(
                    withPresenting: rootVC,
                    hint: nil,
                    additionalScopes: [calendarScope]
                ) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let token = result?.user.accessToken.tokenString else {
                        continuation.resume(throwing: GoogleCalendarError.tokenMissing)
                        return
                    }
                    continuation.resume(returning: token)
                }
            }
        }
    }

    /// Events from every calendar shown in the person's Google Calendar: their own, and ones others
    /// shared with them (a friend's calendar). It used to read only the main ("primary") calendar.
    static func fetchEvents(accessToken: String, from startDate: Date, to endDate: Date) async throws -> [GoogleCalendarEvent] {
        let calendarIds = (try? await shownCalendarIds(accessToken: accessToken)) ?? ["primary"]
        var events: [GoogleCalendarEvent] = []
        var seen = Set<String>()
        for calendarId in calendarIds {
            let found: [GoogleCalendarEvent]
            do {
                found = try await fetchEvents(calendarId: calendarId, accessToken: accessToken, from: startDate, to: endDate)
            } catch {
                if calendarId == "primary" { throw error }
                continue // one shared calendar that can't be read shouldn't stop the rest
            }
            // an invitation from a friend is in their calendar and in yours: keep one
            for var event in found where seen.insert(event.id).inserted {
                event.calendarId = calendarId
                events.append(event)
            }
        }
        return events.sorted { $0.start < $1.start }
    }

    /// the calendars ticked in Google Calendar's list ("primary" first)
    static func shownCalendarIds(accessToken: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=freeBusyReader")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            throw GoogleCalendarError.apiError
        }
        return shownCalendarIds(in: items)
    }

    static func shownCalendarIds(in items: [[String: Any]]) -> [String] {
        var ids = ["primary"]
        for item in items {
            guard let id = item["id"] as? String,
                  (item["primary"] as? Bool) != true,       // already "primary"
                  (item["selected"] as? Bool) == true,      // ticked in Google Calendar
                  (item["hidden"] as? Bool) != true else { continue }
            ids.append(id)
        }
        return ids
    }

    private static func fetchEvents(calendarId: String, accessToken: String, from startDate: Date, to endDate: Date) async throws -> [GoogleCalendarEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? calendarId
        var events: [GoogleCalendarEvent] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events")!
            components.queryItems = [
                URLQueryItem(name: "timeMin", value: formatter.string(from: startDate)),
                URLQueryItem(name: "timeMax", value: formatter.string(from: endDate)),
                URLQueryItem(name: "maxResults", value: "500"),
                URLQueryItem(name: "singleEvents", value: "true"),  // expand recurring into instances
                URLQueryItem(name: "orderBy", value: "startTime")
            ]
            if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            guard let url = components.url else { throw GoogleCalendarError.invalidURL }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw GoogleCalendarError.apiError
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            events += (json["items"] as? [[String: Any]] ?? []).compactMap { parseEvent($0) }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil && events.count < 2500

        return events
    }

    static func parseEvent(_ item: [String: Any]) -> GoogleCalendarEvent? {
        guard let id = item["id"] as? String,
              let startRaw = item["start"] as? [String: Any],
              let endRaw = item["end"] as? [String: Any] else { return nil }

        // Skip cancelled events, and invitations you said no to (Google Calendar hides those too)
        if (item["status"] as? String) == "cancelled" { return nil }
        let attendees = item["attendees"] as? [[String: Any]] ?? []
        if attendees.contains(where: { ($0["self"] as? Bool) == true && ($0["responseStatus"] as? String) == "declined" }) {
            return nil
        }

        // a calendar shared as "free/busy only" (or an untitled event) has no title: it was skipped before
        let title = (item["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = title?.isEmpty == false ? title! : "Busy"
        let location = (item["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let description = item["description"] as? String ?? ""

        guard let (start, isAllDay) = time(startRaw), var (end, _) = time(endRaw) else { return nil }
        if isAllDay { end = end.addingTimeInterval(-1) } // Google's all-day end is the next day

        return GoogleCalendarEvent(id: id, title: summary, description: description,
                                   start: start, end: end, isAllDay: isAllDay,
                                   location: location?.isEmpty == false ? location : nil,
                                   recurringEventId: item["recurringEventId"] as? String,
                                   originalStart: (item["originalStartTime"] as? [String: Any]).flatMap(time)?.date,
                                   recurrence: item["recurrence"] as? [String] ?? [])
    }

    /// {"dateTime": "2026-10-12T15:00:00-04:00"} or {"date": "2026-10-12"} (all day)
    static func time(_ raw: [String: Any]) -> (date: Date, isAllDay: Bool)? {
        if let day = raw["date"] as? String {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone.current
            return df.date(from: day).map { ($0, true) }
        }
        guard let text = raw["dateTime"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return (date, false) }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text).map { ($0, false) }
    }

    // MARK: - As PlotLine events

    /// Google's events as PlotLine events. A repeating event comes from Google as each of its dates;
    /// it's one repeating PlotLine event again (dates changed in Google stay their own events).
    static func plotLineEvents(accessToken: String, from startDate: Date, to endDate: Date) async throws -> [Event] {
        let dates = try await fetchEvents(accessToken: accessToken, from: startDate, to: endDate)
        var events = dates.filter { $0.recurringEventId == nil }.map { oneOff($0) }
        let bySeries = Dictionary(grouping: dates.filter { $0.recurringEventId != nil }, by: { $0.recurringEventId! })
        for (seriesId, group) in bySeries {
            if let master = try? await fetchEvent(id: seriesId, calendarId: group[0].calendarId, accessToken: accessToken),
               let series = series(master) {
                events += ImportedSeries.events(series: series, instances: group.map(instance), window: (startDate, endDate))
            } else {
                events += group.map { oneOff($0) }
            }
        }
        return events.sorted { $0.startDate < $1.startDate }
    }

    /// the repeating event behind a set of dates, if its rule is one PlotLine can follow
    static func series(_ master: GoogleCalendarEvent) -> ImportedSeries.Series? {
        let rules = master.recurrence.filter { $0.uppercased().hasPrefix("RRULE:") }
        guard rules.count == 1, let rule = RecurrenceRule(rrule: rules[0]) else { return nil }
        return ImportedSeries.Series(id: "gcal_\(master.id)", start: master.start, end: master.end, rule: rule,
                                     title: master.title, description: master.description, location: master.location)
    }

    static func instance(_ e: GoogleCalendarEvent) -> ImportedSeries.Instance {
        ImportedSeries.Instance(id: "gcal_\(e.id)", start: e.start, end: e.end, originalStart: e.originalStart ?? e.start,
                                title: e.title, description: e.description, location: e.location)
    }

    static func oneOff(_ e: GoogleCalendarEvent) -> Event {
        Event(id: "gcal_\(e.id)", title: e.title, description: e.description, startDate: e.start, endDate: e.end,
              eventType: "user", recurrence: "none", invitedFriends: [], location: e.location)
    }

    private static func fetchEvent(id: String, calendarId: String, accessToken: String) async throws -> GoogleCalendarEvent? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let cal = calendarId.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendarId
        let event = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(cal)/events/\(event)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseEvent(json)
    }

    @MainActor
    private static func rootViewController() -> UIViewController? {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow?
            .rootViewController else { return nil }

        // Walk to topmost presented VC — required when this is called from inside a sheet
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

enum GoogleCalendarError: LocalizedError {
    case notSignedIn, noRootViewController, tokenMissing, missingClientID, invalidURL, apiError

    var errorDescription: String? {
        switch self {
        case .notSignedIn:          return "Not signed in with Google"
        case .noRootViewController: return "Could not present sign-in screen"
        case .tokenMissing:         return "Google access token unavailable"
        case .missingClientID:      return "Google Client ID not configured"
        case .invalidURL:           return "Invalid Google Calendar URL"
        case .apiError:             return "Google Calendar API error"
        }
    }
}
