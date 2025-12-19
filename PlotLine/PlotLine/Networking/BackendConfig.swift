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
        
        print("Backend URL:", BackendConfig.baseURLString)
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
}
