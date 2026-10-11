//
//  GoalsAPI.swift
//  PlotLine
//
//  Weekly and long-term goal requests. All of them throw on failure so callers can show the
//  error banner and keep what the person typed.
//

import Foundation

enum GoalsAPI {
    private static var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(GoalReminder.dayFormatter) // the server expects "yyyy-MM-dd"
        return encoder
    }()

    private static func send(_ method: String, _ path: String, body: some Encodable) async throws {
        try await send(method, path, data: try encoder.encode(body))
    }

    private static func send(_ method: String, _ path: String, data: Data? = nil) async throws {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        BackendConfig.addApiKey(to: &request)
        if let data {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Weekly

    static func addWeekly(_ goal: TaskItem) async throws { try await send("POST", "", body: goal) }
    static func updateWeekly(_ goal: TaskItem) async throws { try await send("PUT", "/\(goal.id)", body: goal) }
    static func deleteWeekly(_ id: Int) async throws { try await send("DELETE", "/\(id)") }
    static func resetWeekly() async throws { try await send("DELETE", "/reset") }
    /// also checks off the long-term step it was made from (the server does it)
    static func setWeeklyCompleted(_ id: Int, _ completed: Bool) async throws {
        try await send("PUT", "/\(id)/completion", body: ["isCompleted": completed])
    }

    // MARK: - Long-term

    static func addLongTerm(_ goal: LongTermGoal) async throws { try await send("POST", "/long-term", body: goal) }
    static func updateLongTerm(_ goal: LongTermGoal) async throws { try await send("PUT", "/long-term/\(goal.id)", body: goal) }
    static func archiveLongTerm(_ id: UUID) async throws { try await send("PUT", "/long-term/\(id)/archive") }
    static func unarchiveLongTerm(_ id: UUID) async throws { try await send("PUT", "/long-term/\(id)/unarchive") }
    static func resetLongTerm() async throws { try await send("DELETE", "/long-term/reset") }
    /// also checks off the weekly goal made from this step (the server does it)
    static func setStepCompleted(goalId: UUID, stepId: UUID, _ completed: Bool) async throws {
        try await send("PUT", "/long-term/\(goalId)/steps/\(stepId)", body: ["isCompleted": completed])
    }
}
