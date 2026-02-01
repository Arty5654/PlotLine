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
struct WeeklyMonthlyCostView: View {
    @State private var selectedType = "Weekly"
    @State private var costItems: [BudgetItem] = []
    @State private var budgetLimits: [String: Double] = [:]
    @State private var newCategory: String = ""
    
    //    @State private var showSuccessAlert: Bool = false
    //    @State private var showBudgetWarning: Bool = false
    
    @State private var budgetWarningMessage: String = ""
    
    // Recurring subscription detection after Plaid sync
    @State private var recurringPrompts: [RecurringChargePromptModel] = []
    @State private var showRecurringPrompt = false
    
    // Tracker logic
    @State private var takeHomeMonthly: Double = 0
    private let trackerExclusions: Set<String> = [
        "401(k)", "401k", "401(k) Contribution", "401k Contribution", "Subscriptions"
    ]
    
    // Week strip
    @State private var selectedDay: Date = Date()
    @State private var weekDays: [Date] = []
    @State private var weeklyPeriod: WeeklyPeriod? = nil
    
    // Totals
    private var budgetTotal: Double {
        let base = takeHomeMonthly > 0 ? takeHomeMonthly : budgetLimits.values.reduce(0, +)
        return selectedType == "Monthly" ? base : base / 4.0
    }
    private var enteredTotal: Double {
        costItems
            .filter { !trackerExclusions.contains($0.category) }
            .compactMap { Double($0.amount) }
            .reduce(0, +)
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
    
    // Add Categories after sync
    @State private var pendingAssignments: [CategoryAssignment] = []
    @State private var newCategoryName: String = ""
    
    // Build the choices list from UI state
    private var existingCategories: [String] {
        let fromLimits = budgetLimits.keys
        let fromCosts  = costItems.map { $0.category }
        return Array(Set(fromLimits).union(fromCosts)).sorted()
    }
    
    @EnvironmentObject var calendarVM: CalendarViewModel
    
    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    var body: some View {
        // Avoid large nav title ("zoomed") look
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                
                // Header + Segmented
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Enter Your \(selectedType) Costs")
                        .font(.headline)
                        .bold()
                        .foregroundColor(PLColor.textPrimary)
                    
                    Picker("Type", selection: $selectedType) {
                        Text("Weekly").tag("Weekly")
                        Text("Monthly").tag("Monthly")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { newVal in
                        loadBudgetLimits()
                        loadSavedData()
                        if newVal == "Weekly" {
                            rebuildWeek(for: selectedDay)
                            loadWeeklyPeriod(for: selectedDay)
                        } else {
                            fetchMonthlyFeedback(for: selectedDay)
                        }
                        UserDefaults.standard.set(newVal, forKey: "selectedType")
                    }
                }
                .plCard()
                
                // Week strip (only for Weekly)
                if selectedType == "Weekly" {
                    weekHeader
                        .plCard()
                }
                
                // Summary Card
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
                            Text("Total Budget")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                            Text("$\(budgetTotal, specifier: "%.2f")")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Entered")
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
                
                // Monthly Feedback (only when in Monthly mode and we have data)
                if selectedType == "Monthly" {
                    if let fb = monthlyFeedback {
                        MonthlyFeedbackCard(fb: fb, budgetHint: budgetTotal)
                            .plCard()
                    } else {
                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Feedback")
                                .font(.headline)
                            Text("Need more data — complete a full month first.")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)
                        }
                        .plCard()
                    }
                }
                
                // Input list (custom rows instead of List to avoid nested scroll + zoomy look)
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Costs")
                        .font(.headline)
                        .foregroundColor(PLColor.textPrimary)
                    
                    LazyVStack(spacing: PLSpacing.sm) {
                        ForEach(costItems.indices, id: \.self) { i in
                            if !trackerExclusions.contains(costItems[i].category) {
                                CostRow(
                                    item: $costItems[i],
                                    budgetLimit: budgetLimits[costItems[i].category],
                                    onRemove: { removeCategory(item: costItems[i]) },
                                    onChangeAmount: { newVal in
                                        costItems[i].amount = sanitizeAmount(newVal)
                                    }
                                )
                            }
                        }
                    }
                    
                    HStack(spacing: PLSpacing.sm) {
                        TextField("New Category", text: $newCategory)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            addCategory()
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .tint(.green)
                    }
                }
                .plCard()
                
                // Save Button
                Button("Save Costs", action: saveCosts)
                    .buttonStyle(PrimaryButton())
                    .padding(.top, -PLSpacing.sm) // visually tighten spacing to card above
                
                // Sync
                // Present the sheet when user taps "Sync Transactions"
                Button {
                    Task { await fetchAccountsForSelection() }
                } label: {
                    Label("Sync Transactions", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showAccountPicker) {
                    AccountPickerSheet(
                        accounts: $selectableAccounts,
                        selectedAccountIds: $selectedAccountIds,
                        isPresented: $showAccountPicker
                    ) {
                        Task { await syncSelectedAccounts() }
                    }
                }
                
                
                // Subscriptions UI moved to SubsView (kept here intentionally blank)
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { hideKeyboard() }
        }
        //.navigationTitle("\(selectedType) Cost Input")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(selectedType) Cost Input")
                    .font(.headline)
            }
//            ToolbarItemGroup(placement: .keyboard) {
//                Spacer()
//                Button("Done") { hideKeyboard() }
//            }
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
            selectedType = "Weekly" // default to weekly each time page opens
            rebuildWeek(for: selectedDay)
            loadWeeklyPeriod(for: selectedDay)
            loadBudgetLimits()
            loadSavedData()
            fetchTakeHomeMonthly()
        }
        
        .sheet(isPresented: $showCategorizer, onDismiss: {
            pendingAssignments = []
        }) {
            NavigationView {
                VStack(spacing: 12) {
                    if pendingAssignments.isEmpty {
                        Text("Loading…").padding()
                    } else {
                        List {
                            Section("Uncategorized transactions") {
                                ForEach($pendingAssignments) { $a in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("\(a.date)  •  $\(a.amount, specifier: "%.2f")")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Picker("Category", selection: $a.category) {
                                            ForEach(existingCategories, id: \.self) { c in
                                                Text(c).tag(c)
                                            }
                                        }
                                    }
                                }
                            }
                            Section("Create new category") {
                                HStack {
                                    TextField("e.g. Baby Supplies", text: $newCategoryName)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Add") {
                                        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !name.isEmpty else { return }
                                        // Add to current set and apply to last edited row as convenience
                                        self.costItems.append(BudgetItem(category: name, amount: ""))
                                        if !existingCategories.contains(name) {
                                            // existingCategories is computed; just set on selected rows
                                        }
                                        // Assign the new category to any rows currently selected by user (optional)
                                        if let idx = pendingAssignments.indices.last {
                                            pendingAssignments[idx].category = name
                                        }
                                        newCategoryName = ""
                                    }
                                }
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
                            .disabled(pendingAssignments.isEmpty)
                    }
                }
                .onAppear(perform: openCategorizer)
            }
        }
        
        // Final confirmation popup
        .alert("Sync complete", isPresented: $showSyncDone) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your transactions have been synced and categorized.")
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
        .onAppear {
            rebuildWeek(for: Date())
            selectedDay = Date()
            loadBudgetLimits()
            fetchMonthlyFeedback(for: selectedDay)
            requestNotificationPermission()
            fetchTakeHomeMonthly()
        }
        .onReceive(NotificationCenter.default.publisher(for: .plaidSynced)) { _ in
            // after backend wrote to weekly/monthly, just fetch again
            rebuildWeek(for: selectedDay)
            loadWeeklyPeriod(for: selectedDay)
            if selectedType == "Monthly" {
                fetchMonthlyFeedback(for: selectedDay)
            }
        }
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
    
    private func postMerge(type: String, date: Date, values: [String: Double], completion: @escaping (Bool)->Void) {
        let payload: [String: Any] = [
            "username": username,
            "type": type,
            "date": date.ymd(),
            "costs": values
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { completion(false); return }
        
        var req = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/costs/merge-dated")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            completion(error == nil && (200...299).contains(code))
        }.resume()
    }
    
    private func saveCosts() {
        // Validate all cost rows (non-excluded) have a value and are numeric
        let invalid = costItems.first { item in
            guard !trackerExclusions.contains(item.category) else { return false }
            let trimmed = item.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            return Double(trimmed) == nil
        }
        if invalid != nil {
            activeAlert = AppAlert(title: "Missing Amount", message: "Please enter a number for every cost before saving.")
            return
        }

        // build payload excluding tracker exclusions and zeroes
        let values = costItems.reduce(into: [String: Double]()) { acc, item in
            guard !trackerExclusions.contains(item.category),
                  let v = Double(item.amount), v != 0 else { return }
            acc[item.category] = v
        }
        
        let day = selectedDay
        let group = DispatchGroup()
        var okW = false, okM = false
        
        group.enter()
        postMerge(type: "weekly", date: day, values: values) { ok in okW = ok; group.leave() }
        
        group.enter()
        postMerge(type: "monthly", date: day, values: values) { ok in okM = ok; group.leave() }
        
        group.notify(queue: .main) {
            if !(okW && okM) {
                print("Merge failed weekly:\(okW), monthly:\(okM)")
                activeAlert = AppAlert(title: "Save Error", message: "We couldn't save everything. Please try again.")
                return
            }
            self.loadWeeklyPeriod(for: self.selectedDay)
            self.activeAlert = AppAlert(
                title: "Success",
                message: "Your \(selectedType) costs have been saved."
            )
            
            if self.selectedType == "Monthly" {
                self.fetchMonthlyFeedback(for: self.selectedDay)
            }
        }
        
    }
    
    // MARK: - Budget Limits + Costs
    private func loadBudgetLimits() {
        let urlString = "\(BackendConfig.baseURLString)/api/budget/\(username)/\(selectedType.lowercased())"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Error fetching budget:", error.localizedDescription)
                return
            }
            guard let data = data, !data.isEmpty else { return }
            do {
                let decoded = try JSONDecoder().decode(BudgetResponse.self, from: data)
                DispatchQueue.main.async {
                    // exclude 401k-like lines from limit visual
                    self.budgetLimits = decoded.budget.filter { !trackerExclusions.contains($0.key) }
                    
                    if self.selectedType == "Weekly" {
                        self.rebuildWeek(for: self.selectedDay)
                        self.loadWeeklyPeriod(for: self.selectedDay)
                    } else {
                        self.loadSavedData()
                        self.fetchMonthlyFeedback(for: self.selectedDay)
                    }
                }
            } catch {
                print("Failed to decode budget data:", error)
            }
        }.resume()
    }
    
    private func loadSavedData() {
        if selectedType == "Weekly" {
            loadCostsForSelectedDay() // uses weeklyPeriod already loaded
            return
        }
        
        // MONTHLY: read the period file and show totals
        let monthStr = monthYYYYMM(from: selectedDay)
        let urlString = "\(BackendConfig.baseURLString)/api/costs/monthly/\(username)?month=\(monthStr)"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error { print("Monthly fetch error:", error); return }
            guard let data = data else { return }
            if let period = try? JSONDecoder().decode(WeeklyPeriod.self, from: data) {
                DispatchQueue.main.async {
                    let totals = period.totals
                    let keys = Set(totals.keys)
                        .union(self.budgetLimits.keys)
                        .subtracting(self.trackerExclusions)
                        .sorted()
                    self.costItems = keys.map { BudgetItem(category: $0, amount: String(totals[$0] ?? 0.0)) }
                }
            }
        }.resume()
    }
    
    private func monthYYYYMM(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
    
    
    private func setDefaultCategories() {
        self.costItems = [
            BudgetItem(category: "Rent", amount: ""),
            BudgetItem(category: "Groceries", amount: ""),
            BudgetItem(category: "Subscriptions", amount: ""),
            BudgetItem(category: "Eating Out", amount: ""),
            BudgetItem(category: "Entertainment", amount: ""),
            BudgetItem(category: "Utilities", amount: ""),
            BudgetItem(category: "Savings", amount: ""),
            BudgetItem(category: "Miscellaneous", amount: ""),
            BudgetItem(category: "Transportation", amount: ""),
            BudgetItem(category: "Roth IRA", amount: ""),
            BudgetItem(category: "Car Insurance", amount: ""),
            BudgetItem(category: "Health Insurance", amount: ""),
            BudgetItem(category: "Brokerage", amount: "")
        ]
    }
    
    private func checkBudgetWarnings() {
        budgetWarningMessage = ""
        for item in costItems {
            if let limit = budgetLimits[item.category],
               let cost = Double(item.amount),
               cost >= limit {
                budgetWarningMessage += "\(item.category) exceeds the budget limit!\n"
            }
        }
        //showBudgetWarning = !budgetWarningMessage.isEmpty
        if !budgetWarningMessage.isEmpty {
            activeAlert = AppAlert(title: "⚠️ Budget Warning", message: budgetWarningMessage)
        }
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
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/recurring/analyze/\(username)?months=3&remindAfterMonths=2") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
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
                let (data, _) = try await URLSession.shared.data(from: url)
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
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let v = obj["monthlyNet"] as? Double {
                DispatchQueue.main.async { self.takeHomeMonthly = v }
            } else if let s = obj["monthlyNet"] as? String, let v = Double(s) {
                DispatchQueue.main.async { self.takeHomeMonthly = v }
            }
        }.resume()
    }
    
    // MARK: - Weekly header + period loading
    private func rebuildWeek(for date: Date) {
        let start = Calendar.current.startOfWeek(for: date)
        weekDays = (0..<7).map { start.addingDays($0) }
    }
    
    private var weekHeader: some View {
        HStack(spacing: 4) {
            Button {
                selectedDay = selectedDay.addingDays(-7)
                rebuildWeek(for: selectedDay)
                loadWeeklyPeriod(for: selectedDay)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
                    .foregroundColor(PLColor.textPrimary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }

            Spacer(minLength: 4)
            
            ForEach(weekDays, id: \.self) { d in
                let isSelected = Calendar.current.isDate(d, inSameDayAs: selectedDay)
                VStack(spacing: 1) {
                    Text(d.shortWeekday())
                        .font(.system(size: 9))
                        .foregroundColor(PLColor.textSecondary)
                    Text(d.monthDay())
                        .font(.system(size: 11))
                        .foregroundColor(PLColor.textPrimary)
                }
                .frame(minWidth: 28)
                .padding(.vertical, 3)
                .padding(.horizontal, 2)
                .background(isSelected ? PLColor.accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedDay = d
                    loadCostsForSelectedDay()
                }
            }

            Spacer(minLength: 4)

            Button {
                selectedDay = selectedDay.addingDays(+7)
                rebuildWeek(for: selectedDay)
                loadWeeklyPeriod(for: selectedDay)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(PLColor.textPrimary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
        }
    }
    
    private func loadWeeklyPeriod(for anyDate: Date) {
        let weekStart = Calendar.current.startOfWeek(for: anyDate).ymd()
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/weekly/\(username)?week_start=\(weekStart)"
        guard let url = URL(string: urlStr) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let period = try? JSONDecoder().decode(WeeklyPeriod.self, from: data) else {
                DispatchQueue.main.async {
                    self.weeklyPeriod = WeeklyPeriod(periodKey: "", start: weekStart, end: weekStart, days: [:], totals: [:])
                    self.loadCostsForSelectedDay()
                }
                return
            }
            DispatchQueue.main.async {
                self.weeklyPeriod = period
                self.loadCostsForSelectedDay()
            }
        }.resume()
    }
    
    private func loadCostsForSelectedDay() {
        let dayKey = selectedDay.ymd()
        let dayMap = weeklyPeriod?.days[dayKey] ?? [:]
        let keys = Set(dayMap.keys)
            .union(Set(budgetLimits.keys))
            .subtracting(trackerExclusions)
            .sorted()
        self.costItems = keys.map { BudgetItem(category: $0, amount: String(dayMap[$0] ?? 0.0)) }
    }
    
    // Feedback
    private func fetchMonthlyFeedback(for date: Date) {
        let currentMonth = monthYYYYMM(from: Date())
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/feedback/\(username)?month=\(currentMonth)")
        else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode),
                let data = data,
                !data.isEmpty,
                let decoded = try? JSONDecoder().decode(MonthlyFeedback.self, from: data),
                decoded.month == currentMonth
            else { DispatchQueue.main.async { self.monthlyFeedback = nil }; return }

            // Require a real previous-month baseline
            if decoded.totalPrevious == 0 {
                DispatchQueue.main.async { self.monthlyFeedback = nil }
                return
            }

            // If both totals are zero, treat as "no data"
            if decoded.totalCurrent == 0 && decoded.totalPrevious == 0 {
                DispatchQueue.main.async { self.monthlyFeedback = nil }
                return
            }

            DispatchQueue.main.async { self.monthlyFeedback = decoded }
        }.resume();
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
            let (data, resp) = try await URLSession.shared.data(from: url)
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
    
    // Call sync with selected accounts
    private func syncSelectedAccounts() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/sync") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = SyncRequest(username: username, account_ids: Array(selectedAccountIds))
        guard let data = try? JSONEncoder().encode(body) else { return }
        req.httpBody = data
        
        do {
            let (respData, _) = try await URLSession.shared.data(for: req)
            let syncResp = try JSONDecoder().decode(SyncResponse.self, from: respData)
            await MainActor.run {
                self.uncategorized = syncResp.uncategorized
                if uncategorized.isEmpty {
                    self.showSyncDone = true
                    // refresh UI
                    self.rebuildWeek(for: self.selectedDay)
                    self.loadWeeklyPeriod(for: self.selectedDay)
                    if self.selectedType == "Monthly" { self.fetchMonthlyFeedback(for: self.selectedDay) }
                    Task { await fetchRecurringSubscriptionPrompts() }
                } else {
                    self.showCategorizer = true
                }
            }
        } catch {
            print("sync error:", error)
        }
    }
    
    private func openCategorizer() {
        pendingAssignments = uncategorized.map {
            CategoryAssignment(txnId: $0.id, date: $0.date, category: existingCategories.first ?? "Miscellaneous", amount: $0.amount)
        }
    }
    
    private func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
    
    // Send assignments to backend
    private func submitAssignments() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/assign") else { return }
        var req = URLRequest(url: url)
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
            
            // pick a date to jump to (if exactly one day was assigned)
            let days = Array(Set(pendingAssignments.map { $0.date })).sorted()
            await MainActor.run {
                self.showCategorizer = false
                self.showSyncDone = true
                if days.count == 1, let d = parseYMD(days[0]) {
                    self.selectedDay = d
                }
                self.rebuildWeek(for: self.selectedDay)
                self.loadWeeklyPeriod(for: self.selectedDay)
                if self.selectedType == "Monthly" { self.fetchMonthlyFeedback(for: self.selectedDay) }
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
    
    var body: some View {
        HStack(spacing: PLSpacing.sm) {
            Text(item.category)
                .frame(width: 130, alignment: .leading)
            
            TextField("Amount ($)", text: $item.amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: item.amount) { newValue in
                    onChangeAmount(newValue)
                }
            
            if let limit = budgetLimit, let cost = Double(item.amount) {
                if cost > limit {
                    IconBadge(text: "Over budget!", system: "exclamationmark.triangle.fill", color: PLColor.danger)
                } else if cost >= limit * 0.8 {
                    IconBadge(text: "Nearing budget", system: "exclamationmark.triangle.fill", color: PLColor.warning)
                }
            }
            
            Spacer(minLength: PLSpacing.sm)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(PLColor.danger)
            }
        }
    }
}

// Tiny badge used above
private struct IconBadge: View {
    let text: String
    let system: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white)
        .foregroundColor(color)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25)))
    }
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
// For the days of the week at the top
struct WeeklyPeriod: Codable {
    let periodKey: String
    let start: String
    let end: String
    let days: [String: [String: Double]] // "YYYY-MM-DD" -> category->amount
    let totals: [String: Double]
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
        print("Decoding date: \(dateString)")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            self.wrappedValue = date
            print("Successfully decoded date:", date)
        } else {
            print("Failed to decode date:", dateString)
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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
    let cost: String
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
    let delta: Double        // current - previous
    let pct: Double?         // nil means no baseline last month
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

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Text("This Month vs Last Month")
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
                    Text("Last Month")
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
    let added: Int
    let modified: Int
    let removed: Int
    let daysUpdated: Int
    let uncategorized: [UncategorizedTxn]

    private enum CodingKeys: String, CodingKey {
        case added, modified, removed, daysUpdated, uncategorized
    }
}

struct CategoryAssignment: Identifiable, Codable {
    var id: String { txnId }
    let txnId: String
    let date: String
    var category: String
    let amount: Double

    private enum CodingKeys: String, CodingKey {
        case txnId, date, category, amount
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
