//
//  GroceryList.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

import Foundation

struct GroceryList: Identifiable, Codable {
    var id: UUID
    var name: String
    var items: [GroceryItem]
    var username: String
    var isAI: Bool?
    var mealID: String?
    var mealName: String?
    var ownerUsername: String?   // Owner of the canonical shared list (nil for older lists)
    var members: [String]?       // Usernames this list is shared with (excludes the owner)

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case items
        case username
        case isAI = "ai"
        case mealID
        case mealName
        case ownerUsername
        case members
    }

    // True when this list has more than one participant (owner + at least one member).
    var isShared: Bool {
        (members?.isEmpty == false)
    }

    // Whether the given user owns the canonical copy of this list.
    func isOwned(by user: String) -> Bool {
        let owner = ownerUsername ?? username
        return owner.lowercased() == user.lowercased()
    }
}

struct GroceryListInvite: Identifiable, Codable {
    var id: String
    var fromUsername: String
    var toUsername: String
    var ownerUsername: String?
    var listId: String
    var listName: String
    var sentAt: String
    var items: [GroceryItem]
}

struct GroceryItem: Identifiable, Codable, Equatable {
    var listId: UUID
    var id: UUID
    var name: String
    var quantity: Int
    var checked: Bool
    var price: Double?
    var store: String?
    var notes: String?
    var checkedBy: String?   // Username of who checked it off (shared lists)
}
