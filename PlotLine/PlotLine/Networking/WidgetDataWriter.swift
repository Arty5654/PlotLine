// WidgetDataWriter.swift — PlotLine (main app) target
// Writes cached data to the App Groups shared UserDefaults so widgets can read it.
// Call WidgetDataWriter.reloadWidgets() after writing to refresh widget timelines.

import Foundation
import WidgetKit

private let appGroupID = "group.com.plotline.shared"

private var sharedDefaults: UserDefaults {
    UserDefaults(suiteName: appGroupID) ?? .standard
}

// MARK: - Keys (must match WidgetSharedData.swift in widget target)

private enum WKey {
    static let username         = "widget_username"
    static let baseURL          = "widget_base_url"
    static let apiKey           = "widget_api_key"
    static let nutritionToday   = "widget_nutrition_today"
    static let weeklyGoals      = "widget_weekly_goals"
    static let financialWeekly  = "widget_financial_weekly"
    static let financialMonthly = "widget_financial_monthly"
}

// MARK: - Snapshot structs (must match those in WidgetSharedData.swift)

private struct NutritionSnapshot: Encodable {
    var calories, protein, carbs, fat: Double
    var calorieGoal, proteinGoal, carbsGoal, fatGoal: Double
}

private struct GoalSnapshot: Encodable {
    var id: Int
    var name: String
    var isCompleted: Bool
    var priority: String
    var isFinancialGoal: Bool
    var progress: Double?
}

private struct FinancialSnapshot: Encodable {
    var totalSpent: Double
    var totalBudget: Double
}

// MARK: - Public API

enum WidgetDataWriter {

    static func writeCredentials() {
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        sharedDefaults.set(username, forKey: WKey.username)
        sharedDefaults.set(BackendConfig.baseURLString, forKey: WKey.baseURL)
        if let key = BackendConfig.apiKey {
            sharedDefaults.set(key, forKey: WKey.apiKey)
        }
    }

    static func writeNutrition(
        calories: Double, protein: Double, carbs: Double, fat: Double,
        calorieGoal: Double, proteinGoal: Double, carbsGoal: Double, fatGoal: Double
    ) {
        let snap = NutritionSnapshot(
            calories: calories, protein: protein, carbs: carbs, fat: fat,
            calorieGoal: calorieGoal, proteinGoal: proteinGoal,
            carbsGoal: carbsGoal, fatGoal: fatGoal
        )
        if let data = try? JSONEncoder().encode(snap) {
            sharedDefaults.set(data, forKey: WKey.nutritionToday)
        }
    }

    static func writeGoals(_ tasks: [TaskItem]) {
        let snaps = tasks.map { t in
            GoalSnapshot(
                id: t.id,
                name: t.name,
                isCompleted: t.isCompleted,
                priority: t.priority.rawValue,
                isFinancialGoal: t.isFinancialGoal,
                progress: t.progress
            )
        }
        if let data = try? JSONEncoder().encode(snaps) {
            sharedDefaults.set(data, forKey: WKey.weeklyGoals)
        }
    }

    static func writeFinancial(period: String, totalSpent: Double, totalBudget: Double) {
        let snap = FinancialSnapshot(totalSpent: totalSpent, totalBudget: totalBudget)
        if let data = try? JSONEncoder().encode(snap) {
            let key = period == "monthly" ? WKey.financialMonthly : WKey.financialWeekly
            sharedDefaults.set(data, forKey: key)
        }
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
