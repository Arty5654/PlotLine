//
//  GroceryTests.swift
//  PlotLineTests
//
//  Grocery lists: ownership and sharing as the app decides them.
//

import Testing
import Foundation
@testable import PlotLine

struct GroceryTests {

    private func list(owner: String?, username: String, members: [String]?) throws -> GroceryList {
        var json: [String: Any] = ["id": UUID().uuidString, "name": "Weekly", "items": [], "username": username]
        if let owner { json["ownerUsername"] = owner }
        if let members { json["members"] = members }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(GroceryList.self, from: data)
    }

    @Test("A list with members is shared; one without isn't")
    func sharing() throws {
        #expect(try list(owner: "alex", username: "alex", members: ["sam"]).isShared)
        #expect(try !list(owner: "alex", username: "alex", members: []).isShared)
        #expect(try !list(owner: nil, username: "alex", members: nil).isShared)
    }

    @Test("Ownership uses the owner field, falling back to the creator, ignoring case")
    func ownership() throws {
        let shared = try list(owner: "alex", username: "alex", members: ["sam"])
        #expect(shared.isOwned(by: "Alex"))
        #expect(!shared.isOwned(by: "sam"))
        #expect(try list(owner: nil, username: "jo", members: nil).isOwned(by: "jo"))
    }

    @Test("A list made from a meal says so and links to its recipe; older lists have neither")
    func listSourceAndRecipe() throws {
        let fromMeal = try TestJSON.decode(GroceryList.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Spaghetti","items":[],"username":"sam",
         "ai":true,"source":"meal","mealID":"ABC","mealName":"Spaghetti Bolognese"}
        """, iso8601: false)
        #expect(fromMeal.source == "meal")
        #expect(fromMeal.mealID == "ABC")

        let older = try TestJSON.decode(GroceryList.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302","name":"Tacos","items":[],"username":"sam","ai":true}
        """, iso8601: false)
        #expect(older.source == nil)
        #expect(older.mealID == nil)
    }

    @Test("An archived list remembers what its trip added to spending, so restoring can offer to take it back")
    func archivedSpending() throws {
        let list = try TestJSON.decode(GroceryList.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3303","name":"Weekly","items":[],"username":"sam",
         "spentAmount":12.5,"spentDate":"2026-10-11"}
        """, iso8601: false)
        #expect(list.spentAmount == 12.5)
        #expect(list.spentDate == "2026-10-11")
    }
}