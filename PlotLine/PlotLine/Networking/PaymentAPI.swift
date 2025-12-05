import Foundation

enum PaymentAPIError: Error {
    case invalidURL
    case serverError
    case custom(String)
}

enum PaymentAPI {
    private static let baseURL = "http://localhost:8080"

    static func fetchStatus(username: String) async throws -> SubscriptionStatus {
        guard let url = URL(string: "\(baseURL)/api/payments/status/\(username)") else {
            throw PaymentAPIError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PaymentAPIError.serverError
        }
        return try JSONDecoder().decode(SubscriptionStatus.self, from: data)
    }

    static func claim(username: String) async throws -> SubscriptionStatus {
        guard let url = URL(string: "\(baseURL)/api/payments/claim") else {
            throw PaymentAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["username": username]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PaymentAPIError.serverError
        }
        return try JSONDecoder().decode(SubscriptionStatus.self, from: data)
    }

    static func cancel(username: String) async throws -> SubscriptionStatus {
        guard let url = URL(string: "\(baseURL)/api/payments/cancel") else {
            throw PaymentAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["username": username]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PaymentAPIError.serverError
        }
        return try JSONDecoder().decode(SubscriptionStatus.self, from: data)
    }

    static func syncAppleEntitlement(username: String,
                                     originalTransactionID: UInt64,
                                     appAccountToken: UUID?) async throws {
        guard let url = URL(string: "\(baseURL)/api/payments/apple/sync") else {
            throw PaymentAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "username": username,
            "originalTransactionId": String(originalTransactionID),
            "appAccountToken": appAccountToken?.uuidString as Any
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await URLSession.shared.data(for: req)
    }
}
