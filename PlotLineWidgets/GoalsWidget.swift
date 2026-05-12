// GoalsWidget.swift — PlotLineWidgets target
// Shows an overview of weekly goals, or a specific goal if the user picks one.

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct GoalsEntry: TimelineEntry {
    let date: Date
    let goals: [GoalWidgetItem]
    let selectedGoal: GoalWidgetItem?
}

// MARK: - Provider

struct GoalsProvider: AppIntentTimelineProvider {
    typealias Intent = GoalSelectionIntent
    typealias Entry  = GoalsEntry

    func placeholder(in context: Context) -> GoalsEntry {
        GoalsEntry(date: Date(), goals: sampleGoals, selectedGoal: nil)
    }

    func snapshot(for configuration: GoalSelectionIntent, in context: Context) async -> GoalsEntry {
        let goals = readGoalsData()
        let selected = configuration.goal.flatMap { entity in goals.first { $0.id == entity.id } }
        return GoalsEntry(date: Date(), goals: goals, selectedGoal: selected)
    }

    func timeline(for configuration: GoalSelectionIntent, in context: Context) async -> Timeline<GoalsEntry> {
        let goals = readGoalsData()
        let selected = configuration.goal.flatMap { entity in goals.first { $0.id == entity.id } }
        let entry = GoalsEntry(date: Date(), goals: goals, selectedGoal: selected)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }

    private var sampleGoals: [GoalWidgetItem] {
        [
            GoalWidgetItem(id: 1, name: "Exercise daily",   isCompleted: true,  priority: "High",   isFinancialGoal: false, progress: nil),
            GoalWidgetItem(id: 2, name: "Read 30 min/day",  isCompleted: false, priority: "Medium", isFinancialGoal: false, progress: nil),
            GoalWidgetItem(id: 3, name: "Drink 8 glasses",  isCompleted: false, priority: "Low",    isFinancialGoal: false, progress: nil),
        ]
    }
}

// MARK: - Widget

struct GoalsWidget: Widget {
    let kind = "GoalsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: GoalSelectionIntent.self, provider: GoalsProvider()) { entry in
            GoalsWidgetView(entry: entry)
                .widgetURL(URL(string: "plotline://goals"))
        }
        .configurationDisplayName("Goal Tracker")
        .description("Track a specific goal or see an overview of all your weekly goals.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Root View

struct GoalsWidgetView: View {
    let entry: GoalsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let goal = entry.selectedGoal {
            switch family {
            case .systemLarge: SingleGoalLargeView(goal: goal)
            default:           SingleGoalMediumView(goal: goal)
            }
        } else {
            switch family {
            case .systemLarge: GoalsOverviewLargeView(entry: entry)
            default:           GoalsOverviewMediumView(entry: entry)
            }
        }
    }
}

// MARK: - Single Goal Medium

struct SingleGoalMediumView: View {
    let goal: GoalWidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target").foregroundColor(.blue)
                Text("Goal").font(.headline)
                Spacer()
                PriorityBadge(priority: goal.priority)
            }

            HStack(spacing: 12) {
                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.largeTitle)
                    .foregroundColor(goal.isCompleted ? .green : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name).font(.subheadline.bold()).lineLimit(2)
                    Text(goal.isCompleted ? "Completed" : "In Progress")
                        .font(.caption)
                        .foregroundColor(goal.isCompleted ? .green : .secondary)
                }
            }

            if goal.isFinancialGoal, let progress = goal.progress {
                BudgetProgressBar(fraction: progress)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Single Goal Large

struct SingleGoalLargeView: View {
    let goal: GoalWidgetItem

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Image(systemName: "target").foregroundColor(.blue)
                Text("Goal Tracker").font(.headline)
                Spacer()
            }

            Spacer()

            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 64))
                .foregroundColor(goal.isCompleted ? .green : .secondary)

            Text(goal.name).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(3)

            Text(goal.isCompleted ? "Goal Completed!" : "Keep going!")
                .font(.subheadline)
                .foregroundColor(goal.isCompleted ? .green : .secondary)

            PriorityBadge(priority: goal.priority)

            if goal.isFinancialGoal, let progress = goal.progress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Budget Progress").font(.caption).foregroundColor(.secondary)
                    BudgetProgressBar(fraction: progress)
                    Text("\(Int(min(progress, 1.0) * 100))% used")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Overview Medium

struct GoalsOverviewMediumView: View {
    let entry: GoalsEntry

    private var displayGoals: [GoalWidgetItem] { Array(entry.goals.prefix(4)) }
    private var completedCount: Int { entry.goals.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                Text("Weekly Goals").font(.headline)
                Spacer()
                Text("\(completedCount)/\(entry.goals.count)").font(.caption.bold()).foregroundColor(.secondary)
            }

            if entry.goals.isEmpty {
                Spacer()
                Text("No goals set").font(.subheadline).foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(displayGoals) { goal in
                    GoalRow(goal: goal)
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

// MARK: - Overview Large

struct GoalsOverviewLargeView: View {
    let entry: GoalsEntry

    private var regularGoals: [GoalWidgetItem]   { entry.goals.filter { !$0.isFinancialGoal } }
    private var financialGoals: [GoalWidgetItem] { entry.goals.filter { $0.isFinancialGoal } }
    private var completedCount: Int              { entry.goals.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                Text("Weekly Goals").font(.headline)
                Spacer()
                Text("\(completedCount)/\(entry.goals.count) done").font(.caption.bold()).foregroundColor(.secondary)
            }

            // Overall progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: entry.goals.isEmpty ? 0 : geo.size.width * Double(completedCount) / Double(entry.goals.count))
                }
            }
            .frame(height: 6)

            if regularGoals.isEmpty && financialGoals.isEmpty {
                Spacer()
                Text("No goals set").foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(regularGoals.prefix(6)) { goal in
                    HStack(spacing: 8) {
                        Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundColor(goal.isCompleted ? .green : .secondary)
                        Text(goal.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .strikethrough(goal.isCompleted, color: .secondary)
                        Spacer()
                        PriorityBadge(priority: goal.priority)
                    }
                }

                if !financialGoals.isEmpty {
                    Divider()
                    ForEach(financialGoals.prefix(2)) { goal in
                        HStack(spacing: 8) {
                            Image(systemName: "dollarsign.circle").font(.subheadline).foregroundColor(.green)
                            Text(goal.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            if let progress = goal.progress {
                                Text("\(Int(min(progress, 1.0) * 100))%")
                                    .font(.caption)
                                    .foregroundColor(progress > 1.0 ? .red : .green)
                            }
                        }
                    }
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(goal.isCompleted ? .green : .secondary)
            Text(goal.name).font(.caption).lineLimit(1)
            Spacer()
            Circle().fill(priorityColor(goal.priority)).frame(width: 6, height: 6)
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

private struct BudgetProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2))
                Capsule()
                    .fill(fraction > 1.0 ? Color.red : Color.green)
                    .frame(width: geo.size.width * min(fraction, 1.0))
            }
        }
        .frame(height: 8)
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
