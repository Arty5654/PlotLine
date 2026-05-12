// BudgetWidget.swift — PlotLineWidgets target
// Shows weekly or monthly spending vs budget (user-configurable).

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct BudgetEntry: TimelineEntry {
    let date: Date
    let data: FinancialWidgetData
    let period: String
}

// MARK: - Provider

struct BudgetProvider: AppIntentTimelineProvider {
    typealias Intent = BudgetPeriodIntent
    typealias Entry  = BudgetEntry

    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: Date(), data: .empty, period: "weekly")
    }

    func snapshot(for configuration: BudgetPeriodIntent, in context: Context) async -> BudgetEntry {
        let period = configuration.period.rawValue.lowercased()
        return BudgetEntry(date: Date(), data: readFinancialData(period: period), period: period)
    }

    func timeline(for configuration: BudgetPeriodIntent, in context: Context) async -> Timeline<BudgetEntry> {
        let period = configuration.period.rawValue.lowercased()
        let entry = BudgetEntry(date: Date(), data: readFinancialData(period: period), period: period)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }
}

// MARK: - Widget

struct BudgetWidget: Widget {
    let kind = "BudgetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: BudgetPeriodIntent.self, provider: BudgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
                .widgetURL(URL(string: "plotline://budget"))
        }
        .configurationDisplayName("Budget Tracker")
        .description("Track your weekly or monthly spending versus your budget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Root View

struct BudgetWidgetView: View {
    let entry: BudgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemLarge: BudgetLargeView(entry: entry)
        default:           BudgetMediumView(entry: entry)
        }
    }
}

// MARK: - Medium

struct BudgetMediumView: View {
    let entry: BudgetEntry

    private var data: FinancialWidgetData { entry.data }
    private var periodLabel: String { entry.period == "monthly" ? "Monthly" : "Weekly" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").foregroundColor(.green)
                Text("\(periodLabel) Budget").font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.2))
                        Capsule()
                            .fill(budgetColor(data))
                            .frame(width: geo.size.width * data.fraction)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("$\(Int(data.totalSpent)) spent").font(.subheadline.bold())
                    Spacer()
                    Text(data.totalBudget > 0 ? "Budget: $\(Int(data.totalBudget))" : "No budget set")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if data.totalBudget > 0 {
                Text(data.isOverBudget
                     ? "Over budget by $\(Int(data.totalSpent - data.totalBudget))"
                     : "$\(Int(data.remaining)) remaining")
                    .font(.caption)
                    .foregroundColor(data.isOverBudget ? .red : .secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large

struct BudgetLargeView: View {
    let entry: BudgetEntry

    private var data: FinancialWidgetData { entry.data }
    private var periodLabel: String { entry.period == "monthly" ? "Monthly" : "Weekly" }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").foregroundColor(.green)
                Text("\(periodLabel) Budget").font(.headline)
                Spacer()
            }

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: data.fraction)
                    .stroke(
                        budgetColor(data),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text("$\(Int(data.totalSpent))").font(.title2.bold())
                    Text("spent").font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(width: 130, height: 130)

            VStack(spacing: 10) {
                BudgetRow(label: "Budget",
                          value: data.totalBudget > 0 ? "$\(Int(data.totalBudget))" : "Not set",
                          color: .primary)
                BudgetRow(label: "Spent",
                          value: "$\(Int(data.totalSpent))",
                          color: budgetColor(data))
                if data.totalBudget > 0 {
                    BudgetRow(label: data.isOverBudget ? "Over Budget" : "Remaining",
                              value: "$\(Int(abs(data.remaining)))",
                              color: data.isOverBudget ? .red : .green)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct BudgetRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundColor(color)
        }
    }
}

// MARK: - Helper

private func budgetColor(_ data: FinancialWidgetData) -> Color {
    if data.totalBudget == 0 { return .blue }
    if data.isOverBudget     { return .red }
    if data.fraction > 0.85  { return .orange }
    return .green
}
