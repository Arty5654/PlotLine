//
//  ChatMessage.swift
//  PlotLine
//
//  Created by Alex Younkers on 4/22/25.
//
import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: String
    let creator: String
    let timestamp: Date
    let content: String
    var reactions: [String: Int]
    var replies: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case id, creator, timestamp, content, reactions, replies
    }
}

