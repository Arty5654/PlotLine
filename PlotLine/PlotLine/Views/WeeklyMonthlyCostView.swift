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
    
    // Subscription Tracking
    @State private var subscriptions: [SubscriptionItem] = []
    @State private var newSubscriptionName: String = ""
    @State private var newSubscriptionCost: String = ""
    @State private var newSubscriptionDueDate: Date = Date()
    //@State private var showSubscriptionSaveAlert: Bool = false
    
    // Tracker logic
    @State private var takeHomeMonthly: Double = 0
    private let trackerExclusions: Set<String> = [
        "401(k)", "401k", "401(k) Contribution", "401k Contribution"
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
                        .padding(.vertical, 6)
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
                                    onRemove: { removeCategory(item: costItems[i]) }
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
                
                
                // Subscriptions
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("📅 Subscription Tracker")
                        .font(.headline)
                    
                    // Custom list for a consistent look
                    LazyVStack(spacing: PLSpacing.sm) {
                        ForEach($subscriptions) { $subscription in
                            HStack(spacing: PLSpacing.sm) {
                                Text(subscription.name)
                                    .frame(width: 90, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                TextField("Cost ($)", text: $subscription.cost)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                
                                DatePicker("", selection: $subscription.dueDate, displayedComponents: .date)
                                    .labelsHidden()
                                
                                Button {
                                    deleteSubscription(subscription: subscription)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(PLColor.danger)
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: PLSpacing.sm) {
                        TextField("Subscription Name", text: $newSubscriptionName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Cost ($)", text: $newSubscriptionCost)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        DatePicker("", selection: $newSubscriptionDueDate, displayedComponents: .date)
                            .labelsHidden()
                        Button {
                            addSubscription()
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.green)
                        }
                    }
                    
                    Button("Save Subscriptions", action: saveSubscriptions)
                        .buttonStyle(PrimaryButton())
                }
                .plCard()
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
        .onAppear {
            rebuildWeek(for: Date())
            selectedDay = Date()
            loadBudgetLimits()
            fetchMonthlyFeedback(for: selectedDay)
            fetchSubscriptions()
            checkForUpcomingSubscriptions()
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
    
    // MARK: - Subscriptions
    private func addSubscription() {
        guard !newSubscriptionName.isEmpty, !newSubscriptionCost.isEmpty else { return }
        let subItem = SubscriptionItem(name: newSubscriptionName, cost: newSubscriptionCost, dueDate: newSubscriptionDueDate)
        subscriptions.append(subItem)
        newSubscriptionName = ""
        newSubscriptionCost = ""
        newSubscriptionDueDate = Date()
    }
    
    private func fetchSubscriptions() {
        let urlString = "\(BackendConfig.baseURLString)/api/subscriptions/\(username)"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Error fetching subscription data:", error.localizedDescription)
                DispatchQueue.main.async { self.subscriptions = [] }
                return
            }
            guard let data = data, !data.isEmpty else {
                DispatchQueue.main.async { self.subscriptions = [] }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(SubscriptionMapResponse.self, from: data)
                let list: [SubscriptionItem] = decoded.subscriptions.map { (name, subData) in
                    SubscriptionItem(name: name, cost: subData.cost, dueDate: subData.dueDate)
                }
                DispatchQueue.main.async {
                    self.subscriptions = list
                    self.checkForUpcomingSubscriptions()
                }
            } catch {
                print("Failed to decode subscription data:", error)
                DispatchQueue.main.async { self.subscriptions = [] }
            }
        }.resume()
    }
    
    private func deleteSubscription(subscription: SubscriptionItem) {
        let urlString = "\(BackendConfig.baseURLString)/api/subscriptions/\(username)/\(subscription.name)"
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        DispatchQueue.main.async {
            self.subscriptions.removeAll { $0.name == subscription.name }
            calendarVM.deleteEventByType("subscription-\(subscription.name.lowercased())")
        }
        URLSession.shared.dataTask(with: request).resume()
    }
    
    private func saveSubscriptions() {
        var dict = [String: SubscriptionData]()
        for sub in subscriptions {
            dict[sub.name] = SubscriptionData(name: sub.name, cost: sub.cost, dueDate: sub.dueDate)
            DispatchQueue.main.async {
                calendarVM.createEvent(
                    title: "\(sub.name) Subscription",
                    description: "Monthly cost of $\(sub.cost)",
                    startDate: sub.dueDate,
                    endDate: sub.dueDate,
                    eventType: "subscription-\(sub.name.lowercased())",
                    recurrence: "monthly",
                    invitedFriends: []
                )
            }
        }
        let payload = SubscriptionUpload(username: username, subscriptions: dict)
        guard let json = try? JSONEncoder().encode(payload) else { return }
        
        var request = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/subscriptions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json
        URLSession.shared.dataTask(with: request).resume()
        //DispatchQueue.main.async { self.showSubscriptionSaveAlert = true }
        DispatchQueue.main.async {
            self.activeAlert = AppAlert(title: "Success", message: "Your subscriptions have been saved.")
        }
        
    }
    
    private func checkForUpcomingSubscriptions() {
        for sub in subscriptions {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: sub.dueDate).day ?? 0
            if days <= 3, days >= 0 {
                sendNotification(
                    title: "📅 Subscription Due Soon!",
                    message: "\(sub.name) is due in \(days) days."
                )
            }
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
        HStack(spacing: PLSpacing.sm) {
            Button {
                selectedDay = selectedDay.addingDays(-7)
                rebuildWeek(for: selectedDay)
                loadWeeklyPeriod(for: selectedDay)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            
            Spacer(minLength: PLSpacing.sm)
            
            ForEach(weekDays, id: \.self) { d in
                let isSelected = Calendar.current.isDate(d, inSameDayAs: selectedDay)
                VStack(spacing: 1) {
                    Text(d.shortWeekday())
                        .font(.caption2)
                        .foregroundColor(PLColor.textSecondary)
                    Text(d.monthDay())
                        //.font(.caption2)
                        .font(.system(.body, design: .default))
                        .minimumScaleFactor(0.5)
                    //.bold()
                        .foregroundColor(PLColor.textPrimary)
                }
                .frame(width: 24, height: 24)
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
                .background(isSelected ? PLColor.accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedDay = d
                    loadCostsForSelectedDay()
                }
            }
            
            Spacer(minLength: PLSpacing.sm)
            
            Button {
                selectedDay = selectedDay.addingDays(+7)
                rebuildWeek(for: selectedDay)
                loadWeeklyPeriod(for: selectedDay)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 24)
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
    
    var body: some View {
        HStack(spacing: PLSpacing.sm) {
            Text(item.category)
                .frame(width: 130, alignment: .leading)
            
            TextField("Amount ($)", text: $item.amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: item.amount) { _ in
                    // handled by parent warning builder if desired
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


struct SubscriptionRequest: Codable {
    let username: String
    let subscriptions: [SubscriptionItem]
}

private struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
