//
//  ProfileAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/20/25.
//

import Foundation

struct ProfileAPI {
    static let baseURL = "http://localhost:8080"

    static func saveProfile(username: String, name: String, birthday: String, phone: String, city: String, profileUrl: String?) async throws {

        guard let url = URL(string: "\(baseURL)/profile/save-user") else {
            throw URLError(.badURL)
        }

        let requestBody = UserProfile(username: username, name: name, birthday: birthday, phone: phone, city: city, profileUrl: profileUrl)

        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(requestBody)
        } catch {
            throw error
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw AuthError.serverError
            }

            let saveResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            print("Profile saved successfully: \(saveResponse)")
        } catch {
            throw error
        }
    }
    
    static func fetchProfile(username: String) async throws -> UserProfile {
        guard let url = URL(string: "\(baseURL)/profile/get-user?username=\(username)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw AuthError.serverError
            }

            let fetchedProfile = try JSONDecoder().decode(UserProfile.self, from: data)
            return fetchedProfile
        } catch {
            throw error // Handle networking or decoding errors
        }
    }
    
    // change string date back to date when receiving get user info response
    func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
    }
    
}




//date to string
func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

