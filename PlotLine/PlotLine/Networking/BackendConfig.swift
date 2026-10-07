import Foundation

enum BackendConfig {
    /// Base URL for the backend. Override by setting `BACKEND_BASE_URL` in Info.plist (per build config).
    static let baseURLString: String = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String {
            let val = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // If the value is empty or still a build placeholder like "$(BACKEND_BASE_URL)", fail fast.
            if !val.isEmpty && !val.contains("$(") {
                return val
            }
        }

        fatalError("BACKEND_BASE_URL is missing or still a placeholder in Info.plist. Set it per build config.")
    }()

    static let baseURL: URL = {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid BACKEND_BASE_URL: \(baseURLString)")
        }
        guard let host = url.host, host.contains(".") else {
            fatalError("BACKEND_BASE_URL must include a valid host (e.g., https://your-domain.com). Current value: \(baseURLString)")
        }
        return url
    }()

    /// API key for authenticating requests. Set `PLOTLINE_API_KEY` in Info.plist.
    static let apiKey: String? = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PLOTLINE_API_KEY") as? String {
            let val = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty && !val.contains("$(") {
                return val
            }
        }
        return nil
    }()

    /// Creates a URLRequest for the backend with the API key and login token already set
    static func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        addApiKey(to: &request)
        return request
    }

    /// Adds the backend auth headers to a request: the app's API key, plus the signed-in user's
    /// login token. The server identifies the user from the token, so every backend call needs it.
    /// Only use this for requests to our own backend, never third-party APIs.
    static func addApiKey(to request: inout URLRequest) {
        if let key = apiKey {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        if let token = KeychainManager.loadToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
