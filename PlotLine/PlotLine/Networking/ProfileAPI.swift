//
//  ProfileAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/20/25.
//

import Foundation
import SwiftUI

struct ProfileAPI {
    static let baseURL = "http://localhost:8080"

    static func saveProfile(username: String, name: String, birthday: String, city: String) async throws {

        guard let url = URL(string: "\(baseURL)/profile/save-user") else {
            throw URLError(.badURL)
        }

        let requestBody = UserProfile(username: username, name: name, birthday: birthday, city: city)

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
    
    static func fetchPhone(username: String) async throws -> String? {
        guard let url = URL(string: "\(baseURL)/profile/get-phone?username=\(username)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Convert raw data to a string
        let phoneString = String(data: data, encoding: .utf8)
        return phoneString
    }
    
    static func getProfilePic(username: String) async throws -> String? {
        
        guard let url = URL(string: "\(baseURL)/profile/get-profile-pic?username=\(username)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return jsonResponse?["profilePicUrl"] as? String

    }

    
    static func uploadProfilePicture(image: UIImage, username: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.badURL)
        }

        let url = URL(string: "\(baseURL)/profile/upload-profile-pic?username=\(username)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let fileName = "\(username).jpg"
        let mimeType = "image/jpeg"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        

        //body.append("--\(boundary)\r\n".data(using: .utf8)!)
        //body.append("Content-Disposition: form-data; name=\"username\"\r\n\r\n".data(using: .utf8)!)
        //body.append("\(username)\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
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

