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
}
