//
//  NutritionTests.swift
//  PlotLineTests
//
//  Nutrition page: daily totals, food decoding, day keys, dietary restrictions.
//

import Testing
import Foundation
@testable import PlotLine

struct NutritionTests {

    private func food(_ name: String, cal: Double, p: Double, c: Double, f: Double) -> FoodItem {
        FoodItem(name: name, servingSize: "1", servings: 1, calories: cal, protein: p, carbs: c, fat: f,
                 source: .manual, mealType: .lunch)
    }

    @Test("Daily totals add up every food")
    func totals() {
        let entry = NutritionEntry(date: Date(), foods: [
            food("Oatmeal", cal: 300, p: 10, c: 54, f: 6),
            food("Banana", cal: 105, p: 1, c: 27, f: 0.4),
        ])
        #expect(entry.totalCalories == 405)
        #expect(entry.totalProtein == 11)
        #expect(entry.totalCarbs == 81)
        #expect(abs(entry.totalFat - 6.4) < 0.0001)
    }

    @Test("Foods saved before meal sections existed still decode")
    func olderFood() throws {
        let item = try TestJSON.decode(FoodItem.self, """
        {"id":"f1","name":"Apple","servingSize":"1 medium","servings":1,"calories":95,"protein":0.5,"carbs":25,"fat":0.3,"source":"search"}
        """, iso8601: false)
        #expect(item.name == "Apple")
        #expect(item.mealType == nil)
        #expect(item.source == .search)
    }

    @Test("Meal sections have display names")
    func mealTypes() {
        #expect(FoodItem.MealType.allCases.map(\.displayName) == ["Breakfast", "Lunch", "Dinner", "Snack"])
    }

    @Test("Each day is stored under yyyy-MM-dd")
    func dayKey() {
        #expect(NutritionAPI.dateKey(from: TestJSON.day(2026, 10, 5)) == "2026-10-05")
    }

    @Test("Dietary restrictions round-trip")
    func dietary() throws {
        let saved = DietaryRestrictions(username: "alex", lactoseIntolerant: false, vegetarian: true, vegan: false,
                                        glutenFree: false, kosher: false, dairyFree: false, nutFree: true)
        let data = try JSONEncoder().encode(saved)
        let back = try JSONDecoder().decode(DietaryRestrictions.self, from: data)
        #expect(back.vegetarian)
        #expect(back.nutFree)
        #expect(!back.vegan)
    }

    @Test("A food without an id (what the photo analysis used to send) still loads")
    func foodWithoutId() throws {
        let foods = try TestJSON.decode([FoodItem].self, """
        [{"name":"Banana","servingSize":"1 medium","servings":1,"calories":105,"protein":1.3,"carbs":27,"fat":0.4,"source":"photo"},
         {"name":"Mystery","calories":"80"}]
        """, iso8601: false)
        #expect(foods.count == 2)
        #expect(!foods[0].id.isEmpty)
        #expect(foods[0].source == .photo)
        #expect(foods[1].calories == 80)
        #expect(foods[1].servings == 1)
    }

    @Test("Changing a photo food's grams rescales its numbers")
    func photoFoodGrams() throws {
        var thigh = try TestJSON.decode(PhotoFood.self, """
        {"id":"A","name":"Roasted chicken thigh","grams":150,"servingSize":"150 g (1 large thigh)",
         "calories":269,"protein":37.2,"carbs":0,"fat":12.2,"basis":"usda","usdaName":"Chicken, thigh, meat only, roasted"}
        """, iso8601: false)
        let asFound = thigh.foodItem(mealType: .dinner)
        #expect(asFound.calories == 269)
        #expect(asFound.servingSize == "150 g (1 large thigh)")
        #expect(asFound.source == .photo)
        #expect(asFound.mealType == .dinner)

        thigh.grams = 100
        let smaller = thigh.foodItem(mealType: .dinner)
        #expect(smaller.calories == 179)
        #expect(abs(smaller.protein - 24.8) < 0.01)
        #expect(smaller.servingSize == "100 g")
    }

    @Test("The food log keeps a group's foods together under one row, in order")
    func logGroups() {
        func food(_ name: String, group: String? = nil) -> FoodItem {
            FoodItem(name: name, servingSize: "1", servings: 1, calories: 100, protein: 1, carbs: 1, fat: 1,
                     source: .manual, mealType: .dinner, groupId: group, groupName: group.map { "Meal \($0)" })
        }
        let rows = NutritionView.logRows([food("Soup"), food("Chicken", group: "A"), food("Salad"), food("Rice", group: "A")])
        #expect(rows.count == 3)
        guard case .food(let first) = rows[0], case .group(_, let grouped) = rows[1], case .food(let last) = rows[2] else {
            Issue.record("unexpected rows"); return
        }
        #expect(first.name == "Soup")
        #expect(grouped.map(\.name) == ["Chicken", "Rice"])
        #expect(last.name == "Salad")
        #expect(NutritionView.photoGroupName([food("Chicken"), food("Rice"), food("Sauce")]) == "Chicken + 2 more")
    }

    @Test("A search result scales to the amount eaten, and keeps its brand in the name")
    func searchResultAmount() throws {
        let beef = try TestJSON.decode(SearchFood.self, """
        {"id":"usda-1","name":"Ground Beef","brand":"Wal-Mart Stores, Inc.","kind":"branded",
         "per100g":{"calories":312,"protein":17,"carbs":0,"fat":26},"portions":[{"label":"4 oz (112 g)","grams":112}]}
        """, iso8601: false)
        let item = beef.foodItem(grams: 112, amountLabel: "4 oz (112 g)")
        #expect(item.name == "Ground Beef (Wal-Mart Stores, Inc.)")
        #expect(item.calories == 349)
        #expect(abs(item.fat - 29.12) < 0.01)
        #expect(item.servingSize == "4 oz (112 g)")
        #expect(beef.isBranded)
    }
}