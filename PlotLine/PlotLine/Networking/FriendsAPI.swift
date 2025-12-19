//
//  FriendsAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/27/25.
//

import Foundation
import SwiftUI

struct FriendsAPI {
    static let baseURL = "\(BackendConfig.baseURLString)"
    
    static func createOrUpdateFriendRequest(senderUsername: String, receiverUsername: String, status: String) async throws -> String {
        
        guard let url = URL(string: "\(baseURL)/friends/request") else {
            throw URLError(.badURL)
        }
        
        let requestBody = FriendRequest(senderUsername: senderUsername, receiverUsername: receiverUsername, status: status)
        
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
            
            let responseString = String(data: data, encoding: .utf8) ?? "Successfully Sent Friend Request"
            return responseString
            
        } catch {
            throw error
        }
    }
    
    static func fetchFriendList(username: String) async throws -> FriendList {
        guard let url = URL(string: "\(baseURL)/friends/get-friends?username=\(username)") else {
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

            let fetchedList = try JSONDecoder().decode(FriendList.self, from: data)
            return fetchedList
        } catch {
            throw error // Handle networking or decoding errors
        }
    }
    
    static func fetchFriendRequests(username: String) async throws -> RequestList {
        guard let url = URL(string: "\(baseURL)/friends/get-friend-requests?username=\(username)") else {
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

            let fetchedList = try JSONDecoder().decode(RequestList.self, from: data)
            return fetchedList
        } catch {
            throw error // Handle networking or decoding errors
        }
    }
    
    static func userExists(username: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/auth/user-exists?username=\(username)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError
        }
        
        // Decode the Boolean from the response
        let exists = try JSONDecoder().decode(Bool.self, from: data)
        return exists
    }
    
    static func getAllUsers() async throws -> [String] {

        guard let url = URL(string: "\(baseURL)/auth/get-users") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
            !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        if let jsonArray = try JSONSerialization
            .jsonObject(with: data) as? [String] {
            return jsonArray
        }

        // empty fallback
        return []
    }
    
    static func removeFriend(username: String, friendUsername: String) async throws {
        guard let url = URL(string: "\(baseURL)/friends/remove") else {
            throw URLError(.badURL)
        }
        let payload = FriendRequest(senderUsername: username, receiverUsername: friendUsername, status: "REMOVE")
        let data = try JSONEncoder().encode(payload)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.serverError
        }
    }
    
    
}
