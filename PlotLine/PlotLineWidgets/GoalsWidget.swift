// GoalsWidget.swift — PlotLineWidgets target
// Shows weekly goals or long-term goals (user-configurable).

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct GoalsEntry: TimelineEntry {
    let date: Date
    let goals: [GoalWidgetItem]
    let period: GoalPeriod
}

// MARK: - Provider

struct GoalsProvider: AppIntentTimelineProvider {
    typealias Intent = GoalPeriodIntent
    typealias Entry  = GoalsEntry

    func placeholder(in context: Context) -> GoalsEntry {
        GoalsEntry(date: Date(), goals: sampleGoals, period: .weekly)
    }

    func snapshot(for configuration: GoalPeriodIntent, in context: Context) async -> GoalsEntry {
        let period = configuration.period
        let cached = period == .longTerm ? readLongTermGoalsData() : readGoalsData()
        let goals = !cached.isEmpty ? cached : (await fetchLive(period: period) ?? [])
        return GoalsEntry(date: Date(), goals: goals, period: period)
    }

    func timeline(for configuration: GoalPeriodIntent, in context: Context) async -> Timeline<GoalsEntry> {
        let period = configuration.period
        // Prefer UserDefaults (written optimistically on every toggle) so the widget
        // reflects changes even when the user closes the app before the PUT returns.
        // Fall back to a live network fetch when UserDefaults is empty (first launch).
        let cached = period == .longTerm ? readLongTermGoalsData() : readGoalsData()
        let goals = !cached.isEmpty ? cached : (await fetchLive(period: period) ?? [])
        let entry = GoalsEntry(date: Date(), goals: goals, period: period)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func fetchLive(period: GoalPeriod) async -> [GoalWidgetItem]? {
        let defaults = UserDefaults.widgetShared
        let username = defaults.string(forKey: WidgetKey.username) ?? ""
        let baseURL  = defaults.string(forKey: WidgetKey.baseURL)  ?? ""
        let apiKey   = defaults.string(forKey: WidgetKey.apiKey)   ?? ""
        guard !username.isEmpty, !baseURL.isEmpty else { return nil }

        if period == .weekly {
            guard let url = URL(string: "\(baseURL)/api/goals/\(username)") else { return nil }
            var request = URLRequest(url: url)
            if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let response = try? JSONDecoder().decode(WeeklyGoalsResponse.self, from: data) else { return nil }
            return response.weeklyGoals.map { task in
                GoalWidgetItem(
                    id: task.id,
                    name: task.name,
                    isCompleted: task.completed,
                    priority: task.priority,
                    isFinancialGoal: task.isFinancialGoal ?? false,
                    progress: task.progress
                )
            }
        } else {
            guard let url = URL(string: "\(baseURL)/api/goals/\(username)/long-term") else { return nil }
            var request = URLRequest(url: url)
            if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let response = try? JSONDecoder().decode(LongTermGoalsResponse.self, from: data) else { return nil }
            return response.longTermGoals.enumerated().map { (index, goal) in
                let completedSteps = goal.steps.filter { $0.completed }.count
                let totalSteps = goal.steps.count
                let allDone = totalSteps > 0 && completedSteps == totalSteps
                let progress: Double? = totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : nil
                return GoalWidgetItem(
                    id: index + 1,
                    name: goal.title,
                    isCompleted: allDone,
                    priority: "Medium",
                    isFinancialGoal: false,
                    progress: progress
                )
            }
        }
    }

    private var sampleGoals: [GoalWidgetItem] {
        [
            GoalWidgetItem(id: 1, name: "Exercise daily",  isCompleted: true,  priority: "High",   isFinancialGoal: false, progress: nil),
            GoalWidgetItem(id: 2, name: "Read 30 min/day", isCompleted: false, priority: "Medium", isFinancialGoal: false, progress: nil),
            GoalWidgetItem(id: 3, name: "Drink 8 glasses", isCompleted: false, priority: "Low",    isFinancialGoal: false, progress: nil),
        ]
    }
}

// MARK: - Decodable helpers (widget-only, no dependency on main app models)

private struct WeeklyGoalsResponse: Decodable {
    let weeklyGoals: [WeeklyGoalItem]
}

private struct WeeklyGoalItem: Decodable {
    let id: Int
    let name: String
    let completed: Bool
    let priority: String
    let isFinancialGoal: Bool?
    let progress: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, priority, isFinancialGoal, progress
        case completed = "completed"
    }
}

private struct LongTermGoalsResponse: Decodable {
    let longTermGoals: [LongTermGoalItem]
}

private struct LongTermGoalItem: Decodable {
    let title: String
    let steps: [LongTermStepItem]
}

private struct LongTermStepItem: Decodable {
    let name: String
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case completed = "completed"
    }
}

// MARK: - Widget

struct GoalsWidget: Widget {
    let kind = "GoalsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: GoalPeriodIntent.self, provider: GoalsProvider()) { entry in
            GoalsWidgetView(entry: entry)
                .widgetURL(URL(string: "plotline://goals"))
        }
        .configurationDisplayName("Goal Tracker")
        .description("Track your weekly goals or long-term goals.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Root View

struct GoalsWidgetView: View {
    let entry: GoalsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemLarge:          GoalsOverviewLargeView(entry: entry)
        case .accessoryCircular:    GoalsCircularView(entry: entry)
        case .accessoryRectangular: GoalsRectangularView(entry: entry)
        default:                    GoalsOverviewMediumView(entry: entry)
        }
    }
}

// MARK: - Lock Screen Circular

struct GoalsCircularView: View {
    let entry: GoalsEntry
    private var completedCount: Int { entry.goals.filter(\.isCompleted).count }
    private var total: Int { entry.goals.count }
    private var fraction: Double { total > 0 ? Double(completedCount) / Double(total) : 0 }

    var body: some View {
        Gauge(value: fraction) {
            Image(systemName: "checkmark.circle.fill")
        } currentValueLabel: {
            Text("\(completedCount)/\(total)")
                .font(.system(.body, design: .rounded).bold())
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Lock Screen Rectangular

struct GoalsRectangularView: View {
    let entry: GoalsEntry
    private var completedCount: Int { entry.goals.filter(\.isCompleted).count }
    private var periodLabel: String { entry.period == .longTerm ? "Long-Term Goals" : "Weekly Goals" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(periodLabel)  \(completedCount)/\(entry.goals.count)", systemImage: "checkmark.circle.fill")
                .font(.caption).widgetAccentable()
            ForEach(entry.goals.prefix(2)) { goal in
                Label {
                    Text(goal.name).lineLimit(1)
                } icon: {
                    Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                }
                .font(.caption2)
                .foregroundStyle(goal.isCompleted ? .secondary : .primary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Medium

struct GoalsOverviewMediumView: View {
    let entry: GoalsEntry

    private var displayGoals: [GoalWidgetItem] { Array(entry.goals.prefix(4)) }
    private var completedCount: Int { entry.goals.filter(\.isCompleted).count }
    private var periodLabel: String { entry.period == .longTerm ? "Long-Term Goals" : "Weekly Goals" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                Text(periodLabel).font(.headline)
                Spacer()
                Text("\(completedCount)/\(entry.goals.count)").font(.caption.bold()).foregroundColor(.secondary)
            }

            if entry.goals.isEmpty {
                Spacer()
                Text("No goals set").font(.subheadline).foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(displayGoals) { goal in
                    GoalRow(goal: goal, showProgress: entry.period == .longTerm)
                }
                if entry.goals.count > 4 {
                    Text("+\(entry.goals.count - 4) more").font(.caption2).foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large

struct GoalsOverviewLargeView: View {
    let entry: GoalsEntry

    private var completedCount: Int { entry.goals.filter(\.isCompleted).count }
    private var periodLabel: String { entry.period == .longTerm ? "Long-Term Goals" : "Weekly Goals" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                Text(periodLabel).font(.headline)
                Spacer()
                Text("\(completedCount)/\(entry.goals.count) done").font(.caption.bold()).foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: entry.goals.isEmpty ? 0 : geo.size.width * Double(completedCount) / Double(entry.goals.count))
                }
            }
            .frame(height: 6)

            if entry.goals.isEmpty {
                Spacer()
                Text("No goals set").foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(entry.goals.prefix(8)) { goal in
                    GoalRow(goal: goal, showProgress: entry.period == .longTerm)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Shared sub-views

private struct GoalRow: View {
    let goal: GoalWidgetItem
    let showProgress: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundColor(goal.isCompleted ? .green : .secondary)
            Text(goal.name)
                .font(.footnote)
                .lineLimit(1)
                .foregroundColor(goal.isCompleted ? .secondary : .primary)
                .strikethrough(goal.isCompleted, color: .secondary)
            Spacer()
            if showProgress, let progress = goal.progress {
                Text("\(Int(min(progress, 1.0) * 100))%")
                    .font(.caption2)
                    .foregroundColor(progress >= 1.0 ? .green : .secondary)
            } else {
                Circle().fill(priorityColor(goal.priority)).frame(width: 8, height: 8)
            }
        }
    }
}

struct PriorityBadge: View {
    let priority: String

    var body: some View {
        Text(priority)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(priorityColor(priority).opacity(0.15))
            .foregroundColor(priorityColor(priority))
            .clipShape(Capsule())
    }
}

// MARK: - Helpers

func priorityColor(_ priority: String) -> Color {
    switch priority {
    case "High":   return .red
    case "Medium": return .orange
    default:       return .green
    }
}
