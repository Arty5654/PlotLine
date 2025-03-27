//
//  FriendsAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/27/25.
//

import Foundation
import SwiftUI

struct FriendsAPI {
    static let baseURL = "http://localhost:8080"
    
    static func createOrUpdateFriendRequest(senderUsername: String, receiverUsername: String, status: String) async throws {
        
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
    
    
}
