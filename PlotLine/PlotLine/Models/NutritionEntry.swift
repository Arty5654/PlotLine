//
//  NutritionEntry.swift
//  PlotLine
//

import Foundation

struct NutritionEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var date: Date
    var foods: [FoodItem]

    var totalCalories: Double { foods.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { foods.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { foods.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { foods.reduce(0) { $0 + $1.fat } }
}

struct FoodItem: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var servingSize: String  // e.g. "1 cup", "100g", "1 bar"
    var servings: Double     // how many servings the user ate
    var calories: Double     // total for the servings eaten
    var protein: Double      // grams
    var carbs: Double        // grams
    var fat: Double          // grams
    var source: FoodSource   // how the food was added
    var mealType: MealType?  // which meal section (nil = snack for backward compat)

    enum FoodSource: String, Codable {
        case manual
        case barcode
        case photo
        case search
    }

    enum MealType: String, Codable, CaseIterable {
        case breakfast
        case lunch
        case dinner
        case snack

        var displayName: String {
            switch self {
            case .breakfast: return "Breakfast"
            case .lunch: return "Lunch"
            case .dinner: return "Dinner"
            case .snack: return "Snack"
            }
        }

        var icon: String {
            switch self {
            case .breakfast: return "sunrise"
            case .lunch: return "sun.max"
            case .dinner: return "moon.stars"
            case .snack: return "leaf"
            }
        }
    }
}

// MARK: - Saved Meal (group of foods)
struct SavedMeal: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var foods: [FoodItem]

    var totalCalories: Double { foods.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { foods.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { foods.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { foods.reduce(0) { $0 + $1.fat } }
}

// MARK: - User's saved favorites & meals container
struct NutritionUserData: Codable {
    var favorites: [FoodItem]
    var savedMeals: [SavedMeal]
    var goals: NutritionGoals?
}

// MARK: - Nutrition Goals
struct NutritionGoals: Codable {
    var calorieGoal: Double
    var proteinGoal: Double   // grams
    var carbsGoal: Double     // grams
    var fatGoal: Double       // grams
    var source: GoalSource
    var quizData: QuizData?

    enum GoalSource: String, Codable {
        case manual
        case quiz
    }

    /// Compute macro goals from a calorie target and weight goal
    static func macrosFrom(calories: Double, weightGoal: QuizData.WeightGoal) -> (protein: Double, carbs: Double, fat: Double) {
        let splits: (p: Double, c: Double, f: Double) = {
            switch weightGoal {
            case .lose:     return (0.30, 0.40, 0.30)
            case .maintain: return (0.30, 0.40, 0.30)
            case .gain:     return (0.30, 0.45, 0.25)
            }
        }()
        return (
            protein: (calories * splits.p) / 4.0,
            carbs:   (calories * splits.c) / 4.0,
            fat:     (calories * splits.f) / 9.0
        )
    }
}

struct QuizData: Codable {
    var weightLbs: Double
    var heightFeet: Int
    var heightInches: Int
    var age: Int
    var gender: Gender
    var activityLevel: ActivityLevel
    var weightGoal: WeightGoal

    var weightKg: Double { weightLbs * 0.453592 }
    var heightCm: Double { Double(heightFeet * 12 + heightInches) * 2.54 }

    enum Gender: String, Codable, CaseIterable {
        case male, female
        var displayName: String { self == .male ? "Male" : "Female" }
    }

    enum ActivityLevel: String, Codable, CaseIterable {
        case sedentary
        case lightlyActive
        case moderatelyActive
        case veryActive
        case extraActive

        var displayName: String {
            switch self {
            case .sedentary:        return "Sedentary"
            case .lightlyActive:    return "Lightly Active"
            case .moderatelyActive: return "Moderately Active"
            case .veryActive:       return "Very Active"
            case .extraActive:      return "Extra Active"
            }
        }
        var detail: String {
            switch self {
            case .sedentary:        return "Little or no exercise"
            case .lightlyActive:    return "Exercise 1-3 days/week"
            case .moderatelyActive: return "Exercise 3-5 days/week"
            case .veryActive:       return "Exercise 6-7 days/week"
            case .extraActive:      return "Very hard exercise, physical job"
            }
        }
        var multiplier: Double {
            switch self {
            case .sedentary:        return 1.2
            case .lightlyActive:    return 1.375
            case .moderatelyActive: return 1.55
            case .veryActive:       return 1.725
            case .extraActive:      return 1.9
            }
        }
    }

    enum WeightGoal: String, Codable, CaseIterable {
        case lose, maintain, gain
        var displayName: String {
            switch self {
            case .lose:     return "Lose Weight"
            case .maintain: return "Maintain"
            case .gain:     return "Gain Weight"
            }
        }
        var detail: String {
            switch self {
            case .lose:     return "~1 lb/week calorie deficit"
            case .maintain: return "Stay at current weight"
            case .gain:     return "~0.5 lb/week surplus"
            }
        }
    }

    /// Mifflin-St Jeor BMR
    var bmr: Double {
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(age)
        return gender == .male ? base + 5 : base - 161
    }

    /// TDEE = BMR x activity multiplier
    var tdee: Double { bmr * activityLevel.multiplier }

    /// Adjusted calories for weight goal
    var targetCalories: Double {
        switch weightGoal {
        case .lose:     return tdee - 600
        case .maintain: return tdee
        case .gain:     return tdee + 300
        }
    }
}

// Open Food Facts API response models
struct OpenFoodFactsProduct: Codable {
    let status: Int?
    let product: OFFProductDetail?
}

struct OFFProductDetail: Codable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: Double?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case nutriments
    }
}

struct OFFNutriments: Codable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let energyKcalServing: Double?
    let proteinsServing: Double?
    let carbohydratesServing: Double?
    let fatServing: Double?
    // Some products store energy in kJ instead of kcal
    let energyKj100g: Double?
    let energyKjServing: Double?
    // Some products use "energy_100g" which is kJ
    let energy100g: Double?
    let energyServing: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteinsServing = "proteins_serving"
        case carbohydratesServing = "carbohydrates_serving"
        case fatServing = "fat_serving"
        case energyKj100g = "energy-kj_100g"
        case energyKjServing = "energy-kj_serving"
        case energy100g = "energy_100g"
        case energyServing = "energy_serving"
    }

    /// Best available kcal per serving, converting from kJ if needed (1 kJ ≈ 0.239 kcal)
    var bestCaloriesServing: Double? {
        if let v = energyKcalServing, v > 0 { return v }
        if let v = energyKjServing, v > 0 { return v * 0.239 }
        if let v = energyServing, v > 0 {
            // energy_serving is usually kJ
            return v * 0.239
        }
        return nil
    }

    /// Best available kcal per 100g, converting from kJ if needed
    var bestCalories100g: Double? {
        if let v = energyKcal100g, v > 0 { return v }
        if let v = energyKj100g, v > 0 { return v * 0.239 }
        if let v = energy100g, v > 0 {
            return v * 0.239
        }
        return nil
    }
}

// Open Food Facts search response
struct OFFSearchResponse: Codable {
    let count: Int?
    let products: [OFFProductDetail]?
}
