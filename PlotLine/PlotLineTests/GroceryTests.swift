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
/// Foods from the log go on a grocery list as what you'd buy, not as what you ate.
struct GroceryNameTests {

    @Test("Cooked and prepared foods become the uncooked thing you buy",
          arguments: [
            ("Pasta, cooked", "Pasta"),
            ("Pasta, cooked, enriched, without added salt", "Pasta"),
            ("Beef, ground, 80% lean meat / 20% fat, raw", "Ground beef (80/20)"),
            ("Beef, ground, 93% lean meat / 7% fat, patty, cooked, pan-broiled", "Ground beef (93/7)"),
            ("Rice, white, long-grain, regular, enriched, cooked", "White rice, long-grain"),
            ("Chicken breast, grilled, skin not eaten", "Chicken breast"),
            ("Chicken, broilers or fryers, thigh, meat only, cooked, roasted", "Chicken thigh"),
            ("Broccoli, cooked, boiled, drained, without salt", "Broccoli"),
            ("Potatoes, mashed, home-prepared, whole milk added", "Potatoes"),
            ("Milk, whole", "Whole milk"),
            ("Grilled chicken breast", "Chicken breast"),
            ("Scrambled eggs", "Eggs"),
            ("Steamed white rice", "White rice"),
          ])
    func shoppingName(logged: String, expected: String) {
        #expect(GroceryName.forShopping(logged) == expected)
    }

    @Test("Names that already are what you buy stay as they are")
    func unchanged() {
        for name in ["Bananas", "Mom's lasagna", "Baked beans", "Spaghetti with meat sauce", "Grilled"] {
            #expect(GroceryName.forShopping(name) == name)
        }
    }

    @Test("Store products keep their name: they're bought as they are")
    func brandsKept() {
        let rotisserie = FoodItem(name: "Rotisserie Chicken, Cooked (Kirkland Signature)", servingSize: "100 g", servings: 1,
                                  calories: 190, protein: 25, carbs: 0, fat: 10, source: .search, brand: "Kirkland Signature")
        #expect(GroceryName.forShopping(rotisserie) == rotisserie.name)

        let scanned = FoodItem(name: "Barilla – Spaghetti", servingSize: "56 g", servings: 1,
                               calories: 200, protein: 7, carbs: 42, fat: 1, source: .barcode)
        #expect(GroceryName.forShopping(scanned) == scanned.name)

        let generic = FoodItem(name: "Pasta, cooked", servingSize: "1 cup", servings: 1,
                               calories: 220, protein: 8, carbs: 43, fat: 1, source: .search)
        #expect(GroceryName.forShopping(generic) == "Pasta")
    }

    @Test("A whole meal: one list item per thing to buy, named for the store")
    func mealEntries() {
        func food(_ name: String, brand: String? = nil) -> FoodItem {
            FoodItem(name: name, servingSize: "1 serving", servings: 1, calories: 100, protein: 1, carbs: 1, fat: 1,
                     source: .search, brand: brand)
        }
        let entries = AddToGrocerySheet.entries(for: [
            food("Pasta, cooked"),
            food("Beef, ground, 80% lean meat / 20% fat, raw"),
            food("Pasta, cooked, enriched, without added salt"), // shops as "Pasta" too
            food("Marinara Sauce (Rao's)", brand: "Rao's"),
        ])
        #expect(entries.map(\.name) == ["Pasta", "Ground beef (80/20)", "Marinara Sauce (Rao's)"])
        #expect(entries.filter { !$0.included }.isEmpty)
        #expect(entries[0].logged == "Pasta, cooked")
    }
}
