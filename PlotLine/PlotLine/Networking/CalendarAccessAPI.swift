import Foundation

struct CalendarAccessAPI {

    static let base = BackendConfig.baseURLString

    // MARK: - Send invite
    static func sendInvite(from: String, to: String, level: String, requireApproval: Bool) async throws -> CalendarInvite {
        guard let url = URL(string: "\(base)/calendar-access/send-invite") else { throw URLError(.badURL) }
        let body: [String: Any] = [
            "fromUsername": from,
            "toUsername": to,
            "level": level,
            "requireApproval": requireApproval
        ]
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(CalendarInvite.self, from: data)
    }

    // MARK: - Respond to invite
    static func respondToInvite(recipient: String, inviteId: String, accept: Bool) async throws {
        guard let url = URL(string: "\(base)/calendar-access/respond-invite") else { throw URLError(.badURL) }
        let body: [String: Any] = ["recipientUsername": recipient, "inviteId": inviteId, "accept": accept]
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Get access data
    static func getAccessData(username: String) async throws -> CalendarAccessData {
        guard let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/calendar-access/data?username=\(encoded)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(CalendarAccessData.self, from: data)
    }

    // MARK: - Get shared events from a friend's calendar
    static func getSharedEvents(owner: String, requester: String) async throws -> [Event] {
        guard let ownerEnc = owner.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let requesterEnc = requester.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/calendar-access/shared-events?ownerUsername=\(ownerEnc)&requesterUsername=\(requesterEnc)")
        else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Event].self, from: data)
    }

    // MARK: - Approve a pending event
    static func approveEvent(owner: String, eventId: String) async throws {
        guard let url = URL(string: "\(base)/calendar-access/approve-event") else { throw URLError(.badURL) }
        let body: [String: Any] = ["ownerUsername": owner, "eventId": eventId]
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Reject a pending event
    static func rejectEvent(owner: String, eventId: String) async throws {
        guard let url = URL(string: "\(base)/calendar-access/reject-event") else { throw URLError(.badURL) }
        let body: [String: Any] = ["ownerUsername": owner, "eventId": eventId]
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Revoke access
    static func revokeAccess(owner: String, friend: String, keepEvents: Bool) async throws {
        guard let url = URL(string: "\(base)/calendar-access/revoke") else { throw URLError(.badURL) }
        let body: [String: Any] = ["ownerUsername": owner, "friendUsername": friend, "keepEvents": keepEvents]
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
