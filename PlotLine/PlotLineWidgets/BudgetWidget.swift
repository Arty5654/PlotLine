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
        let data = await fetchLive(period: period) ?? readFinancialData(period: period)
        return BudgetEntry(date: Date(), data: data, period: period)
    }

    func timeline(for configuration: BudgetPeriodIntent, in context: Context) async -> Timeline<BudgetEntry> {
        let period = configuration.period.rawValue.lowercased()
        let data = await fetchLive(period: period) ?? readFinancialData(period: period)
        let entry = BudgetEntry(date: Date(), data: data, period: period)
        // Refresh every 30 minutes even with app closed
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }

    // Fetches financial data using the same endpoints the budget chart uses.
    private func fetchLive(period: String) async -> FinancialWidgetData? {
        let defaults = UserDefaults.widgetShared
        let username = defaults.string(forKey: WidgetKey.username) ?? ""
        let baseURL  = defaults.string(forKey: WidgetKey.baseURL)  ?? ""
        let apiKey   = defaults.string(forKey: WidgetKey.apiKey)   ?? ""
        guard !username.isEmpty, !baseURL.isEmpty else { return nil }

        let now = Date()
        let monthFmt = DateFormatter()
        monthFmt.calendar = .init(identifier: .gregorian)
        monthFmt.dateFormat = "yyyy-MM"
        let currentMonth = monthFmt.string(from: now)

        guard let costsURL = URL(string: "\(baseURL)/api/costs/monthly/\(username)?month=\(currentMonth)") else { return nil }
        var costsRequest = URLRequest(url: costsURL)
        if !apiKey.isEmpty { costsRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }

        guard let (costsData, _) = try? await URLSession.shared.data(for: costsRequest),
              let periodData = try? JSONDecoder().decode(BudgetPeriodFile.self, from: costsData) else { return nil }

        let excluded: Set<String> = ["401(k)", "401k", "401(k) Contribution", "401k Contribution"]

        let totalSpent: Double
        if period == "weekly" {
            let cal = Calendar(identifier: .gregorian)
            let weekday = cal.component(.weekday, from: now)
            let weekStart = cal.date(byAdding: .day, value: -(weekday - 1), to: cal.startOfDay(for: now)) ?? now
            let dayFmt = DateFormatter()
            dayFmt.calendar = .init(identifier: .gregorian)
            dayFmt.dateFormat = "yyyy-MM-dd"
            totalSpent = (periodData.days ?? [:])
                .filter { (k, _) in
                    guard let d = dayFmt.date(from: k) else { return false }
                    return d >= weekStart && d <= now
                }
                .values
                .flatMap { $0.filter { !excluded.contains($0.key) }.values }
                .reduce(0, +)
        } else {
            totalSpent = (periodData.totals ?? [:])
                .filter { !excluded.contains($0.key) }
                .values.reduce(0, +)
        }

        guard let budgetURL = URL(string: "\(baseURL)/api/llm/budget/last/\(username)") else {
            return FinancialWidgetData(totalSpent: totalSpent, totalBudget: 0)
        }
        var budgetRequest = URLRequest(url: budgetURL)
        if !apiKey.isEmpty { budgetRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }

        var monthlyBudget = 0.0
        if let (budgetData, _) = try? await URLSession.shared.data(for: budgetRequest),
           let obj = try? JSONSerialization.jsonObject(with: budgetData) as? [String: Any] {
            if let v = obj["monthlyNet"] as? Double { monthlyBudget = v }
            else if let s = obj["monthlyNet"] as? String, let v = Double(s) { monthlyBudget = v }
        }

        let totalBudget = period == "weekly" ? (monthlyBudget > 0 ? monthlyBudget / 4.0 : 0) : monthlyBudget
        return FinancialWidgetData(totalSpent: totalSpent, totalBudget: totalBudget)
    }
}

private struct BudgetPeriodFile: Decodable {
    let totals: [String: Double]?
    let days: [String: [String: Double]]?
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
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Root View

struct BudgetWidgetView: View {
    let entry: BudgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemLarge:           BudgetLargeView(entry: entry)
        case .accessoryCircular:     BudgetCircularView(entry: entry)
        case .accessoryRectangular:  BudgetRectangularView(entry: entry)
        default:                     BudgetMediumView(entry: entry)
        }
    }
}

// MARK: - Lock Screen Circular

struct BudgetCircularView: View {
    let entry: BudgetEntry
    private var data: FinancialWidgetData { entry.data }
    private var periodLabel: String { entry.period == "monthly" ? "Mo" : "Wk" }

    var body: some View {
        Gauge(value: data.fraction) {
            Text(periodLabel).font(.caption2)
        } currentValueLabel: {
            Text("$\(Int(data.totalSpent))")
                .font(.system(.body, design: .rounded).bold())
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Lock Screen Rectangular

struct BudgetRectangularView: View {
    let entry: BudgetEntry
    private var data: FinancialWidgetData { entry.data }
    private var periodLabel: String { entry.period == "monthly" ? "Monthly" : "Weekly" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(periodLabel) Budget", systemImage: "dollarsign.circle.fill")
                .font(.caption).widgetAccentable()
            Text("$\(Int(data.totalSpent)) spent")
                .font(.headline)
            if data.totalBudget > 0 {
                Text(data.isOverBudget
                     ? "Over by $\(Int(data.totalSpent - data.totalBudget))"
                     : "$\(Int(data.remaining)) left of $\(Int(data.totalBudget))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No budget set").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
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
