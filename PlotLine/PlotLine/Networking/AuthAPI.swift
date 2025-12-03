//
//  AuthAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/12/25.
//
import Foundation

struct AuthAPI {

    static let baseURL = "http://localhost:8080" // replace with localhost
    
    static func signUp(phone: String, email: String, username: String, password: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/signup") else {
            throw AuthError.invalidURL
        }

        // encode sign up request
        let requestBody = SignUpRequest(phone: phone, email: email, username: username, password: password)
        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
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
    
    static func sendCode(phone: String) async throws -> SmsResponse {
        
        guard let url = URL(string: "\(baseURL)/sms/send-verification") else {
            throw AuthError.invalidURL
        }
        
        let requestBody = SmsRequest(toNumber: phone)
        let jsonData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: url)
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
    case custom(String)
}
