//
//  ChatAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 4/22/25.
//

import Foundation

class ChatAPI {
    private let baseURL = URL(string: "\(BackendConfig.baseURLString)/chat")!
    
    // helper decoder/encoder for reuse of timestamp encode/decode
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    
    func fetchFeed(userId: String) async throws -> [ChatMessage] {
        var components = URLComponents(url: baseURL.appendingPathComponent("get-feed"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "userId", value: userId)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try decoder.decode([ChatMessage].self, from: data)
    }

    
    func postMessage(userId: String, content: String) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId)
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let msg = ChatMessage(
            id: UUID().uuidString,
            creator: userId,
            timestamp: Date(),
            content: content,
            reactions: [:],
            replies: [:]
        )
        req.httpBody = try encoder.encode(msg)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }


    func addReaction(owner: String, messageId: String, emoji: String) async throws {
        let url = baseURL
            .appendingPathComponent(owner)
            .appendingPathComponent(messageId)
            .appendingPathComponent("reactions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(["emoji": emoji])
        _ = try await URLSession.shared.data(for: req)
    }
    
    func removeReaction(owner: String, messageId: String, emoji: String) async throws {
        // Build URL: \(BackendConfig.baseURLString)/chat/{owner}/{messageId}/reactions?emoji={emoji}
        let url = baseURL
            .appendingPathComponent(owner)
            .appendingPathComponent(messageId)
            .appendingPathComponent("reactions")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "emoji", value: emoji)
        ]

        var req = URLRequest(url: components.url!)
        req.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }


    func addReply(owner: String, messageId: String, text: String) async throws {
        // grab the replier’s username from UserDefaults
        let replier = UserDefaults
            .standard
            .string(forKey: "loggedInUsername") ?? "Guest"

        let url = baseURL
            .appendingPathComponent(owner)
            .appendingPathComponent(messageId)
            .appendingPathComponent("replies")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // now send both userId and text
        let body = ["userId": replier, "text": text]
        req.httpBody = try encoder.encode(body)

        _ = try await URLSession.shared.data(for: req)
    }

}
