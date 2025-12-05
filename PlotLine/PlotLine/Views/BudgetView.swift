//
//  BudgetView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/13/25.
//

import SwiftUI
import Charts
import Foundation
import LinkKit

// MARK: - Local tokens (scoped to this file)
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let danger         = Color.red
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius { static let md: CGFloat = 12 }

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

// MARK: - Root
struct BudgetView: View {
    @State private var selectedTab = "Budgeting"
    @EnvironmentObject var viewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Text("Budgeting").tag("Budgeting")
                    Text("Stocks").tag("Stocks")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, PLSpacing.lg)
                .padding(.vertical, PLSpacing.sm)

                Divider()

                Group {
                    if selectedTab == "Budgeting" {
                        ScrollView {
                            BudgetSection()
                                .environmentObject(viewModel)
                                .padding(.horizontal, PLSpacing.lg)
                                .padding(.vertical, PLSpacing.lg)
                        }
                    } else {
                        InvestmentHomeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text("Dashboard").font(.headline) } }
        }
    }
}

// MARK: - Budgeting Section
struct BudgetSection: View {
    @EnvironmentObject var calendarVM: CalendarViewModel
    @State private var chartType = "Weekly" // or "Monthly"
    @StateObject private var plaidCoordinator = PlaidLinkCoordinator()

    private var quizCompleted: Bool {
        UserDefaults.standard.bool(forKey: "budgetQuizCompleted")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.lg) {
            VStack(alignment: .leading, spacing: PLSpacing.xs) {
                Text("Budgeting").font(.title3).bold()
                Text("Track spending trends and manage your tools.")
                    .font(.subheadline).foregroundColor(PLColor.textSecondary)
            }
            .plCard()

            if !quizCompleted {
                NavigationLink { BudgetQuizView().environmentObject(calendarVM) } label: {
                    Label("Take the AI Powered Budget Quiz", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
            } else {
                // Trend chart card
                VStack(alignment: .leading, spacing: PLSpacing.md) {
                    HStack {
                        Text("Spending Trends").font(.headline)
                        Spacer()
                        Picker("Chart", selection: $chartType) {
                            Text("Weekly").tag("Weekly")
                            Text("Monthly").tag("Monthly")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }
                    SpendingTrendChartView(chartType: chartType)
                }
                .plCard()

                // Tools
                VStack(spacing: PLSpacing.sm) {
                    ActionRow(title: "Take the AI Powered Budget Quiz Again", system: "sparkles") {
                        BudgetQuizView().environmentObject(calendarVM)
                    }
                    ActionRow(title: "Upload a Receipt to Track Spending", system: "doc.viewfinder") {
                        ReceiptUploadView().environmentObject(calendarVM)
                    }
                    ActionRow(title: "Input Weekly/Monthly Costs", system: "square.and.pencil") {
                        WeeklyMonthlyCostView().environmentObject(calendarVM)
                    }
                    ActionRow(title: "Create Weekly/Monthly Budget", system: "list.bullet.rectangle.portrait") {
                        BudgetInputView()
                    }
                    ActionRow(title: "Compare New Income/Location Budget", system: "arrow.2.squarepath") {
                        BudgetCompareView()
                    }
                    Button {
                        Task { await startPlaidLink() }
                    } label: {
                        HStack(spacing: PLSpacing.md) {
                            Image(systemName: "creditcard").frame(width: 20)
                            Text("Track Credit Card Transactions Automatically")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundColor(PLColor.textSecondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, PLSpacing.md)
                        .background(PLColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
                    }
                }
            }
        }
    }
    
    private func startPlaidLink() async {
        guard let url = URL(string: "http://localhost:8080/api/plaid/link_token?username=\(currentUsername())"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let linkToken = obj["link_token"] as? String
        else { print("Failed to fetch link_token"); return }

        await presentPlaidLink(linkToken: linkToken, coordinator: plaidCoordinator) { publicToken, accountIds in
            Task { await exchange(publicToken: publicToken, selectedAccountIds: accountIds) }
        }
    }
    
    private func exchange(publicToken: String, selectedAccountIds: [String]) async {
        guard let url = URL(string: "http://localhost:8080/api/plaid/exchange") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "username": currentUsername(),
            "public_token": publicToken,
            "account_ids": selectedAccountIds
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)

        await MainActor.run { plaidCoordinator.handler = nil }
    }
    
    private func currentUsername() -> String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
}

private struct ActionRow<Destination: View>: View {
    let title: String
    let system: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: PLSpacing.md) {
                Image(systemName: system).frame(width: 20)
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote).foregroundColor(PLColor.textSecondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
        }
    }
}

// MARK: - Line/Area Chart (Weekly last 8 weeks | Monthly last 6 months)
struct SpendingTrendChartView: View {
    let chartType: String                  // "Weekly" or "Monthly"

    // State
    @State private var points: [TrendPoint] = []
    @State private var budgetTarget: Double = 0
    @State private var isLoading = false
    @State private var loadError: String?

    // Computed helpers (so the compiler doesn’t choke)
    private var pts: [TrendPoint] { points }
    private var target: Double { budgetTarget }
    private var axisDates: [Date] { points.map { $0.date } }

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {

            if isLoading && points.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading…").foregroundColor(PLColor.textSecondary)
                }
            }

            if let loadError, points.isEmpty {
                Text(loadError).font(.footnote).foregroundColor(PLColor.danger)
            }

            if !points.isEmpty {
                Chart {
                    // Single ForEach with multiple marks keeps type-checker happy
                    ForEach(pts) { p in
                        AreaMark(
                            x: .value("Date", p.date),
                            y: .value("Spent", p.total)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(PLColor.accent.opacity(0.20))

                        LineMark(
                            x: .value("Date", p.date),
                            y: .value("Spent", p.total)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(PLColor.accent)

                        PointMark(
                            x: .value("Date", p.date),
                            y: .value("Spent", p.total)
                        )
                        .foregroundStyle(PLColor.accent)
                    }

                    if target > 0 {
                        RuleMark(y: .value("Budget", target))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(PLColor.danger)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Budget: $\(target, specifier: "%.0f")")
                                    .font(.caption2)
                                    .foregroundColor(PLColor.danger)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text(chartType == "Weekly" ? d.asShortWeek() : d.asShortMonth())
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 240)
                .animation(.easeInOut, value: pts)
            } else if !isLoading {
                Text("No \(chartType.lowercased()) data yet.")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
            }

            if let latest = points.last {
                HStack {
                    Text("Latest \(chartType):").foregroundColor(PLColor.textSecondary)
                    Text("$\(latest.total, specifier: "%.2f")").font(.headline)
                    Spacer()
                    if budgetTarget > 0 {
                        let delta = latest.total - budgetTarget
                        Text(delta >= 0 ? "Over by $\(abs(delta), specifier: "%.2f")"
                                        : "Left: $\(abs(delta), specifier: "%.2f")")
                            .font(.subheadline)
                            .foregroundColor(delta >= 0 ? PLColor.danger : .green)
                    }
                }
            }
        }
        .task(id: chartType) { await reload() }
    }

    // MARK: - Data loading
    private func reload() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        async let t = fetchBudgetTarget()
        async let s = fetchTrendSeries()

        do {
            let (target, series) = try await (t, s)
            await MainActor.run {
                self.budgetTarget = target
                self.points = series.sorted { $0.date < $1.date }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.points = []
                self.budgetTarget = 0
                self.loadError = "Failed to load \(chartType.lowercased()) trend."
                self.isLoading = false
            }
        }
    }

    private func fetchBudgetTarget() async throws -> Double {
        let type = chartType.lowercased()
        guard let url = URL(string: "http://localhost:8080/api/budget/\(username)/\(type)") else { return 0 }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(BudgetResponse.self, from: data)
        return resp.budget.values.reduce(0, +)
    }

    private func fetchTrendSeries() async throws -> [TrendPoint] {
        chartType == "Weekly" ? try await last8Weeks() : try await last6Months()
    }

    private func last8Weeks() async throws -> [TrendPoint] {
        let cal = Calendar.current
        let currentStart = cal.startOfWeek(for: Date())
        var starts: [Date] = []
        for i in stride(from: 7, through: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -7 * i, to: currentStart) { starts.append(d) }
        }
        var result: [TrendPoint] = []
        for start in starts {
            if let p = try await fetchWeeklyPoint(for: start) { result.append(p) }
        }
        return result
    }

    private func last6Months() async throws -> [TrendPoint] {
        let cal = Calendar.current
        let now = Date()
        var months: [Date] = []
        for i in stride(from: 5, through: 0, by: -1) {
            if let d = cal.date(byAdding: .month, value: -i, to: now) { months.append(d) }
        }
        var result: [TrendPoint] = []
        for m in months {
            if let p = try await fetchMonthlyPoint(for: m) { result.append(p) }
        }
        return result
    }

    private func fetchWeeklyPoint(for start: Date) async throws -> TrendPoint? {
        let weekStart = start.ymd()
        guard let url = URL(string: "http://localhost:8080/api/costs/weekly/\(username)?week_start=\(weekStart)") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(PeriodFile.self, from: data)
        let total = (resp.totals?.values.reduce(0, +)) ?? 0
        return TrendPoint(date: start, total: total)
    }

    private func fetchMonthlyPoint(for date: Date) async throws -> TrendPoint? {
        let f = DateFormatter(); f.calendar = .init(identifier: .gregorian); f.dateFormat = "yyyy-MM"
        let monthStr = f.string(from: date)
        guard let url = URL(string: "http://localhost:8080/api/costs/monthly/\(username)?month=\(monthStr)") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(PeriodFile.self, from: data)
        let total = (resp.totals?.values.reduce(0, +)) ?? 0
        // place at end-of-month for spacing
        let comps = DateComponents(year: Calendar.current.component(.year, from: date),
                                   month: Calendar.current.component(.month, from: date) + 1,
                                   day: 0)
        let xDate = Calendar.current.date(from: comps) ?? date
        return TrendPoint(date: xDate, total: total)
    }
}

// MARK: - Helpers & models (local-only)
private struct TrendPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let total: Double
}

private struct PeriodFile: Decodable {
    let totals: [String: Double]?
}

private extension Calendar {
    // Sunday-based week to match backend
//    func startOfWeek(for date: Date) -> Date {
//        let weekday = component(.weekday, from: date) // 1..7 (Sun=1)
//        return self.date(byAdding: .day, value: -(weekday - 1), to: startOfDay(for: date)) ?? startOfDay(for: date)
//    }
}
private extension Date {
//    func ymd() -> String {
//        let f = DateFormatter()
//        f.calendar = .init(identifier: .gregorian)
//        f.dateFormat = "yyyy-MM-dd"
//        return f.string(from: self)
//    }
    func asShortWeek() -> String { let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: self) }
    func asShortMonth() -> String { let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: self) }
}
