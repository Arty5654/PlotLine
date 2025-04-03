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
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case items
        case username
        case isAI = "ai"
    }
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
}
