// CombinedWidget.swift — PlotLineWidgets target
// One large widget showing calories, budget, and goals at a glance.

import WidgetKit
import SwiftUI

// MARK: - Entry

struct CombinedEntry: TimelineEntry {
    let date: Date
    let nutrition: NutritionWidgetData
    let goals: [GoalWidgetItem]
    let financial: FinancialWidgetData
}

// MARK: - Provider

struct CombinedProvider: TimelineProvider {
    func placeholder(in context: Context) -> CombinedEntry {
        CombinedEntry(date: Date(), nutrition: .empty, goals: [], financial: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (CombinedEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CombinedEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> CombinedEntry {
        CombinedEntry(
            date: Date(),
            nutrition: readNutritionData(),
            goals: readGoalsData(),
            financial: readFinancialData(period: "weekly")
        )
    }
}

// MARK: - Widget

struct CombinedWidget: Widget {
    let kind = "PlotLineOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CombinedProvider()) { entry in
            CombinedWidgetView(entry: entry)
        }
        .configurationDisplayName("PlotLine Overview")
        .description("See your calories, budget, and goals at a glance.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - View

struct CombinedWidgetView: View {
    let entry: CombinedEntry

    private var regularGoals: [GoalWidgetItem] { entry.goals.filter { !$0.isFinancialGoal } }
    private var completedCount: Int { entry.goals.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("PlotLine").font(.headline.bold())
                Spacer()
                Text(todayLabel).font(.caption).foregroundColor(.secondary)
            }

            Divider()

            // Calories row
            Link(destination: URL(string: "plotline://nutrition")!) {
                OverviewRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    title: "Calories",
                    detail: "\(Int(entry.nutrition.calories)) / \(Int(entry.nutrition.calorieGoal)) kcal",
                    fraction: entry.nutrition.calorieFraction,
                    barColor: calorieBarColor(entry.nutrition.calorieFraction)
                )
            }

            // Budget row
            Link(destination: URL(string: "plotline://budget")!) {
                OverviewRow(
                    icon: "dollarsign.circle.fill",
                    iconColor: .green,
                    title: "Weekly Budget",
                    detail: "$\(Int(entry.financial.totalSpent)) / $\(Int(entry.financial.totalBudget))",
                    fraction: entry.financial.fraction,
                    barColor: budgetBarColor(entry.financial)
                )
            }

            Divider()

            // Goals section
            Link(destination: URL(string: "plotline://goals")!) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                        Text("Weekly Goals").font(.subheadline.bold()).foregroundColor(.primary)
                        Spacer()
                        Text("\(completedCount)/\(entry.goals.count)")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    if regularGoals.isEmpty {
                        Text("No goals set").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(regularGoals.prefix(4)) { goal in
                            HStack(spacing: 6) {
                                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                    .foregroundColor(goal.isCompleted ? .green : .secondary)
                                Text(goal.name).font(.caption).lineLimit(1).foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        if regularGoals.count > 4 {
                            Text("+\(regularGoals.count - 4) more").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Sub-views

private struct OverviewRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    let fraction: Double
    let barColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(iconColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(detail).font(.subheadline.bold()).foregroundColor(.primary)
            }
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule().fill(barColor).frame(width: geo.size.width * fraction)
                }
            }
            .frame(width: 80, height: 8)
        }
    }
}

// MARK: - Helpers

private var todayLabel: String {
    let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: Date())
}

private func calorieBarColor(_ fraction: Double) -> Color {
    if fraction > 1.0 { return .red }
    if fraction > 0.85 { return .orange }
    return .green
}

private func budgetBarColor(_ data: FinancialWidgetData) -> Color {
    if data.totalBudget == 0 { return .blue }
    if data.isOverBudget     { return .red }
    if data.fraction > 0.85  { return .orange }
    return .green
}
