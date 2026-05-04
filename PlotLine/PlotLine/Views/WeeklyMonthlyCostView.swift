//
//  WeeklyMonthlyCostView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/15/25.
//

import SwiftUI
import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Minimal Design Tokens (self-contained for now)
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let success        = Color.green
    static let danger         = Color.red
    static let warning        = Color.orange
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius {
    static let md: CGFloat = 12
}

// Reusable Card + Primary Button
private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(PLColor.cardBorder)
            )
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

// MARK: - View
// Common categories available across budget views
private let commonCategories = [
    // Defaults
    "Rent", "Groceries", "Subscriptions", "Eating Out",
    "Entertainment", "Utilities", "Savings", "Miscellaneous",
    "Transportation", "Roth IRA", "Car Insurance",
    "Health Insurance", "Brokerage",
    // Additional common
    "Gas", "Phone", "Internet", "Gym", "Clothing",
    "Personal Care", "Education", "Childcare", "Pet Care",
    "Home Maintenance", "Gifts", "Donations", "Travel",
    "Baby Supplies", "Hobbies", "Shopping", "Coffee",
    "Alcohol & Bars", "Home Decor", "Electronics",
    "Medical", "Dental", "Vision", "Therapy",
    "Parking", "Tolls", "Laundry", "Haircuts",
    "Streaming Services", "Gaming", "Music", "Books"
]

struct WeeklyMonthlyCostView: View {
    @State private var selectedTab = "Costs"
    @State private var costItems: [BudgetItem] = []
    @State private var budgetLimits: [String: Double] = [:]
    @State private var newCategory: String = ""
    @State private var showCategoryPicker = false

    // Fixed monthly costs
    @State private var fixedCosts: [FixedCostItem] = []
    @State private var showAddFixedCost = false
    @State private var editingFixedCost: FixedCostItem? = nil
    @State private var fixedCostCategory: String = ""
    @State private var fixedCostAmount: String = ""
    @State private var showFixedCostCategoryPicker = false
    @State private var fixedCostCustomCategory: String = ""

    // Recurring subscription detection after Plaid sync
    @State private var recurringPrompts: [RecurringChargePromptModel] = []
    @State private var showRecurringPrompt = false

    // Tracker logic
    @State private var takeHomeMonthly: Double = 0
    private let trackerExclusions: Set<String> = [
        "401(k)", "401k", "401(k) Contribution", "401k Contribution"
    ]

    // Current month being viewed
    @State private var selectedMonth: Date = Date()
    // Daily vs Monthly view toggle within Costs tab
    @State private var costsViewMode = "Monthly" // "Monthly" or "Daily"
    @State private var selectedDay: Date = Date()
    // Cached monthly period for day-level data
    @State private var monthlyPeriod: WeeklyPeriod? = nil
    // Monthly totals for budget summary (always reflects month totals regardless of view mode)
    @State private var monthlyTotals: [String: Double] = [:]

    // Totals (always monthly)
    private var budgetTotal: Double {
        takeHomeMonthly > 0 ? takeHomeMonthly : budgetLimits.values.reduce(0, +)
    }
    private var fixedCostTotal: Double {
        fixedCosts.reduce(0) { $0 + $1.amount }
    }
    private var enteredTotal: Double {
        // Always use month totals for budget summary, regardless of daily/monthly view mode
        // Fixed costs are already included in monthlyTotals (merged on backend)
        let fromTotals = monthlyTotals
            .filter { !trackerExclusions.contains($0.key) }
            .values
            .reduce(0, +)
        return fromTotals
    }
    private var remaining: Double { budgetTotal - enteredTotal }
    private var utilization: Double {
        guard budgetTotal > 0 else { return 0 }
        return min(max(enteredTotal / budgetTotal, 0), 1)
    }
    private var utilizationPercentText: String {
        guard budgetTotal > 0 else { return "—" }
        return String(format: "%.0f%%", utilization * 100)
    }

    private var monthDisplayText: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedMonth)
    }

    private var selectedDayDisplayText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: selectedDay)
    }

    private var daysInSelectedMonth: [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: selectedMonth),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: firstOfMonth) }
    }
    
    // Confirmation after Save
    @State private var activeAlert: AppAlert? = nil
    
    // Feedback
    @State private var monthlyFeedback: MonthlyFeedback?
    
    // Sync flow UI state
    @State private var showAccountPicker = false
    @State private var selectableAccounts: [PlaidAccount] = []
    @State private var selectedAccountIds: Set<String> = []
    @State private var uncategorized: [UncategorizedTxn] = []
    @State private var showCategorizer = false
    @State private var showSyncDone = false
    @State private var isSyncing = false
    @State private var lastSyncStats: (added: Int, modified: Int, uncategorized: Int) = (0, 0, 0)
    @State private var showResetConfirmation = false
    @State private var isResetting = false
    
    // Add Categories after sync
    @State private var pendingAssignments: [CategoryAssignment] = []
    @State private var skippedTransactionIds: Set<String> = []
    @State private var newCategoryName: String = ""
    @State private var showSyncCategoryPicker = false
    
    // Build the choices list from UI state
    private var existingCategories: [String] {
        let fromLimits = budgetLimits.keys
        let fromCosts  = costItems.map { $0.category }
        return Array(Set(fromLimits).union(fromCosts)).sorted()
    }

    private var availableSyncCategories: [String] {
        let current = Set(costItems.map { $0.category.lowercased() })
        return commonCategories.filter { !current.contains($0.lowercased()) }.sorted()
    }

    // Categories not yet added — shown in the "Add Category" dropdown
    private var availableCategories: [String] {
        let current = Set(costItems.map { $0.category.lowercased() })
        return commonCategories.filter { !current.contains($0.lowercased()) }.sorted()
    }
    
    @EnvironmentObject var calendarVM: CalendarViewModel
    
    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Costs / Feedback tab picker
            Picker("Tab", selection: $selectedTab) {
                Text("Costs").tag("Costs")
                Text("Feedback").tag("Feedback")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.sm)

            Divider()

            if selectedTab == "Costs" {
                costsTab
            } else {
                feedbackTab
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Monthly Costs")
                    .font(.headline)
            }
        }
        .tint(PLColor.accent)
        .alert(item: $activeAlert) { a in
            Alert(
                title: Text(a.title),
                message: Text(a.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            loadBudgetLimits()
            loadMonthlyData()
            fetchFixedCosts()
            fetchTakeHomeMonthly()
            fetchMonthlyFeedback(for: selectedMonth)
            requestNotificationPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadMonthlyData()
            fetchFixedCosts()
            fetchMonthlyFeedback(for: selectedMonth)
        }

        .sheet(isPresented: $showCategorizer, onDismiss: {
            pendingAssignments = []
            skippedTransactionIds = []
        }) {
            NavigationView {
                VStack(spacing: 12) {
                    if pendingAssignments.isEmpty && skippedTransactionIds.isEmpty {
                        Text("Loading…").padding()
                    } else if pendingAssignments.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("All transactions handled!")
                                .font(.headline)
                            Text("\(skippedTransactionIds.count) skipped")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                ForEach($pendingAssignments) { $a in
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Transaction name - prominent, adapts to dark mode
                                        Text(a.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .lineLimit(2)

                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(a.date)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text("$\(a.amount, specifier: "%.2f")")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                            }
                                            Spacer()
                                            Button {
                                                skipTransaction(a)
                                            } label: {
                                                Text("Skip")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(.red)
                                        }
                                        Picker("Category", selection: $a.category) {
                                            ForEach(existingCategories, id: \.self) { c in
                                                Text(c).tag(c)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .tint(Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .systemBlue }))
                                    }
                                    .padding(.vertical, 4)
                                }
                            } header: {
                                Text("Uncategorized transactions (\(pendingAssignments.count))")
                                    .foregroundColor(Color(UIColor { traitCollection in
                                        traitCollection.userInterfaceStyle == .dark ? .white : .systemBlue
                                    }))
                            }

                            if !skippedTransactionIds.isEmpty {
                                Section {
                                    Text("\(skippedTransactionIds.count) transaction(s) will be skipped")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Section {
                                Menu {
                                    ForEach(availableSyncCategories, id: \.self) { cat in
                                        Button(cat) {
                                            self.costItems.append(BudgetItem(category: cat, amount: ""))
                                            if let idx = pendingAssignments.indices.last {
                                                pendingAssignments[idx].category = cat
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("Custom...") { showSyncCategoryPicker = true }
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Add Category")
                                            .font(.subheadline)
                                            .foregroundColor(Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .systemBlue }))
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .alert("Custom Category", isPresented: $showSyncCategoryPicker) {
                                    TextField("Category name", text: $newCategoryName)
                                    Button("Add") {
                                        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !name.isEmpty else { return }
                                        self.costItems.append(BudgetItem(category: name, amount: ""))
                                        if let idx = pendingAssignments.indices.last {
                                            pendingAssignments[idx].category = name
                                        }
                                        newCategoryName = ""
                                    }
                                    Button("Cancel", role: .cancel) { newCategoryName = "" }
                                }
                            } header: {
                                Text("Create new category")
                                    .foregroundColor(Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .systemBlue }))
                            }
                        }
                    }
                }
                .navigationTitle("Categorize")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showCategorizer = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { Task { await submitAssignments() } }
                            .disabled(pendingAssignments.isEmpty && skippedTransactionIds.isEmpty)
                    }
                }
                .onAppear(perform: openCategorizer)
            }
        }
        
        // Final confirmation popup
        .alert("Sync Complete", isPresented: $showSyncDone) {
            Button("OK", role: .cancel) {}
        } message: {
            if lastSyncStats.added == 0 && lastSyncStats.modified == 0 {
                Text("No new transactions found. Your bank data is already up to date.")
            } else {
                Text("\(lastSyncStats.added) new transaction(s) synced and categorized.")
            }
        }
        .sheet(isPresented: $showRecurringPrompt) {
            RecurringPromptSheet(
                prompts: $recurringPrompts,
                onAccept: { prompt in
                    Task { await acceptRecurringPrompt(prompt) }
                },
                onDecline: { prompt in
                    Task { await snoozeRecurringPrompt(prompt) }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .plaidSynced)) { _ in
            loadMonthlyData()
            fetchMonthlyFeedback(for: selectedMonth)
        }
    }

    // MARK: - Costs Tab
    private var costsTab: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                // Month navigation
                HStack {
                    Button {
                        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                        loadMonthlyData()
                        fetchMonthlyFeedback(for: selectedMonth)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PLColor.textPrimary)
                    }
                    Spacer()
                    Text(monthDisplayText)
                        .font(.headline)
                        .foregroundColor(PLColor.textPrimary)
                    Spacer()
                    Button {
                        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                        loadMonthlyData()
                        fetchMonthlyFeedback(for: selectedMonth)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PLColor.textPrimary)
                    }
                }
                .plCard()

                // Monthly / Daily toggle
                Picker("View", selection: $costsViewMode) {
                    Text("Monthly").tag("Monthly")
                    Text("Daily").tag("Daily")
                }
                .pickerStyle(.segmented)
                .onChange(of: costsViewMode) { _ in
                    if costsViewMode == "Monthly" {
                        loadMonthlyTotalsIntoCostItems()
                    } else {
                        loadDayCostsIntoCostItems()
                    }
                }

                // Day picker (only in Daily mode)
                if costsViewMode == "Daily" {
                    dayPicker
                        .plCard()
                }

                // Budget Summary (always shows monthly totals)
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    HStack {
                        Text("Budget Summary")
                            .font(.headline)
                        Spacer()
                        Text(utilizationPercentText)
                            .font(.subheadline)
                            .foregroundColor(utilization >= 1.0 ? PLColor.danger : PLColor.textSecondary)
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Monthly Budget")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                            Text("$\(budgetTotal, specifier: "%.2f")")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Spent")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                            Text("$\(enteredTotal, specifier: "%.2f")")
                                .font(.headline)
                        }
                    }
                    ProgressView(value: utilization)
                    let over = remaining < 0
                    Text(over
                         ? "Over by $\(abs(remaining), specifier: "%.2f")"
                         : "Left: $\(remaining, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundColor(over ? PLColor.danger : PLColor.success)
                }
                .plCard()

                // Cost input rows
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text(costsViewMode == "Daily" ? "Costs for \(selectedDayDisplayText)" : "Monthly Costs")
                        .font(.headline)
                        .foregroundColor(PLColor.textPrimary)

                    LazyVStack(spacing: PLSpacing.sm) {
                        ForEach($costItems) { $item in
                            if !trackerExclusions.contains(item.category) {
                                CostRow(
                                    item: $item,
                                    budgetLimit: budgetLimits[item.category],
                                    onRemove: { removeCategory(item: item) },
                                    onChangeAmount: { newVal in
                                        item.amount = sanitizeAmount(newVal)
                                    }
                                )
                            }
                        }
                    }

                    // Add category
                    VStack(spacing: PLSpacing.xs) {
                        Menu {
                            ForEach(availableCategories, id: \.self) { cat in
                                Button(cat) {
                                    costItems.append(BudgetItem(category: cat, amount: ""))
                                }
                            }
                            Divider()
                            Button("Custom...") {
                                showCategoryPicker = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                Text("Add Category")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(PLColor.textSecondary)
                            }
                            .padding(.vertical, 8)
                        }
                        .alert("Custom Category", isPresented: $showCategoryPicker) {
                            TextField("Category name", text: $newCategory)
                            Button("Add") { addCategory() }
                            Button("Cancel", role: .cancel) { newCategory = "" }
                        }
                    }
                }
                .plCard()

                // Fixed Monthly Costs
                if costsViewMode == "Monthly" {
                    fixedCostsSection
                }

                // Save
                Button("Save Costs", action: saveCosts)
                    .buttonStyle(PrimaryButton())
                    .padding(.top, -PLSpacing.sm)

                // Sync
                HStack(spacing: 12) {
                    Button {
                        Task { await fetchAccountsForSelection() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSyncing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Syncing...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Transactions")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncing || isResetting)

                    Button {
                        showResetConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            if isResetting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(isSyncing || isResetting)
                }
                .sheet(isPresented: $showAccountPicker) {
                    AccountPickerSheet(
                        accounts: $selectableAccounts,
                        selectedAccountIds: $selectedAccountIds,
                        isPresented: $showAccountPicker
                    ) {
                        Task { await syncSelectedAccounts() }
                    }
                }
                .alert("Reset Sync?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        Task { await resetSyncState() }
                    }
                } message: {
                    Text("This will clear all sync history. Your next sync will fetch all transactions from the last 30 days.")
                }

                // View Transactions
                NavigationLink {
                    TransactionsView(username: username, month: selectedMonth)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("View Transactions")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { hideKeyboard() }
        }
    }

    // MARK: - Feedback Tab
    private var feedbackTab: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                if let fb = monthlyFeedback {
                    MonthlyFeedbackCard(fb: fb, budgetHint: budgetTotal)
                        .plCard()
                } else {
                    VStack(spacing: PLSpacing.md) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 40))
                            .foregroundColor(PLColor.textSecondary)
                        Text("No Feedback Yet")
                            .font(.headline)
                        Text("Complete at least one prior month of tracking to see how you're doing. Up to 6 months are averaged for a more accurate baseline.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .plCard()
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
        }
    }
    
    // MARK: - Day Picker
    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: PLSpacing.xs) {
            Text(selectedDayDisplayText)
                .font(.subheadline.bold())
                .foregroundColor(PLColor.textPrimary)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                // Day-of-week headers
                let weekdayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PLColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                // Leading empty cells for alignment
                let cal = Calendar.current
                let firstDay = daysInSelectedMonth.first ?? selectedMonth
                let weekdayOffset = cal.component(.weekday, from: firstDay) - 1 // Sun=0
                ForEach(0..<weekdayOffset, id: \.self) { _ in
                    Text("")
                        .frame(height: 32)
                }

                // Day cells
                ForEach(daysInSelectedMonth, id: \.self) { day in
                    let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
                    let dayNum = cal.component(.day, from: day)
                    let dayKey = day.ymd()
                    let hasData = monthlyPeriod?.days[dayKey] != nil

                    Text("\(dayNum)")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white : PLColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            isSelected ? PLColor.accent :
                            hasData ? PLColor.accent.opacity(0.12) : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture {
                            selectedDay = day
                            loadDayCostsIntoCostItems()
                        }
                }
            }
        }
    }

    // MARK: - Fixed Monthly Costs Section
    private var fixedCostsSection: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Text("Fixed Monthly Costs")
                    .font(.headline)
                    .foregroundColor(PLColor.textPrimary)
                Spacer()
                if !fixedCosts.isEmpty {
                    Text("$\(fixedCostTotal, specifier: "%.2f")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(PLColor.textSecondary)
                }
            }

            Text("These amounts are automatically included every month.")
                .font(.caption)
                .foregroundColor(PLColor.textSecondary)

            if fixedCosts.isEmpty {
                HStack {
                    Image(systemName: "pin.slash")
                        .foregroundColor(PLColor.textSecondary)
                    Text("No fixed costs set")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(fixedCosts) { fc in
                    HStack {
                        Text(fc.category)
                            .font(.body)
                        Spacer()
                        Text("$\(fc.amount, specifier: "%.2f")")
                            .font(.body.monospacedDigit())
                            .fontWeight(.medium)
                        Button {
                            editingFixedCost = fc
                            fixedCostCategory = fc.category
                            fixedCostAmount = String(format: "%.2f", fc.amount)
                            showAddFixedCost = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .foregroundColor(PLColor.accent)
                        }
                        .buttonStyle(.plain)
                        Button {
                            deleteFixedCost(fc)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(PLColor.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                editingFixedCost = nil
                fixedCostCategory = ""
                fixedCostAmount = ""
                showAddFixedCost = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                    Text("Add Fixed Cost")
                        .font(.subheadline)
                }
            }
        }
        .plCard()
        .sheet(isPresented: $showAddFixedCost) {
            fixedCostSheet
        }
    }

    private var fixedCostSheet: some View {
        NavigationView {
            Form {
                Section("Category") {
                    Picker("Category", selection: $fixedCostCategory) {
                        Text("Select...").tag("")
                        ForEach(commonCategories.sorted(), id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        TextField("Or type custom...", text: $fixedCostCustomCategory)
                            .textInputAutocapitalization(.words)
                        if !fixedCostCustomCategory.isEmpty {
                            Button("Use") {
                                fixedCostCategory = fixedCostCustomCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                                fixedCostCustomCategory = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Amount") {
                    HStack {
                        Text("$")
                            .font(.title3)
                        TextField("0.00", text: $fixedCostAmount)
                            .keyboardType(.decimalPad)
                            .font(.title3)
                    }
                }
            }
            .navigationTitle(editingFixedCost != nil ? "Edit Fixed Cost" : "Add Fixed Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddFixedCost = false
                        fixedCostCustomCategory = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveFixedCost()
                    }
                    .disabled(fixedCostCategory.isEmpty || Double(fixedCostAmount) == nil)
                }
            }
        }
    }

    // MARK: - Fixed Cost Functions

    private func fetchFixedCosts() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/fixed/\(username)") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode([FixedCostItem].self, from: data) else { return }
            DispatchQueue.main.async {
                self.fixedCosts = decoded
            }
        }.resume()
    }

    private func saveFixedCost() {
        guard let amount = Double(fixedCostAmount), !fixedCostCategory.isEmpty else { return }
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/fixed/\(username)"
        guard let url = URL(string: urlStr) else { return }

        var payload: [String: Any] = [
            "category": fixedCostCategory,
            "amount": amount
        ]
        if let existing = editingFixedCost {
            payload["id"] = existing.id
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(code),
                  let data = data,
                  let updated = try? JSONDecoder().decode([FixedCostItem].self, from: data) else { return }
            DispatchQueue.main.async {
                self.fixedCosts = updated
                self.showAddFixedCost = false
                self.fixedCostCustomCategory = ""
            }
        }.resume()
    }

    private func deleteFixedCost(_ fc: FixedCostItem) {
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/fixed/\(username)/\(fc.id)"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(code),
                  let data = data,
                  let updated = try? JSONDecoder().decode([FixedCostItem].self, from: data) else { return }
            DispatchQueue.main.async {
                self.fixedCosts = updated
            }
        }.resume()
    }

    // MARK: - Cost Functions
    private func addCategory() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !costItems.contains(where: { $0.category.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            costItems.append(BudgetItem(category: trimmed, amount: ""))
        }
        newCategory = ""
    }
    private func removeCategory(item: BudgetItem) {
        costItems.removeAll { $0.id == item.id }
    }

    // Keep only digits and a single decimal point
    private func sanitizeAmount(_ input: String) -> String {
        var filtered = input.filter { "0123456789.".contains($0) }
        if let firstDot = filtered.firstIndex(of: ".") {
            let after = filtered.index(after: firstDot)
            let remainder = filtered[after...].replacingOccurrences(of: ".", with: "")
            filtered = String(filtered[..<after]) + remainder
        }
        return filtered
    }
    
    private func postMerge(type: String, date: Date, values: [String: Double], replaceAll: Bool = false, completion: @escaping (Bool)->Void) {
        var payload: [String: Any] = [
            "username": username,
            "type": type,
            "date": date.ymd(),
            "costs": values
        ]
        if replaceAll {
            payload["replaceAll"] = true
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { completion(false); return }

        var req = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/costs/merge-dated")!)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            completion(error == nil && (200...299).contains(code))
        }.resume()
    }
    
    private func postSetMonthlyTotals(values: [String: Double], completion: @escaping (Bool)->Void) {
        let monthStr = monthYYYYMM(from: selectedMonth)
        let urlString = "\(BackendConfig.baseURLString)/api/costs/monthly/\(username)/set-totals?month=\(monthStr)"
        guard let url = URL(string: urlString) else { completion(false); return }

        let payload: [String: Any] = ["costs": values]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { completion(false); return }

        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            completion(error == nil && (200...299).contains(code))
        }.resume()
    }

    private func saveCosts() {
        // Validate: reject non-numeric values but allow empty (treated as 0)
        let invalid = costItems.first { item in
            guard !trackerExclusions.contains(item.category) else { return false }
            let trimmed = item.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false } // empty = 0, that's fine
            return Double(trimmed) == nil
        }
        if invalid != nil {
            activeAlert = AppAlert(title: "Invalid Amount", message: "Please enter a valid number (or leave blank for $0).")
            return
        }

        let isDaily = costsViewMode == "Daily"
        let successMsg = isDaily
            ? "Costs for \(selectedDayDisplayText) saved."
            : "Your monthly costs have been saved."

        if isDaily {
            // Daily: build payload excluding tracker exclusions and zeroes
            let values = costItems.reduce(into: [String: Double]()) { acc, item in
                guard !trackerExclusions.contains(item.category),
                      let v = Double(item.amount), v != 0 else { return }
                acc[item.category] = v
            }
            // SET this day's costs directly
            postMerge(type: "monthly", date: selectedDay, values: values) { ok in
                DispatchQueue.main.async {
                    if !ok { self.activeAlert = AppAlert(title: "Save Error", message: "We couldn't save. Please try again."); return }
                    self.loadMonthlyData()
                    self.fetchMonthlyFeedback(for: self.selectedMonth)
                    self.activeAlert = AppAlert(title: "Success", message: successMsg)
                }
            }
        } else {
            // Monthly: send desired totals to backend.
            // Backend stores adjustments separately from day entries,
            // so monthly-only costs (like rent) won't appear in weekly charts.
            let values = costItems.reduce(into: [String: Double]()) { acc, item in
                guard !trackerExclusions.contains(item.category) else { return }
                let v = Double(item.amount) ?? 0
                acc[item.category] = v
            }
            postSetMonthlyTotals(values: values) { ok in
                DispatchQueue.main.async {
                    if !ok { self.activeAlert = AppAlert(title: "Save Error", message: "We couldn't save. Please try again."); return }
                    self.loadMonthlyData()
                    self.fetchMonthlyFeedback(for: self.selectedMonth)
                    self.activeAlert = AppAlert(title: "Success", message: successMsg)
                }
            }
        }
    }

    
    // MARK: - Budget Limits + Costs
    private func loadBudgetLimits() {
        let urlString = "\(BackendConfig.baseURLString)/api/budget/\(username)/monthly"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("Error fetching budget:", error.localizedDescription)
                return
            }
            guard let data = data, !data.isEmpty else { return }
            do {
                let decoded = try JSONDecoder().decode(BudgetResponse.self, from: data)
                DispatchQueue.main.async {
                    self.budgetLimits = decoded.budget.filter { !self.trackerExclusions.contains($0.key) }
                    self.loadMonthlyData()
                }
            } catch {
                print("Failed to decode budget data:", error)
            }
        }.resume()
    }
    
    private func loadMonthlyData() {
        let monthStr = monthYYYYMM(from: selectedMonth)
        let urlString = "\(BackendConfig.baseURLString)/api/costs/monthly/\(username)?month=\(monthStr)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { print("Monthly fetch error:", error); return }
            guard let data = data else { return }
            if let period = try? JSONDecoder().decode(WeeklyPeriod.self, from: data) {
                DispatchQueue.main.async {
                    self.monthlyPeriod = period
                    self.monthlyTotals = period.totals

                    if self.costsViewMode == "Daily" {
                        self.loadDayCostsIntoCostItems()
                    } else {
                        self.loadMonthlyTotalsIntoCostItems()
                    }
                }
            }
        }.resume()
    }

    private func loadMonthlyTotalsIntoCostItems() {
        let totals = monthlyTotals
        // Exclude fixed cost categories (they're shown in the fixed costs section)
        let fixedCatNames = Set(fixedCosts.map { $0.category.lowercased() })

        // Only fall back to budget categories if there are no saved totals for this month
        var keys = Set(totals.keys)
        if keys.isEmpty {
            keys = keys.union(budgetLimits.keys)
        }
        let sorted = keys
            .subtracting(trackerExclusions)
            .filter { !fixedCatNames.contains($0.lowercased()) }
            .sorted()
        costItems = sorted.map { cat in
            let v = totals[cat] ?? 0.0
            return BudgetItem(category: cat, amount: v == 0.0 ? "" : String(v))
        }
    }

    private func loadDayCostsIntoCostItems() {
        let dayKey = selectedDay.ymd()
        let dayCosts = monthlyPeriod?.days[dayKey] ?? [:]
        // Exclude fixed cost categories
        let fixedCatNames = Set(fixedCosts.map { $0.category.lowercased() })

        var keys = Set(dayCosts.keys)
        if keys.isEmpty {
            keys = keys.union(budgetLimits.keys)
        }
        let sorted = keys
            .subtracting(trackerExclusions)
            .filter { !fixedCatNames.contains($0.lowercased()) }
            .sorted()
        costItems = sorted.map { cat in
            let v = dayCosts[cat] ?? 0.0
            return BudgetItem(category: cat, amount: v == 0.0 ? "" : String(v))
        }
    }
    
    private func monthYYYYMM(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
    
    
    
    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted { print("Notification permission granted.") }
            else { print("Notification permission denied: \(error?.localizedDescription ?? "Unknown error")") }
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("Notification Settings: \(settings.authorizationStatus.rawValue)")
        }
    }
    private func sendNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Recurring subscription prompts (Plaid)
    private func fetchRecurringSubscriptionPrompts() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/recurring/analyze/\(username)?months=6&remindAfterMonths=2") else { return }
        do {
            var request = URLRequest(url: url)
            BackendConfig.addApiKey(to: &request)
            let (data, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            let decoded = try JSONDecoder().decode(RecurringPromptResponse.self, from: data)
            if !decoded.prompts.isEmpty {
                await MainActor.run {
                    self.recurringPrompts = decoded.prompts
                    self.showRecurringPrompt = true
                }
                sendNotification(
                    title: "Subscription detected",
                    message: "We found recurring charges. Open the app to confirm."
                )
            }
        } catch {
            print("recurring prompt fetch error:", error)
        }
    }

    private func acceptRecurringPrompt(_ prompt: RecurringChargePromptModel) async {
        let dueDate = nextOccurrence(dayOfMonth: prompt.dayOfMonth)
        let newSub = SubscriptionItem(name: prompt.name, cost: "", dueDate: dueDate)
        await upsertSubscriptions([newSub])
        await MainActor.run {
            recurringPrompts.removeAll { $0.id == prompt.id }
            showRecurringPrompt = !recurringPrompts.isEmpty
        }
    }

    private func snoozeRecurringPrompt(_ prompt: RecurringChargePromptModel) async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/recurring/snooze") else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "username": username,
            "snoozeKey": prompt.snoozeKey,
            "months": 2
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        req.httpBody = data
        do {
            _ = try await URLSession.shared.data(for: req)
        } catch {
            print("snooze error:", error)
        }
        await MainActor.run {
            recurringPrompts.removeAll { $0.id == prompt.id }
            showRecurringPrompt = !recurringPrompts.isEmpty
        }
    }

    private func upsertSubscriptions(_ newSubs: [SubscriptionItem]) async {
        // Fetch existing subs from backend
        var merged: [String: SubscriptionItem] = [:]
        if let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/\(username)") {
            do {
                var request = URLRequest(url: url)
                BackendConfig.addApiKey(to: &request)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let decoded = try? JSONDecoder().decode(SubscriptionMapResponse.self, from: data) {
                    for (name, subData) in decoded.subscriptions {
                        merged[name.lowercased()] = SubscriptionItem(name: name, cost: "", dueDate: subData.dueDate)
                    }
                }
            } catch { }
        }
        for sub in newSubs {
            merged[sub.name.lowercased()] = sub
        }

        var dict: [String: SubscriptionData] = [:]
        for sub in merged.values {
            dict[sub.name] = SubscriptionData(name: sub.name, cost: "", dueDate: sub.dueDate)
            await MainActor.run {
                ensureSubscriptionEvent(sub)
                scheduleMonthlySubscriptionReminder(for: sub)
            }
        }

        let payload = SubscriptionUpload(username: username, subscriptions: dict)
        guard let body = try? JSONEncoder().encode(payload),
              let postURL = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions") else { return }
        var req = URLRequest(url: postURL)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            _ = try await URLSession.shared.data(for: req)
        } catch {
            print("save subs error:", error)
        }
    }

    private func ensureSubscriptionEvent(_ sub: SubscriptionItem) {
        let existing = calendarVM.events.first {
            $0.eventType.lowercased().hasPrefix("subscription") &&
            $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
        }
        if existing == nil {
            calendarVM.createEvent(
                title: sub.name,
                description: "Subscription reminder",
                startDate: sub.dueDate,
                endDate: sub.dueDate,
                eventType: "subscription",
                recurrence: "monthly",
                invitedFriends: []
            )
        }
    }

    private func scheduleMonthlySubscriptionReminder(for sub: SubscriptionItem) {
        let center = UNUserNotificationCenter.current()
        let id = "subscription-reminder-\(sub.name.lowercased())"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        var comps = Calendar.current.dateComponents([.day], from: sub.dueDate)
        let day = comps.day ?? 1
        if day == 1 {
            comps.day = 1
            comps.hour = 9
            comps.minute = 0
        } else {
            comps.day = day - 1
            comps.hour = 9
            comps.minute = 0
        }

        let content = UNMutableNotificationContent()
        content.title = "Subscription Reminder"
        content.body = day == 1 ? "\(sub.name) is due today." : "\(sub.name) is due tomorrow."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    private func nextOccurrence(dayOfMonth: Int) -> Date {
        let calendar = Calendar.current
        let today = Date()
        var comps = calendar.dateComponents([.year, .month], from: today)
        let range = calendar.range(of: .day, in: .month, for: today) ?? 1..<28
        let day = min(max(dayOfMonth, 1), range.count)
        comps.day = day
        let thisMonth = calendar.date(from: comps) ?? today
        if thisMonth >= today { return thisMonth }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
        return nextMonth
    }
    
    // MARK: - Income
    private func fetchTakeHomeMonthly() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/budget/last/\(username)") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let v = obj["monthlyNet"] as? Double {
                DispatchQueue.main.async { self.takeHomeMonthly = v }
            } else if let s = obj["monthlyNet"] as? String, let v = Double(s) {
                DispatchQueue.main.async { self.takeHomeMonthly = v }
            }
        }.resume()
    }
    
    // MARK: - Feedback
    private func fetchMonthlyFeedback(for date: Date) {
        let month = monthYYYYMM(from: date)
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/feedback/\(username)?month=\(month)")
        else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode),
                let data = data,
                !data.isEmpty,
                let decoded = try? JSONDecoder().decode(MonthlyFeedback.self, from: data),
                decoded.month == month
            else { DispatchQueue.main.async { self.monthlyFeedback = nil }; return }

            if decoded.totalPrevious == 0 {
                DispatchQueue.main.async { self.monthlyFeedback = nil }
                return
            }

            if decoded.totalCurrent == 0 && decoded.totalPrevious == 0 {
                DispatchQueue.main.async { self.monthlyFeedback = nil }
                return
            }

            DispatchQueue.main.async { self.monthlyFeedback = decoded }
        }.resume()
    }
    
    // Fetch accounts (grouped across items) the user can pick from
    private func fetchAccountsForSelection() async {
        await MainActor.run {
            // Show the sheet right away with a loading state
            self.selectableAccounts = []
            self.selectedAccountIds = []
            self.showAccountPicker = true
        }

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/accounts?username=\(username)") else { return }
        do {
            var request = URLRequest(url: url)
            BackendConfig.addApiKey(to: &request)
            let (data, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(decoding: data, as: UTF8.self)
                print("accounts HTTP \(http.statusCode): \(body)")
                throw URLError(.badServerResponse)
            }
            let list = try JSONDecoder().decode([PlaidAccount].self, from: data)
            print("decoded accounts:", list.map { "\($0.name) [\($0.id)]" })
            await MainActor.run {
                self.selectableAccounts = list           // sheet updates in place
            }
        } catch {
            print("accounts fetch error:", error)
            await MainActor.run {
                self.activeAlert = AppAlert(
                    title: "Couldn’t load accounts",
                    message: "Please relink your bank or try again."
                )
                // keep the sheet up; user can Cancel
            }
        }
    }
    
    // user_transactions_dynamic
    
    // Reset sync state (clear cursors and seen transactions)
    private func resetSyncState() async {
        await MainActor.run { isResetting = true }
        defer { Task { @MainActor in isResetting = false } }

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/reset-sync") else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["username": username]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                await MainActor.run {
                    self.activeAlert = AppAlert(
                        title: "Sync Reset",
                        message: "Your next sync will fetch all transactions from the last 30 days."
                    )
                }
            } else {
                let body = String(decoding: respData, as: UTF8.self)
                print("reset-sync error: \(body)")
                await MainActor.run {
                    self.activeAlert = AppAlert(
                        title: "Reset Failed",
                        message: "Could not reset sync state. Please try again."
                    )
                }
            }
        } catch {
            print("reset-sync error: \(error)")
            await MainActor.run {
                self.activeAlert = AppAlert(
                    title: "Reset Failed",
                    message: "Network error: \(error.localizedDescription)"
                )
            }
        }
    }

    // Call sync with selected accounts
    private func syncSelectedAccounts() async {
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/sync") else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = SyncRequest(username: username, account_ids: Array(selectedAccountIds))
        guard let data = try? JSONEncoder().encode(body) else { return }
        req.httpBody = data

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                print("sync HTTP status: \(http.statusCode)")
            }
            let respString = String(decoding: respData, as: UTF8.self)
            print("sync response body: \(respString)")

            let syncResp = try JSONDecoder().decode(SyncResponse.self, from: respData)

            // Check for error response from backend
            if let error = syncResp.error {
                print("sync backend error: \(error)")
                await MainActor.run {
                    self.activeAlert = AppAlert(
                        title: "Sync Error",
                        message: error
                    )
                }
                return
            }

            await MainActor.run {
                self.uncategorized = syncResp.uncategorized ?? []
                self.lastSyncStats = (
                    added: syncResp.added ?? 0,
                    modified: syncResp.modified ?? 0,
                    uncategorized: self.uncategorized.count
                )
                if uncategorized.isEmpty {
                    self.showSyncDone = true
                    self.loadMonthlyData()
                    self.fetchMonthlyFeedback(for: self.selectedMonth)
                    Task { await fetchRecurringSubscriptionPrompts() }
                } else {
                    self.showCategorizer = true
                }
            }
        } catch {
            print("sync error:", error)
            await MainActor.run {
                self.activeAlert = AppAlert(
                    title: "Sync Error",
                    message: "Failed to parse sync response: \(error.localizedDescription)"
                )
            }
        }
    }
    
    private func openCategorizer() {
        pendingAssignments = uncategorized.map {
            CategoryAssignment(txnId: $0.id, date: $0.date, name: $0.name, category: existingCategories.first ?? "Miscellaneous", amount: $0.amount)
        }
        skippedTransactionIds = []
    }

    private func skipTransaction(_ assignment: CategoryAssignment) {
        skippedTransactionIds.insert(assignment.txnId)
        pendingAssignments.removeAll { $0.txnId == assignment.txnId }
    }

    private func submitSkippedTransactions() async {
        guard !skippedTransactionIds.isEmpty else { return }

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/skip-transactions") else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "username": username,
            "transaction_ids": Array(skippedTransactionIds)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        req.httpBody = data

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                print("Successfully skipped \(skippedTransactionIds.count) transactions")
            }
        } catch {
            print("Error skipping transactions: \(error)")
        }
    }
    
    // Send assignments to backend
    private func submitAssignments() async {
        // First, submit any skipped transactions
        await submitSkippedTransactions()

        // If all transactions were skipped, just close and refresh
        if pendingAssignments.isEmpty {
            await MainActor.run {
                self.showCategorizer = false
                self.showSyncDone = true
                self.loadMonthlyData()
                self.fetchMonthlyFeedback(for: self.selectedMonth)
                NotificationCenter.default.post(name: .plaidSynced, object: nil)
            }
            return
        }

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/assign") else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AssignPayload(username: username, assignments: pendingAssignments)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        req.httpBody = data

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(decoding: respData, as: UTF8.self)
                print("assign HTTP \(http.statusCode): \(body)")
                await MainActor.run {
                    self.activeAlert = AppAlert(title: "Save Error", message: "Server error \(http.statusCode). Try again.")
                }
                return
            }

            await MainActor.run {
                self.showCategorizer = false
                self.showSyncDone = true
                self.loadMonthlyData()
                self.fetchMonthlyFeedback(for: self.selectedMonth)
                NotificationCenter.default.post(name: .plaidSynced, object: nil)
            }
            await fetchRecurringSubscriptionPrompts()
        } catch {
            print("assign error:", error)
            await MainActor.run {
                self.activeAlert = AppAlert(title: "Save Error", message: "We couldn't save your categories. Please try again.")
            }
        }
    }
}

// MARK: - Cost Row
private struct CostRow: View {
    @Binding var item: BudgetItem
    let budgetLimit: Double?
    var onRemove: () -> Void
    var onChangeAmount: (String) -> Void

    private var budgetStatus: BudgetStatus? {
        guard let limit = budgetLimit, let cost = Double(item.amount), cost > 0 else { return nil }
        if cost > limit { return .over }
        if cost >= limit * 0.8 { return .nearing }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: PLSpacing.sm) {
                Text(item.category)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("$0", text: $item.amount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onChange(of: item.amount) { newValue in
                        onChangeAmount(newValue)
                    }

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(PLColor.danger)
                }
            }

            if let status = budgetStatus {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(status == .over ? "Over budget" : "Nearing budget")
                        .font(.caption)
                }
                .foregroundColor(status == .over ? PLColor.danger : PLColor.warning)
            }
        }
    }

    private enum BudgetStatus { case over, nearing }
}

// MARK: - Calendar helpers
extension Calendar {
    // Sunday-based weeks to match your backend
    func startOfWeek(for date: Date) -> Date {
        let weekday = component(.weekday, from: date) // 1..7 Sun=1
        return self.date(byAdding: .day, value: -(weekday - 1), to: startOfDay(for: date)) ?? startOfDay(for: date)
    }
}
extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func addingDays(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: self) ?? self }
    func ymd() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
    func shortWeekday() -> String { let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: self) }
    func monthDay() -> String { let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: self) }
}

// Subscription Models

struct SubscriptionItem: Identifiable, Codable {
    var id = UUID()
    let name: String
    var cost: String
    @CodableDate
    var dueDate: Date

}
// Fixed monthly cost item
struct FixedCostItem: Codable, Identifiable {
    let id: String
    let category: String
    let amount: Double
}

// For the days of the week at the top
struct WeeklyPeriod: Codable {
    let periodKey: String
    let start: String
    let end: String
    let days: [String: [String: Double]] // "YYYY-MM-DD" -> category->amount
    let totals: [String: Double]
    let adjustments: [String: Double]? // monthly-only costs (not in days/weekly charts)
}

// Decode date to be able to upload it to the backend
@propertyWrapper
struct CodableDate: Codable {
    var wrappedValue: Date

    init(wrappedValue: Date) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let date = f1.date(from: dateString) ?? f2.date(from: dateString) {
            self.wrappedValue = date
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Use DateFormatter with exact UTC 'Z' format the backend expects
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = formatter.string(from: wrappedValue)
        try container.encode(dateString)
    }
}

struct SubscriptionUpload: Codable {
    let username: String
    let subscriptions: [String: SubscriptionData]
}

struct SubscriptionMapResponse: Codable {
    let username: String
    let subscriptions: [String: SubscriptionData]
}

struct SubscriptionData: Codable {
    let name: String
    let cost: String?
    @CodableDate var dueDate: Date
}

struct RecurringChargePromptModel: Identifiable, Codable {
    let snoozeKey: String
    let name: String
    let averageAmount: Double
    let dayOfMonth: Int
    let consecutiveMonths: Int
    let lastSeen: String
    let nextReminderAfter: String
    var id: String { snoozeKey }
}

struct RecurringPromptResponse: Codable {
    let prompts: [RecurringChargePromptModel]
    let remindAfterMonths: Int?
}


struct SubscriptionRequest: Codable {
    let username: String
    let subscriptions: [SubscriptionItem]
}

private struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RecurringPromptSheet: View {
    @Binding var prompts: [RecurringChargePromptModel]
    var onAccept: (RecurringChargePromptModel) -> Void
    var onDecline: (RecurringChargePromptModel) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(prompts) { prompt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prompt.name)
                            .font(.headline)
                        Text("Seen \(prompt.consecutiveMonths)x, avg $\(prompt.averageAmount, specifier: "%.2f")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Button("Add Subscription") {
                                onAccept(prompt)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Not a subscription") {
                                onDecline(prompt)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Recurring Charges")
        }
    }
}

// Models for Feedback
private struct CategoryDelta: Codable, Identifiable {
    var id: String { category }
    let category: String
    let current: Double
    let previous: Double
    let delta: Double        // current - average
    let pct: Double?         // nil means no prior-month baseline for this category
}

private struct MonthlyFeedback: Codable {
    let month: String
    let previousMonth: String
    let totalCurrent: Double
    let totalPrevious: Double
    let totalDelta: Double
    let deltas: [CategoryDelta]
    let overBudget: Bool?
    let monthlyBudget: Double?
    let cutbacks: [CategoryDelta]?
    let monthsCompared: Int?
}

private struct FeedbackRow: View {
    let label: String
    let deltaText: String
    let color: Color
    var body: some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(deltaText)
                .foregroundColor(color)
                .font(.subheadline)
        }
    }
}

private struct MonthlyFeedbackCard: View {
    let fb: MonthlyFeedback
    let budgetHint: Double?

    private var verdictText: String { fb.totalDelta <= 0 ? "You spent less 🎉" : "You spent more" }
    private var verdictColor: Color { fb.totalDelta <= 0 ? PLColor.success : PLColor.danger }

    private var resolvedBudget: Double? {
        if let b = fb.monthlyBudget { return b }
        return budgetHint
    }

    private var overBudgetFlag: Bool? {
        if let flag = fb.overBudget { return flag }
        if let budget = resolvedBudget { return fb.totalCurrent > budget }
        return nil
    }

    private var overageText: String? {
        guard overBudgetFlag == true,
              let budget = resolvedBudget,
              fb.totalCurrent > budget else { return nil }
        let over = fb.totalCurrent - budget
        let saveNext = over / 2.0
        return "Over budget by \(currency(over)). Aim to save \(currency(saveNext)) next month to get back on pace."
    }

    private var kudosText: String? {
        guard overBudgetFlag == false,
              let budget = resolvedBudget else { return nil }
        let cushion = max(0, budget - fb.totalCurrent)
        return cushion > 0
        ? "Nice work staying on track! You could invest/save an extra \(currency(cushion * 0.4)) next month."
        : "Nice work staying on track! Consider investing a little extra next month."
    }

    private var currentTotalText: String { String(format: "$%.2f", fb.totalCurrent) }
    private var previousTotalText: String { String(format: "$%.2f", fb.totalPrevious) }

    // pre-sort once
    private var sortedByMagnitude: [CategoryDelta] {
        fb.deltas.sorted { abs($0.delta) > abs($1.delta) }
    }
    private var downs: [CategoryDelta] { Array(sortedByMagnitude.filter { $0.delta < 0 }.prefix(3)) }
    private var ups:   [CategoryDelta] { Array(sortedByMagnitude.filter { $0.delta > 0 }.prefix(3)) }

    // Helper to format a delta line like "-$35 (−12%)" or "+$20 (+8%)"
    private func deltaLine(for d: CategoryDelta) -> String {
        let absD = abs(d.delta)
        let dollars = String(format: "$%.0f", absD)
        if let pct = d.pct {
            let pct100 = Int(round(pct * 100))
            if d.delta < 0 {
                return "-\(dollars) (\(pct100 <= 0 ? "\(abs(pct100))%" : "\(abs(pct100))%"))"
            } else {
                return "+\(dollars) (\(pct100)%"
                    + ")"
            }
        } else {
            return d.delta < 0 ? "-\(dollars)" : "+\(dollars)"
        }
    }

    private var eatOutNudgeText: String? {
        guard fb.totalDelta <= 0,
              let eatOut = fb.deltas.first(where: { $0.category.lowercased().contains("eat") && $0.delta < 0 })
        else { return nil }
        let amt = String(format: "$%.0f", abs(eatOut.delta))
        return "👏 Great job eating out less by \(amt)."
    }
    
    private var cutbacks: [CategoryDelta] {
        fb.cutbacks ?? []
    }

    private var comparisonLabel: String {
        switch fb.monthsCompared ?? 1 {
        case 1:  return "Last Month"
        case let n: return "Avg of \(n) Months"
        }
    }

    private var headerTitle: String {
        (fb.monthsCompared ?? 1) <= 1 ? "This Month vs Last Month" : "This Month vs Your Average"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
                Text(verdictText)
                    .font(.subheadline)
                    .foregroundColor(verdictColor)
            }

            // Totals
            HStack {
                VStack(alignment: .leading) {
                    Text("This Month")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                    Text(currentTotalText)
                        .font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(comparisonLabel)
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                    Text(previousTotalText)
                        .font(.headline)
                }
            }

            if let overageText {
                Text(overageText)
                    .font(.subheadline)
                    .foregroundColor(PLColor.danger)
            } else if let kudosText {
                Text(kudosText)
                    .font(.subheadline)
                    .foregroundColor(PLColor.success)
            }
            
            if !cutbacks.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Suggested cutbacks to catch up:")
                    .font(.subheadline)
                ForEach(cutbacks, id: \.category) { d in
                    FeedbackRow(
                        label: d.category,
                        deltaText: "Cut \(currency(d.delta))",
                        color: PLColor.danger
                    )
                }
            }

            // Spent less
            if !downs.isEmpty {
                Divider().padding(.vertical, 2)
                Text("You spent less on:")
                    .font(.subheadline)
                ForEach(downs, id: \.category) { d in
                    FeedbackRow(
                        label: d.category,
                        deltaText: deltaLine(for: d),
                        color: PLColor.success
                    )
                }
            }

            // Spent more
            if !ups.isEmpty {
                Divider().padding(.vertical, 2)
                Text("You spent more on:")
                    .font(.subheadline)
                ForEach(ups, id: \.category) { d in
                    FeedbackRow(
                        label: d.category,
                        deltaText: deltaLine(for: d),
                        color: PLColor.danger
                    )
                }
            }

            // Nudge
            if let nudge = eatOutNudgeText {
                Text(nudge)
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
                    .padding(.top, 4)
            }
        }
    }
    
    private func currency(_ v: Double) -> String {
        String(format: "$%.0f", v)
    }
}

// Models that match backend JSON
struct PlaidAccount: Identifiable, Codable, Hashable {
    let id: String           // account_id
    let name: String
    let mask: String?
    let type: String?
    let subtype: String?
    let itemId: String       // parent item id

    // UI-only computed helpers are fine (not encoded/decoded)
    var display: String { "\(name)\(mask.map { " ••\($0)" } ?? "")" }

    // Only decode the fields the backend actually returns:
    private enum CodingKeys: String, CodingKey {
        case id, name, mask, type, subtype, itemId
    }
}

struct UncategorizedTxn: Identifiable, Codable {
    let id: String      // transaction_id
    let date: String    // "YYYY-MM-DD"
    let name: String
    let amount: Double
    let accountId: String

    private enum CodingKeys: String, CodingKey {
        case id, date, name, amount, accountId
    }
}

struct SyncRequest: Codable {
    let username: String
    let account_ids: [String]
}

struct SyncResponse: Codable {
    let added: Int?
    let modified: Int?
    let removed: Int?
    let daysUpdated: Int?
    let uncategorized: [UncategorizedTxn]?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case added, modified, removed, daysUpdated, uncategorized, error
    }
}

struct CategoryAssignment: Identifiable, Codable {
    var id: String { txnId }
    let txnId: String
    let date: String
    let name: String
    var category: String
    let amount: Double

    private enum CodingKeys: String, CodingKey {
        case txnId, date, name, category, amount
    }
}

struct AssignPayload: Codable {
    let username: String
    let assignments: [CategoryAssignment]
}

#if canImport(UIKit)
private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

private struct AccountPickerSheet: View {
    @Binding var accounts: [PlaidAccount]
    @Binding var selectedAccountIds: Set<String>
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    var body: some View {
        NavigationView {
            Group {
                if accounts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                           Text("No accounts found")
                               .font(.subheadline)
                               .foregroundColor(.secondary)
                           Text("Try linking again from the Plaid screen.")
                               .font(.caption)
                               .foregroundColor(.secondary)
                       }
                       .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(accounts) { acct in
                        HStack {
                            Text(acct.display)
                            Spacer()
                            if selectedAccountIds.contains(acct.id) {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedAccountIds.contains(acct.id) {
                                selectedAccountIds.remove(acct.id)
                            } else {
                                selectedAccountIds.insert(acct.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sync") {
                        isPresented = false
                        onConfirm()
                    }
                    .disabled(selectedAccountIds.isEmpty)
                }
            }
        }
        .onAppear {
            print("AccountPickerSheet appeared; accounts.count = \(accounts.count)")
        }
    }
}
