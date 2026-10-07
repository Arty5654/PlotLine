import Foundation

enum PaymentAPIError: LocalizedError {
    case invalidURL
    case serverError
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL, .serverError: return "Couldn't reach PlotLine. Please try again."
        case .custom(let message): return message
        }
    }
}

enum PaymentAPI {
    private static let baseURL = "\(BackendConfig.baseURLString)"

    static func fetchStatus(username: String) async throws -> MembershipStatus {
        guard let url = URL(string: "\(baseURL)/api/payments/status/\(username)") else {
            throw PaymentAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PaymentAPIError.serverError
        }
        return try JSONDecoder().decode(MembershipStatus.self, from: data)
    }

    /// Sends an App Store purchase (StoreKit's signed transaction) to the server, which checks
    /// Apple's signature and unlocks this account.
    static func syncApplePurchase(signedTransaction: String) async throws -> MembershipStatus {
        guard let url = URL(string: "\(baseURL)/api/payments/apple/sync") else {
            throw PaymentAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["signedTransaction": signedTransaction])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let refusal = refusal(data, response) { throw refusal }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PaymentAPIError.serverError
        }
        return try JSONDecoder().decode(MembershipStatus.self, from: data)
    }

    /// the server's reason when it refuses a purchase (400: not verified, 409: used by another account)
    static func refusal(_ data: Data, _ response: URLResponse) -> PaymentAPIError? {
        guard let http = response as? HTTPURLResponse, http.statusCode == 400 || http.statusCode == 409 else { return nil }
        struct Body: Decodable { let error: String? }
        guard let message = (try? JSONDecoder().decode(Body.self, from: data))?.error else { return nil }
        return .custom(message)
    }
}
