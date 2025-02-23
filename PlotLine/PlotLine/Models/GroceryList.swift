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
    var items: [GroceryItem] // Can be replaced with a more detailed model if needed
    var username: String // Include username to associate the list with the user
}

struct GroceryItem: Codable {
    var id: UUID
    var name: String
    var quantity: Int
    var checked: Bool
}
