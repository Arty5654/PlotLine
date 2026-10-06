//
//  AuthAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/12/25.
//
import Foundation

struct AuthAPI {

    // Point the app to the deployed backend
    static let baseURL = "\(BackendConfig.baseURLString)"
    
    static func signUp(phone: String, email: String, username: String, password: String, acceptedTerms: Bool) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/signup") else {
            throw AuthError.invalidURL
        }

        // encode sign up request
        let requestBody = SignUpRequest(phone: phone, email: email, username: username, password: password,
                                        acceptedTerms: acceptedTerms)
        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        if !authResponse.success {
            throw AuthError.custom(authResponse.error ?? "Unknown error")
        }

        return authResponse
    }


    static func signIn(username: String, password: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/signin") else {
            throw AuthError.invalidURL
        }

        // encode sign up request
        let requestBody = SignInRequest(username: username, password: password)
        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        if !authResponse.success {

            throw AuthError.custom(authResponse.error ?? "Unknown error")
        }

        return authResponse
    }

    static func googleSignIn(idToken: String, username: String, email: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/google-signin") else {
            throw AuthError.invalidURL
        }

        let requestBody = GoogleSignInRequest(idToken: idToken, username: username, email: email)
        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        if !authResponse.success {
            throw AuthError.custom(authResponse.error ?? "Google authentication failed")
        }

        return authResponse
    }

    // server replies with one of these when it needs more input before signing in
    static let appleUsernameRequired = "Username Required"
    static let appleLinkRequired = "Link Required"

    static func appleSignIn(identityToken: String, rawNonce: String, username: String?, linkPassword: String?) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/apple-signin") else {
            throw AuthError.invalidURL
        }

        let requestBody = AppleSignInRequest(identityToken: identityToken, rawNonce: rawNonce, username: username, linkPassword: linkPassword)
        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        let needsMoreInput = authResponse.error == appleUsernameRequired || authResponse.error == appleLinkRequired
        if !authResponse.success && !needsMoreInput {
            throw AuthError.custom(authResponse.error ?? "Apple authentication failed")
        }

        return authResponse
    }

    // Swap the current login token for a fresh one. Throws sessionExpired if the token is no longer valid.
    static func refreshSession() async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/refresh") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverError
        }
        if httpResponse.statusCode == 401 {
            throw AuthError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    // Record that the signed-in user agrees to the current Terms of Service and Privacy Policy
    static func acceptTerms() async throws {
        guard let url = URL(string: "\(baseURL)/auth/accept-terms") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverError
        }
        if httpResponse.statusCode == 401 {
            throw AuthError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }
        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        if !authResponse.success {
            throw AuthError.custom(authResponse.error ?? "Couldn't save your agreement. Please try again.")
        }
    }

    static let appleAuthorizationRequired = "Apple Authorization Required"

    // Permanently deletes the signed-in account. The server identifies the account from the login token.
    static func deleteAccount(appleAuthorizationCode: String?) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/delete-account") else {
            throw AuthError.invalidURL
        }
        guard KeychainManager.loadToken() != nil else {
            throw AuthError.sessionExpired
        }

        var body: [String: String] = [:]
        if let appleAuthorizationCode { body["appleAuthorizationCode"] = appleAuthorizationCode }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverError
        }
        if httpResponse.statusCode == 401 {
            throw AuthError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        if !authResponse.success && authResponse.error != appleAuthorizationRequired {
            throw AuthError.custom(authResponse.error ?? "Couldn't delete your account.")
        }
        return authResponse
    }
    
    static func sendCode(phone: String) async throws -> SmsResponse {
        
        guard let url = URL(string: "\(baseURL)/sms/send-verification") else {
            throw AuthError.invalidURL
        }
        
        let requestBody = SmsRequest(toNumber: phone)
        let jsonData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }
        
        let textResponse = try JSONDecoder().decode(SmsResponse.self, from: data)
        if !textResponse.success {
            throw AuthError.custom(textResponse.message)
        }
        
        return textResponse
    }

    
    static func sendVerification(phone: String, code: String, username: String) async throws -> SmsResponse {
        
        guard let url = URL(string: "\(baseURL)/sms/verify-code") else {
            throw AuthError.invalidURL
        }
        
        let requestBody = VerificationRequest(phoneNumber: phone, code: code, username: username)
        let jsonData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }
        
        let textResponse = try JSONDecoder().decode(SmsResponse.self, from: data)
        if !textResponse.success {
            throw AuthError.custom(textResponse.message)
        }
        
        return textResponse
    }
    
    static func changePassword(username: String, oldPassword: String, newPassword: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/auth/change-password") else {
            throw AuthError.invalidURL
        }

        let requestBody = PasswordRequest(username: username, oldPassword: oldPassword, newPassword: newPassword)
        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        if !authResponse.success {

            throw AuthError.custom(authResponse.error ?? "Unknown error")
        }

        return authResponse.success
    }
    
    static func changePasswordWithCode(username: String, newPassword: String, code: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/auth/change-password-code") else {
            throw AuthError.invalidURL
        }

        let requestBody = OTPPasswordRequest(username: username, newPassword: newPassword, code: code)
        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        if !authResponse.success {

            throw AuthError.custom(authResponse.error ?? "Unknown error")
        }

        return authResponse.success
    }
    
    
    
    
    
    
}

// types of authentication errors
enum AuthError: Error {
    case invalidURL
    case serverError
    case sessionExpired
    case custom(String)
}
