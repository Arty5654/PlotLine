// WidgetDataWriter.swift — PlotLine (main app) target
// Writes cached data to the App Groups shared UserDefaults so widgets can read it.
// Call WidgetDataWriter.reloadWidgets() after writing to refresh widget timelines.

import Foundation
import WidgetKit

private let appGroupID = "group.com.ArteomAvetissian.PlotLine"

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
    static let longTermGoals    = "widget_longterm_goals"
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

    static func writeLongTermGoals(_ goals: [LongTermGoal]) {
        let snaps = goals.enumerated().map { (index, goal) in
            let done = goal.steps.filter { $0.isCompleted }.count
            let total = goal.steps.count
            return GoalSnapshot(
                id: index + 1,
                name: goal.title,
                isCompleted: total > 0 && done == total,
                priority: "Medium",
                isFinancialGoal: false,
                progress: total > 0 ? Double(done) / Double(total) : nil
            )
        }
        if let data = try? JSONEncoder().encode(snaps) {
            sharedDefaults.set(data, forKey: WKey.longTermGoals)
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

    // Fetches weekly goals from the backend and writes to shared UserDefaults.
    // Called on app foreground so the widget stays current between 30-min scheduled refreshes.
    static func refreshGoalsData() {
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        guard !username.isEmpty, username != "Guest" else { return }

        if let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)") {
            var req = URLRequest(url: url)
            BackendConfig.addApiKey(to: &req)
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let resp = try? JSONDecoder().decode(WeeklyGoalsRefreshResponse.self, from: data) else { return }
                let snaps = resp.weeklyGoals.map { t in
                    GoalSnapshot(id: t.id, name: t.name, isCompleted: t.completed,
                                 priority: t.priority, isFinancialGoal: t.isFinancialGoal ?? false,
                                 progress: t.progress)
                }
                if let encoded = try? JSONEncoder().encode(snaps) {
                    sharedDefaults.set(encoded, forKey: WKey.weeklyGoals)
                }
                reloadWidgets()
            }.resume()
        }

        if let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term") {
            var req = URLRequest(url: url)
            BackendConfig.addApiKey(to: &req)
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let resp = try? JSONDecoder().decode(LongTermGoalsRefreshResponse.self, from: data) else { return }
                let snaps = resp.longTermGoals.enumerated().map { (index, goal) in
                    let done = goal.steps.filter { $0.completed }.count
                    let total = goal.steps.count
                    return GoalSnapshot(id: index + 1, name: goal.title,
                                       isCompleted: total > 0 && done == total,
                                       priority: "Medium", isFinancialGoal: false,
                                       progress: total > 0 ? Double(done) / Double(total) : nil)
                }
                if let encoded = try? JSONEncoder().encode(snaps) {
                    sharedDefaults.set(encoded, forKey: WKey.longTermGoals)
                }
                reloadWidgets()
            }.resume()
        }
    }

    private struct WeeklyGoalsRefreshResponse: Decodable {
        let weeklyGoals: [WeeklyGoalRefreshItem]
    }
    private struct WeeklyGoalRefreshItem: Decodable {
        let id: Int
        let name: String
        let completed: Bool
        let priority: String
        let isFinancialGoal: Bool?
        let progress: Double?
    }
    private struct LongTermGoalsRefreshResponse: Decodable {
        let longTermGoals: [LongTermGoalRefreshItem]
    }
    private struct LongTermGoalRefreshItem: Decodable {
        let title: String
        let steps: [LongTermStepRefreshItem]
    }
    private struct LongTermStepRefreshItem: Decodable {
        let completed: Bool
    }

    // Fetches actual spending from the same endpoints the budget chart uses, then writes
    // both weekly and monthly totals to shared UserDefaults and reloads widget timelines.
    static func refreshFinancialData() {
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        guard !username.isEmpty, username != "Guest" else { return }

        let now = Date()
        let monthFmt = DateFormatter()
        monthFmt.calendar = .init(identifier: .gregorian)
        monthFmt.dateFormat = "yyyy-MM"
        let currentMonth = monthFmt.string(from: now)

        guard let costsURL = URL(string: "\(BackendConfig.baseURLString)/api/costs/monthly/\(username)?month=\(currentMonth)") else { return }
        var costsRequest = URLRequest(url: costsURL)
        BackendConfig.addApiKey(to: &costsRequest)

        URLSession.shared.dataTask(with: costsRequest) { costsData, _, costsError in
            guard costsError == nil,
                  let costsData = costsData,
                  let period = try? JSONDecoder().decode(FinancialPeriodFile.self, from: costsData) else { return }

            let excluded: Set<String> = ["401(k)", "401k", "401(k) Contribution", "401k Contribution"]

            let monthlySpent = (period.totals ?? [:])
                .filter { !excluded.contains($0.key) }
                .values.reduce(0, +)

            let cal = Calendar(identifier: .gregorian)
            let weekday = cal.component(.weekday, from: now)
            let weekStart = cal.date(byAdding: .day, value: -(weekday - 1), to: cal.startOfDay(for: now)) ?? now
            let dayFmt = DateFormatter()
            dayFmt.calendar = .init(identifier: .gregorian)
            dayFmt.dateFormat = "yyyy-MM-dd"
            let weeklySpent = (period.days ?? [:])
                .filter { (k, _) in
                    guard let d = dayFmt.date(from: k) else { return false }
                    return d >= weekStart && d <= now
                }
                .values
                .flatMap { $0.filter { !excluded.contains($0.key) }.values }
                .reduce(0, +)

            guard let budgetURL = URL(string: "\(BackendConfig.baseURLString)/api/llm/budget/last/\(username)") else {
                writeFinancial(period: "monthly", totalSpent: monthlySpent, totalBudget: 0)
                writeFinancial(period: "weekly",  totalSpent: weeklySpent,  totalBudget: 0)
                reloadWidgets()
                return
            }
            var budgetRequest = URLRequest(url: budgetURL)
            BackendConfig.addApiKey(to: &budgetRequest)

            URLSession.shared.dataTask(with: budgetRequest) { budgetData, _, _ in
                var monthlyBudget = 0.0
                if let budgetData = budgetData,
                   let obj = try? JSONSerialization.jsonObject(with: budgetData) as? [String: Any] {
                    if let v = obj["monthlyNet"] as? Double { monthlyBudget = v }
                    else if let s = obj["monthlyNet"] as? String, let v = Double(s) { monthlyBudget = v }
                }
                writeFinancial(period: "monthly", totalSpent: monthlySpent, totalBudget: monthlyBudget)
                writeFinancial(period: "weekly",  totalSpent: weeklySpent,  totalBudget: monthlyBudget > 0 ? monthlyBudget / 4.0 : 0)
                reloadWidgets()
            }.resume()
        }.resume()
    }

    private struct FinancialPeriodFile: Decodable {
        let totals: [String: Double]?
        let days: [String: [String: Double]]?
    }
}
