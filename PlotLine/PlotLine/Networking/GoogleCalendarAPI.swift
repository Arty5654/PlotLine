import Foundation
import GoogleSignIn

struct GoogleCalendarEvent {
    let id: String
    let title: String
    let description: String
    let start: Date
    let end: Date
    let isAllDay: Bool
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

    // Fetch events from primary calendar for a date range
    static func fetchEvents(accessToken: String, from startDate: Date, to endDate: Date) async throws -> [GoogleCalendarEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let timeMin = formatter.string(from: startDate)
        let timeMax = formatter.string(from: endDate)

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "maxResults", value: "500"),
            URLQueryItem(name: "singleEvents", value: "true"),  // expand recurring into instances
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        guard let url = components.url else { throw GoogleCalendarError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GoogleCalendarError.apiError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { parseEvent($0) }
    }

    private static func parseEvent(_ item: [String: Any]) -> GoogleCalendarEvent? {
        guard let id = item["id"] as? String,
              let summary = item["summary"] as? String,
              let startRaw = item["start"] as? [String: Any],
              let endRaw = item["end"] as? [String: Any] else { return nil }

        // Skip cancelled events
        if (item["status"] as? String) == "cancelled" { return nil }

        let description = item["description"] as? String ?? ""

        // Determine if all-day (uses "date") or timed (uses "dateTime")
        let isAllDay: Bool
        let start: Date
        let end: Date

        if let dateStr = startRaw["date"] as? String,
           let endStr = endRaw["date"] as? String {
            isAllDay = true
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone.current
            guard let s = df.date(from: dateStr), let e = df.date(from: endStr) else { return nil }
            start = s
            // Google all-day end is exclusive, subtract one second
            end = e.addingTimeInterval(-1)
        } else if let dtStr = startRaw["dateTime"] as? String,
                  let endStr = endRaw["dateTime"] as? String {
            isAllDay = false
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var s = formatter.date(from: dtStr)
            var e = formatter.date(from: endStr)
            if s == nil {
                formatter.formatOptions = [.withInternetDateTime]
                s = formatter.date(from: dtStr)
                e = formatter.date(from: endStr)
            }
            guard let s, let e else { return nil }
            start = s; end = e
        } else {
            return nil
        }

        return GoogleCalendarEvent(id: id, title: summary, description: description,
                                   start: start, end: end, isAllDay: isAllDay)
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
