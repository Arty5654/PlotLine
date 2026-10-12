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
    /// foods added together (a saved meal, a meal photo) share a group, shown as one row in the log
    var groupId: String? = nil
    var groupName: String? = nil
    /// the store brand of a branded search result; brands go on grocery lists as they are
    var brand: String? = nil

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

// Tolerant decoding: a food missing a field (an older save, an AI answer) still loads with
// sensible defaults instead of failing the whole list. In an extension so the memberwise init stays.
extension FoodItem {
    enum CodingKeys: String, CodingKey {
        case id, name, servingSize, servings, calories, protein, carbs, fat, source, mealType, groupId, groupName, brand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) -> Double? {
            if let d = try? c.decode(Double.self, forKey: key) { return d }
            if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
            return nil
        }
        self.init(
            id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            name: try c.decode(String.self, forKey: .name),
            servingSize: (try? c.decode(String.self, forKey: .servingSize)) ?? "1 serving",
            servings: number(.servings) ?? 1,
            calories: number(.calories) ?? 0,
            protein: number(.protein) ?? 0,
            carbs: number(.carbs) ?? 0,
            fat: number(.fat) ?? 0,
            source: (try? c.decode(FoodSource.self, forKey: .source)) ?? .manual,
            mealType: try? c.decode(MealType.self, forKey: .mealType),
            groupId: try? c.decode(String.self, forKey: .groupId),
            groupName: try? c.decode(String.self, forKey: .groupName),
            brand: try? c.decode(String.self, forKey: .brand)
        )
    }
}

/// One food found in a meal photo, before it's logged. Changing `grams` rescales the numbers.
struct PhotoFood: Decodable, Identifiable {
    let id: String
    var name: String
    let estimatedGrams: Double   // what the analysis found; the numbers below are for this weight
    let servingSize: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let basis: String?           // "usda" (USDA data for the estimated weight) or "estimate" (AI)
    let usdaName: String?
    var grams: Double            // what the person says they ate

    enum CodingKeys: String, CodingKey { case id, name, grams, servingSize, calories, protein, carbs, fat, basis, usdaName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        estimatedGrams = (try? c.decode(Double.self, forKey: .grams)) ?? 0
        grams = estimatedGrams
        servingSize = (try? c.decode(String.self, forKey: .servingSize)) ?? "1 serving"
        calories = (try? c.decode(Double.self, forKey: .calories)) ?? 0
        protein = (try? c.decode(Double.self, forKey: .protein)) ?? 0
        carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
        fat = (try? c.decode(Double.self, forKey: .fat)) ?? 0
        basis = try? c.decode(String.self, forKey: .basis)
        usdaName = try? c.decode(String.self, forKey: .usdaName)
    }

    private var scale: Double { estimatedGrams > 0 ? grams / estimatedGrams : 1 }

    /// the food as it goes into the log, for the weight now entered
    func foodItem(mealType: FoodItem.MealType) -> FoodItem {
        let portion = estimatedGrams > 0 && grams != estimatedGrams ? "\(Int(grams.rounded())) g" : servingSize
        return FoodItem(name: name, servingSize: portion, servings: 1,
                        calories: (calories * scale).rounded(), protein: protein * scale,
                        carbs: carbs * scale, fat: fat * scale, source: .photo, mealType: mealType)
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
