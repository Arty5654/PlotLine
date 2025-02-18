//
//  AuthAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/12/25.
//
import Foundation

struct AuthAPI {

    static let baseURL = "http://localhost:8080" // replace with localhost
    
    static func signUp(phone: String, username: String, password: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/signup") else {
            throw AuthError.invalidURL
        }

        // encode sign up request
        let requestBody = SignUpRequest(phone: phone, username: username, password: password)
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
    
    static func googleSignIn(idToken: String, username: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/google-signin") else {
            throw AuthError.invalidURL
        }

        let requestBody = GoogleSignInRequest(idToken: idToken, username: username)
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

    
    
    
    
}

// types of authentication errors
enum AuthError: Error {
    case invalidURL
    case serverError
    case custom(String)
}
