//
//  SpendingFeedbackView.swift
//  PlotLine
//
//  Monthly Costs → Feedback: this month against last month or the 3- or 6-month average (of the
//  months that were tracked), a 6-month spending trend, each category this month vs the average,
//  each category against its budget with pace ("day 13 of 31"), and the biggest changes.
//  Fixed costs are in every month's totals, counted once.
//

import Charts
import SwiftUI

enum FeedbackCompare: String, CaseIterable, Identifiable {
    case last, three = "3", six = "6"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .last: return "Last month"
        case .three: return "3 months"
        case .six: return "6 months"
        }
    }
}

struct SpendingFeedbackView: View {
    let feedback: MonthlyFeedback?
    @Binding var compare: FeedbackCompare
    /// the budget by category, and this month's spending by category (fixed costs counted once)
    let budget: [String: Double]
    let spent: [String: Double]
    let month: Date
    /// fixed costs (lower-cased): counted in full from the 1st, so they're not judged on pace
    var fixed: Set<String> = []

    private func isFixed(_ category: String) -> Bool { fixed.contains(category.lowercased()) }

    private var comparedLabel: String {
        guard let fb = feedback else { return "" }
        let n = fb.monthsCompared ?? 0
        return n <= 1 ? "last month" : "your \(n)-month average"
    }

    var body: some View {
        VStack(spacing: PLSpacing.lg) {
            Picker("Compare with", selection: $compare) {
                ForEach(FeedbackCompare.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if let fb = feedback, (fb.monthsCompared ?? 0) > 0 {
                summary(fb).plCard()
                if let history = fb.history, history.contains(where: \.tracked) { trend(history, current: fb.month).plCard() }
                categoryChart(fb).plCard()
            } else {
                VStack(spacing: PLSpacing.sm) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 36)).foregroundColor(PLColor.textSecondary)
                    Text("Nothing to compare yet").font(.headline)
                    Text("Once a past month has spending in it, you'll see how this month compares. Linking a bank or card in the budget quiz brings in the last 3 months.")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .plCard()
            }
            if !budget.isEmpty { budgetVsActual.plCard() }
            if let fb = feedback, (fb.monthsCompared ?? 0) > 0 { biggestChanges(fb).plCard() }
        }
    }

    // MARK: Summary

    private func summary(_ fb: MonthlyFeedback) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This month vs \(comparedLabel)").font(.headline)
            HStack {
                VStack(alignment: .leading) {
                    Text("This month").font(.caption).foregroundColor(PLColor.textSecondary)
                    Text(fb.totalCurrent.dollars()).font(.title3.weight(.bold))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text((fb.monthsCompared ?? 0) <= 1 ? "Last month" : "Average").font(.caption).foregroundColor(PLColor.textSecondary)
                    Text(fb.totalPrevious.dollars()).font(.title3.weight(.bold))
                }
            }
            let delta = fb.totalCurrent - fb.totalPrevious
            Text(delta <= 0 ? "\((-delta).dollars()) less so far" : "\(delta.dollars()) more so far")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(delta <= 0 ? PLColor.success : PLColor.danger)
            if isCurrentMonth {
                Text("The month isn't over yet, so this will grow.").font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    // MARK: Charts

    private static let monthKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private func shortMonth(_ key: String) -> String {
        Self.monthKey.date(from: key).map { $0.formatted(.dateTime.month(.abbreviated)) } ?? key
    }

    private func trend(_ history: [MonthTotal], current: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending by month").font(.headline)
            Chart(history) { m in
                BarMark(x: .value("Month", shortMonth(m.month)), y: .value("Spent", m.tracked ? m.total : 0))
                    .foregroundStyle(m.month == current ? PLColor.accent : PLColor.accent.opacity(0.35))
                    .annotation(position: .top) {
                        if m.tracked {
                            Text(m.total.dollars()).font(.system(size: 9)).foregroundColor(PLColor.textSecondary)
                        }
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 160)
            if history.contains(where: { !$0.tracked }) {
                Text("Months with no spending tracked are left empty.").font(.caption2).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    private struct Bar: Identifiable {
        let id = UUID()
        let category: String
        let series: String
        let amount: Double
    }

    private func categoryChart(_ fb: MonthlyFeedback) -> some View {
        let top = fb.deltas.sorted { max($0.current, $0.previous) > max($1.current, $1.previous) }.prefix(6)
        let compared = (fb.monthsCompared ?? 0) <= 1 ? "Last month" : "Average"
        let bars = top.flatMap { d in
            [Bar(category: d.category, series: "This month", amount: d.current),
             Bar(category: d.category, series: compared, amount: d.previous)]
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("By category").font(.headline)
            Chart(bars) { bar in
                BarMark(x: .value("Amount", bar.amount), y: .value("Category", bar.category))
                    .foregroundStyle(by: .value("When", bar.series))
                    .position(by: .value("When", bar.series))
            }
            .chartForegroundStyleScale(["This month": PLColor.accent, compared: Color.gray.opacity(0.5)])
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: CGFloat(max(1, top.count)) * 44 + 40)
        }
    }

    // MARK: Budget vs actual

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    /// how far through the month (1 for a past month)
    private var monthDone: Double {
        guard isCurrentMonth, let days = Calendar.current.range(of: .day, in: .month, for: month)?.count else { return 1 }
        return Double(Calendar.current.component(.day, from: Date())) / Double(days)
    }

    /// flexible lines first (most used first), then fixed ones
    private var budgetLines: [String] {
        func used(_ line: String) -> Double { (spent[line] ?? 0) / max(1, budget[line] ?? 1) }
        return budget.filter { $0.value > 0 }.map(\.key).sorted { a, b in
            if isFixed(a) != isFixed(b) { return !isFixed(a) }
            return used(a) > used(b)
        }
    }

    private var budgetVsActual: some View {
        let lines: [String] = budgetLines
        let flexible: [String] = lines.filter { !isFixed($0) }
        let totalBudget: Double = flexible.map { budget[$0] ?? 0 }.reduce(0, +)
        let totalSpent: Double = flexible.map { spent[$0] ?? 0 }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Budget vs actual").font(.headline)
            if isCurrentMonth, let days = Calendar.current.range(of: .day, in: .month, for: month)?.count {
                let day = Calendar.current.component(.day, from: Date())
                let share = totalBudget > 0 ? totalSpent / totalBudget : 0
                Text("Day \(day) of \(days): \(Int((share * 100).rounded()))% of your flexible budget spent, \(Int((monthDone * 100).rounded()))% of the month gone.")
                    .font(.subheadline)
                    .foregroundColor(share > monthDone + 0.1 ? .orange : PLColor.textSecondary)
            }
            ForEach(lines, id: \.self) { line in
                let limit = budget[line] ?? 0, used = spent[line] ?? 0
                let share = limit > 0 ? used / limit : 0
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(line).font(.subheadline)
                        Spacer()
                        Text("\(used.dollars()) of \(limit.dollars())").font(.subheadline.monospacedDigit())
                    }
                    ProgressView(value: min(1, share))
                        .tint(share > 1 ? PLColor.danger : isFixed(line) ? Color.gray : share > monthDone + 0.1 ? .orange : PLColor.success)
                    if isFixed(line) {
                        Text("Fixed: counted in full every month").font(.caption).foregroundColor(PLColor.textSecondary)
                    } else if share > 1 {
                        Text("\((used - limit).dollars()) over").font(.caption).foregroundColor(PLColor.danger)
                    } else if isCurrentMonth && share > monthDone + 0.1 {
                        Text("Ahead of pace for this point in the month").font(.caption).foregroundColor(.orange)
                    }
                }
            }
        }
    }

    // MARK: Biggest changes

    private func biggestChanges(_ fb: MonthlyFeedback) -> some View {
        let new = fb.deltas.filter { $0.previous == 0 && $0.current > 0 }.sorted { $0.current > $1.current }
        let ups = fb.deltas.filter { $0.previous > 0 && $0.delta > 0 }.sorted { $0.delta > $1.delta }.prefix(3)
        let downs = fb.deltas.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }.prefix(3)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Biggest changes").font(.headline)
            if ups.isEmpty && downs.isEmpty && new.isEmpty {
                Text("About the same as \(comparedLabel).").font(.subheadline).foregroundColor(PLColor.textSecondary)
            }
            if !ups.isEmpty {
                Text("Up").font(.caption.weight(.semibold)).foregroundColor(PLColor.textSecondary)
                ForEach(Array(ups)) { change($0, color: PLColor.danger) }
            }
            if !downs.isEmpty {
                Text("Down").font(.caption.weight(.semibold)).foregroundColor(PLColor.textSecondary)
                ForEach(Array(downs)) { change($0, color: PLColor.success) }
            }
            if !new.isEmpty {
                Text("New this month").font(.caption.weight(.semibold)).foregroundColor(PLColor.textSecondary)
                ForEach(new) { d in
                    HStack { Text(d.category); Spacer(); Text(d.current.dollars()).monospacedDigit() }.font(.subheadline)
                }
            }
        }
    }

    private func change(_ d: CategoryDelta, color: Color) -> some View {
        HStack {
            Text(d.category)
            Spacer()
            Text("\(d.previous.dollars()) → \(d.current.dollars())").foregroundColor(PLColor.textSecondary).monospacedDigit()
            Text(d.delta > 0 ? "+\(d.delta.dollars())" : "−\((-d.delta).dollars())").foregroundColor(color).monospacedDigit()
        }
        .font(.subheadline)
    }
}
