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
}
