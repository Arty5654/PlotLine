// WidgetSharedData.swift — PlotLineWidgets target
// Read-only side: widget reads cached data that the main app writes.

import Foundation

let widgetAppGroupID = "group.com.ArteomAvetissian.PlotLine"

// MARK: - App Groups UserDefaults

extension UserDefaults {
    static var widgetShared: UserDefaults {
        UserDefaults(suiteName: widgetAppGroupID) ?? .standard
    }
}

// MARK: - Keys

enum WidgetKey {
    static let username         = "widget_username"
    static let baseURL          = "widget_base_url"
    static let apiKey           = "widget_api_key"
    static let nutritionToday   = "widget_nutrition_today"
    static let weeklyGoals      = "widget_weekly_goals"
    static let longTermGoals    = "widget_longterm_goals"
    static let financialWeekly  = "widget_financial_weekly"
    static let financialMonthly = "widget_financial_monthly"
}

// MARK: - Nutrition

struct NutritionWidgetData: Codable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double

    static let empty = NutritionWidgetData(
        calories: 0, protein: 0, carbs: 0, fat: 0,
        calorieGoal: 2000, proteinGoal: 150, carbsGoal: 225, fatGoal: 65
    )

    var calorieFraction: Double { calorieGoal > 0 ? min(calories / calorieGoal, 1.0) : 0 }
    var proteinFraction: Double { proteinGoal > 0 ? min(protein / proteinGoal, 1.0) : 0 }
    var carbsFraction: Double   { carbsGoal > 0   ? min(carbs / carbsGoal, 1.0) : 0 }
    var fatFraction: Double     { fatGoal > 0      ? min(fat / fatGoal, 1.0) : 0 }
}

// MARK: - Goals

struct GoalWidgetItem: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var isCompleted: Bool
    var priority: String
    var isFinancialGoal: Bool
    var progress: Double?
}

// MARK: - Financial

struct FinancialWidgetData: Codable {
    var totalSpent: Double
    var totalBudget: Double

    static let empty = FinancialWidgetData(totalSpent: 0, totalBudget: 0)

    var fraction: Double    { totalBudget > 0 ? min(totalSpent / totalBudget, 1.0) : 0 }
    var remaining: Double   { max(totalBudget - totalSpent, 0) }
    var isOverBudget: Bool  { totalSpent > totalBudget && totalBudget > 0 }
}

// MARK: - Readers

func readNutritionData() -> NutritionWidgetData {
    guard let data = UserDefaults.widgetShared.data(forKey: WidgetKey.nutritionToday),
          let snap = try? JSONDecoder().decode(NutritionWidgetData.self, from: data) else {
        return .empty
    }
    return snap
}

func readGoalsData() -> [GoalWidgetItem] {
    guard let data = UserDefaults.widgetShared.data(forKey: WidgetKey.weeklyGoals),
          let goals = try? JSONDecoder().decode([GoalWidgetItem].self, from: data) else {
        return []
    }
    return goals
}

func readLongTermGoalsData() -> [GoalWidgetItem] {
    guard let data = UserDefaults.widgetShared.data(forKey: WidgetKey.longTermGoals),
          let goals = try? JSONDecoder().decode([GoalWidgetItem].self, from: data) else {
        return []
    }
    return goals
}

func readFinancialData(period: String) -> FinancialWidgetData {
    let key = period == "monthly" ? WidgetKey.financialMonthly : WidgetKey.financialWeekly
    guard let data = UserDefaults.widgetShared.data(forKey: key),
          let snap = try? JSONDecoder().decode(FinancialWidgetData.self, from: data) else {
        return .empty
    }
    return snap
}
