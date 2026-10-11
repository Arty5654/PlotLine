//
//  GroceryCosts.swift
//  PlotLine
//
//  Adding a grocery trip to spending ("Done Shopping") and taking it back (restoring the list).
//  A trip is recorded on its day in the dated costs, which feed both the spending screens and
//  "spent this week" on the grocery budget card (so that starts from zero each week).
//

import Foundation

enum GroceryCosts {
    private static var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
    }

    /// Does this account have a budget with a Groceries amount? nil if it couldn't be checked.
    static func hasGroceryBudget() async -> Bool? {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/budget/\(username)/weekly/groceries") else { return nil }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 404 { return false } // no budget yet (or no Groceries in it)
        return (200...299).contains(status) ? true : nil
    }

    /// Adds `amount` spent on `date` ("yyyy-MM-dd").
    static func record(_ amount: Double, on date: String) async throws {
        guard amount > 0 else { return }
        for type in ["weekly", "monthly"] {
            try await post("/api/costs/add-dated", ["username": username, "type": type, "date": date,
                                                     "costs": ["Groceries": amount]])
        }
    }

    /// Takes back a trip recorded with `record` (from the day it was recorded, not today).
    static func undo(_ amount: Double, on date: String) async throws {
        guard amount > 0 else { return }
        try await post("/api/costs/undo-receipt", ["username": username, "date": date, "costs": ["Groceries": amount]])
    }

    private static func post(_ path: String, _ body: [String: Any]) async throws {
        guard let url = URL(string: "\(BackendConfig.baseURLString)\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    static func today() -> String { GroceryListDetailView.isoDateString(Date()) }

    /// "spent this week" by category, for the person's own week (their today, not the server's)
    static func thisWeekURL(username: String) -> URL? {
        URL(string: "\(BackendConfig.baseURLString)/api/costs/\(username)/weekly?date=\(today())")
    }
}
