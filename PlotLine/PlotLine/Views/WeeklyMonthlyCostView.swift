//
//  WeeklyMonthlyCostView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/15/25.
//

import SwiftUI
import Foundation
import UserNotifications

struct WeeklyMonthlyCostView: View {
    @State private var selectedType = UserDefaults.standard.string(forKey: "selectedType") ?? "Weekly"
    @State private var costItems: [BudgetItem] = []
    @State private var budgetLimits: [String: Double] = [:] // Stores budget limits
    @State private var newCategory: String = ""
    
    @State private var showSuccessAlert: Bool = false
    @State private var showBudgetWarning: Bool = false
    @State private var budgetWarningMessage: String = ""
    
    // Subscription Tracking
    @State private var subscriptions: [SubscriptionItem] = []
    @State private var newSubscriptionName: String = ""
    @State private var newSubscriptionCost: String = ""
    @State private var newSubscriptionDueDate: Date = Date()
    @State private var showSubscriptionSaveAlert: Bool = false
    
    // Get live totals
    @State private var takeHomeMonthly: Double = 0
    private let trackerExclusions: Set<String> = ["401(k)", "401k", "401(k) Contribution", "401k Contribution"]
    
    // for the Days of the week at the top of the page
    @State private var selectedDay: Date = Date()
    @State private var weekDays: [Date] = []
    @State private var weeklyPeriod: WeeklyPeriod? = nil

    private var budgetTotal: Double {
        let base = takeHomeMonthly > 0 ? takeHomeMonthly : budgetLimits.values.reduce(0, +)
        return selectedType == "Monthly" ? base : base / 4.0
    }

    private var enteredTotal: Double {
        costItems
            .filter { !trackerExclusions.contains($0.category) } // exclude 401k from tracker math
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
    
    @EnvironmentObject var calendarVM: CalendarViewModel
    
    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                // ------------------
                //  COSTS SECTION
                // ------------------
                Text("Enter Your \(selectedType) Costs")
                    .font(.title2)
                    .bold()

                // Weekly/Monthly Toggle
                Picker("Type", selection: $selectedType) {
                    Text("Weekly").tag("Weekly")
                    Text("Monthly").tag("Monthly")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: selectedType) { newVal in
                    loadBudgetLimits()
                    loadSavedData()
                    if newVal == "Weekly" {
                        rebuildWeek(for: selectedDay)
                        loadWeeklyPeriod(for: selectedDay)
                    }
                }
                
                if selectedType == "Weekly" {
                    weekHeader
                        .padding(.top, 4)
                }
                
                // Summary Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Budget Summary")
                            .font(.headline)
                        Spacer()
                        Text(utilizationPercentText)
                            .font(.subheadline)
                            .foregroundColor(utilization >= 1.0 ? .red : .secondary)
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Budget")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("$\(budgetTotal, specifier: "%.2f")")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Entered")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("$\(enteredTotal, specifier: "%.2f")")
                                .font(.headline)
                        }
                    }

                    ProgressView(value: utilization)
                        .progressViewStyle(.linear)

                    let over = remaining < 0
                    Text(over
                         ? "Over by $\(abs(remaining), specifier: "%.2f")"
                         : "Left: $\(remaining, specifier: "%.2f")")
                        .font(.subheadline)
                        .foregroundColor(over ? .red : .green)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)


                // Expense Inputs
                List {
                    ForEach($costItems.filter { !trackerExclusions.contains($0.wrappedValue.category) }) { $item in
                        HStack {
                            Text(item.category)
                                .frame(width: 120, alignment: .leading)
                            TextField("Amount ($)", text: $item.amount)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: item.amount) {
                                    checkBudgetWarnings()
                                }

                            // Budget Warning Indicator (if cost exceeds budget)
                            if let budget = budgetLimits[item.category],
                               let cost = Double(item.amount) {
                                if cost > budget {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .overlay(
                                            Text("Over budget!")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                                .padding(5)
                                                .frame(width: 120)
                                                .background(Color.white)
                                                .cornerRadius(5)
                                                .shadow(radius: 3)
                                                .fixedSize(horizontal: true, vertical: false)
                                                .offset(y: -25),
                                            alignment: .top
                                        )
                                } else if cost >= budget * 0.8 {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .overlay(
                                            Text("Nearing budget")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .padding(5)
                                                .frame(width: 120)
                                                .background(Color.white)
                                                .cornerRadius(5)
                                                .shadow(radius: 3)
                                                .fixedSize(horizontal: true, vertical: false)
                                                .offset(y: -25),
                                            alignment: .top
                                        )
                                }
                            }

                            // Remove category button
                            Button(action: { removeCategory(item: item) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .frame(height: 250)

                // Add new category
                HStack {
                    TextField("New Category", text: $newCategory)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button(action: addCategory) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding()

                // Save Costs Button
                Button(action: saveCosts) {
                    Text("Save Costs")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
                .alert(isPresented: $showBudgetWarning) {
                    Alert(
                        title: Text("⚠️ Budget Warning"),
                        message: Text(budgetWarningMessage),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
            .padding()
            .navigationTitle("\(selectedType) Cost Input")
            .alert(isPresented: $showSuccessAlert) {
                Alert(
                    title: Text("Success"),
                    message: Text("Your \(selectedType) costs have been saved."),
                    dismissButton: .default(Text("OK"))
                )
            }

            // --------------------------
            //   SUBSCRIPTION TRACKER
            // --------------------------
            VStack(alignment: .leading, spacing: 15) {
                Text("📅 Subscription Tracker")
                    .font(.title2)
                    .bold()

                List {
                    ForEach($subscriptions) { $subscription in
                        HStack {
                            Text(subscription.name)
                                .frame(width: 80, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            TextField("Cost ($)", text: $subscription.cost)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            DatePicker("", selection: $subscription.dueDate, displayedComponents: .date)
                                .labelsHidden()
                            Button(action: {
                                deleteSubscription(subscription: subscription)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .frame(height: 200)

                // Subscription input
                HStack {
                    TextField("Subscription Name", text: $newSubscriptionName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Cost ($)", text: $newSubscriptionCost)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    DatePicker("", selection: $newSubscriptionDueDate, displayedComponents: .date)
                        .labelsHidden()
                    Button(action: addSubscription) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                // Save Subscriptions
                Button(action: saveSubscriptions) {
                    Text("Save Subscriptions")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
//                Button("Test Notification") {
//                    sendNotification(title: "Manual Test", message: "Did this show up?")
//                }
//                .padding()
//                .background(Color.blue)
//                .foregroundColor(.white)
//                .cornerRadius(10)

            }
            .padding()
            .alert(isPresented: $showSubscriptionSaveAlert) {
                Alert(
                    title: Text("Success"),
                    message: Text("Your subscriptions have been saved."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        // onAppear at the end, so it’s still inside the struct’s body
        .onAppear {
            rebuildWeek(for: Date())
            selectedDay = Date()
            loadWeeklyPeriod(for: selectedDay)
            loadBudgetLimits()
            loadSavedData()
            fetchSubscriptions()
            checkForUpcomingSubscriptions()
            requestNotificationPermission()
            fetchTakeHomeMonthly()
        }
    }

    // MARK: - Cost Functions
    
    private func addCategory() {
        guard !newCategory.isEmpty else { return }
        if !costItems.contains(where: { $0.category.lowercased() == newCategory.lowercased() }) {
            costItems.append(BudgetItem(category: newCategory, amount: ""))
        }
        newCategory = ""
    }

    private func removeCategory(item: BudgetItem) {
        costItems.removeAll { $0.id == item.id }
    }

    private func deleteItems(at offsets: IndexSet) {
        costItems.remove(atOffsets: offsets)
    }

    private func postMerge(type: String, date: Date, values: [String: Double], completion: @escaping (Bool)->Void) {
        let payload: [String: Any] = [
            "username": username,
            "type": type, // "weekly" | "monthly"
            "date": date.ymd(),
            "costs": values
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { completion(false); return }

        var req = URLRequest(url: URL(string: "http://localhost:8080/api/costs/merge-dated")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { _,_,err in
            completion(err == nil)
        }.resume()
    }

    private func saveCosts() {
        let values = costItems.reduce(into: [String: Double]()) { acc, item in
            //if let v = Double(item.amount), v != 0 { acc[item.category] = v }
            guard !trackerExclusions.contains(item.category),
                  let v = Double(item.amount),
                  v != 0
                else { return }
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
            if !(okW && okM) { print("⚠️ Merge failed weekly:\(okW), monthly:\(okM)") }
            // Refresh week so totals update
            self.loadWeeklyPeriod(for: self.selectedDay)
            self.showSuccessAlert = true
        }
    }


    // MARK: - Budget Limits
    private func loadBudgetLimits() {
        let urlString = "http://localhost:8080/api/budget/\(username)/\(selectedType.lowercased())"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching budget:", error.localizedDescription)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("No budget data found.")
                return
            }

            do {
                let decodedData = try JSONDecoder().decode(BudgetResponse.self, from: data)
                DispatchQueue.main.async {
                    self.budgetLimits = decodedData.budget.filter { !trackerExclusions.contains($0.key)}
                }
            } catch {
                print("Failed to decode budget data:", error)
            }
        }.resume()
    }

    // MARK: - Load Saved Costs or Default
    private func loadSavedData() {
        let urlString = "http://localhost:8080/api/costs/\(username)/\(selectedType.lowercased())"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching costs:", error.localizedDescription)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("No cost data found.")
                DispatchQueue.main.async {
                    self.setDefaultCategories()
                }
                return
            }

            do {
                let decodedData = try JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data)
                DispatchQueue.main.async {
                    self.costItems = decodedData.costs
                        .filter { !trackerExclusions.contains($0.key) }
                        .map { BudgetItem(category: $0.key, amount: String($0.value)) }
                }
            } catch {
                print("Failed to decode costs:", error)
            }
        }.resume()
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
            //BudgetItem(category: "401(k)", amount: ""),
            BudgetItem(category: "Roth IRA", amount: ""),
            BudgetItem(category: "Car Insurance", amount: ""),
            BudgetItem(category: "Health Insurance", amount: ""),
            BudgetItem(category: "Brokerage", amount: "")
        ]
    }

    // Check for budget warnings dynamically
    private func checkBudgetWarnings() {
        budgetWarningMessage = ""
        for item in costItems {
            if let budgetLimit = budgetLimits[item.category],
               let costValue = Double(item.amount),
               costValue >= budgetLimit {
                budgetWarningMessage += "\(item.category) exceeds the budget limit!\n"
            }
        }
        showBudgetWarning = !budgetWarningMessage.isEmpty
    }

    // MARK: - Subscription Functions
    private func addSubscription() {
        guard !newSubscriptionName.isEmpty, !newSubscriptionCost.isEmpty else { return }
        let subItem = SubscriptionItem(
            name: newSubscriptionName,
            cost: newSubscriptionCost,
            dueDate: newSubscriptionDueDate
        )
        subscriptions.append(subItem)
        newSubscriptionName = ""
        newSubscriptionCost = ""
        newSubscriptionDueDate = Date()
    }
    
    
    private func fetchSubscriptions() {
        let urlString = "http://localhost:8080/api/subscriptions/\(username)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching subscription data:", error.localizedDescription)
                DispatchQueue.main.async {
                    self.subscriptions = []
                }
                return
            }

            guard let data = data, !data.isEmpty else {
                print("No subscription data found; using empty list.")
                DispatchQueue.main.async {
                    self.subscriptions = []
                }
                return
            }

            do {
                // Decode into 'SubscriptionMapResponse'
                let decoded = try JSONDecoder().decode(SubscriptionMapResponse.self, from: data)
                
                // Then convert dictionary -> [SubscriptionItem] for local usage
                let list: [SubscriptionItem] = decoded.subscriptions.map { (name, subData) in
                    SubscriptionItem(name: name, cost: subData.cost, dueDate: subData.dueDate)
                }
                
                DispatchQueue.main.async {
                    self.subscriptions = list
                    self.checkForUpcomingSubscriptions()
                }
            } catch {
                print("Failed to decode subscription data:", error)
                DispatchQueue.main.async {
                    self.subscriptions = []
                }
            }
        }.resume()
    }

    private func deleteSubscription(subscription: SubscriptionItem) {
        let urlString = "http://localhost:8080/api/subscriptions/\(username)/\(subscription.name)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        DispatchQueue.main.async {
            self.subscriptions.removeAll { $0.name == subscription.name }
            calendarVM.deleteEventByType("subscription-\(subscription.name.lowercased())")
        }
        URLSession.shared.dataTask(with: request).resume()

        // Also remove locally
        //subscriptions.removeAll { $0.id == subscription.id }
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
        
        // Then create our 'SubscriptionMapUpload'
        let payload = SubscriptionUpload(
            username: username,
            subscriptions: dict
        )
        
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            print("Failed to encode SubscriptionMapUpload")
            return
        }

        let urlString = "http://localhost:8080/api/subscriptions"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request).resume()
        
        DispatchQueue.main.async {
            
            self.showSubscriptionSaveAlert = true
        }
    }


    private func checkForUpcomingSubscriptions() {
        print("Inside checkForUpcomingSubscriptions")
        for sub in subscriptions {
            print(" Checking Subscription: \(sub.name)")
            print("   - Cost: \(sub.cost)")
            print("   - Due Date (raw): \(sub.dueDate)")
            let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: sub.dueDate).day ?? 0
            print("Days until due: ", daysUntilDue)
            if daysUntilDue <= 3, daysUntilDue >= 0 {
                print("Sending notification?")
                sendNotification(
                    title: "📅 Subscription Due Soon!",
                    message: "\(sub.name) is due in \(daysUntilDue) days."
                )
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else {
                print("Notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("Notification Settings: \(settings.authorizationStatus.rawValue)")
        }
    }

    private func sendNotification(title: String, message: String) {
        print("Inside sendNotification")
        print("  -Title: \(title)")
        print("  -Message: \(message)")
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        // Force alerts to appear when the app is in the foreground
        content.interruptionLevel = .timeSensitive
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        // Delay by 5 seconds (demo)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification request: \(error.localizedDescription)")
            } else {
                print("Notification successfully added to queue.")
            }
        }
    }
    
    private func fetchTakeHomeMonthly() {
        guard let url = URL(string: "http://localhost:8080/api/llm/budget/last/\(username)") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            if let v = obj["monthlyNet"] as? Double {
                DispatchQueue.main.async { self.takeHomeMonthly = v }
                return
            }
            if let s = obj["monthlyNet"] as? String, let v = Double(s) {
                DispatchQueue.main.async { self.takeHomeMonthly = v }
                return
            }
        }.resume()
    }
    
    // Calander of Days of the Week
    private func rebuildWeek(for date: Date) {
        let start = Calendar.current.startOfWeek(for: date)
        weekDays = (0..<7).map { start.addingDays($0) }
    }

    private var weekHeader: some View {
        HStack {
            Button {
                selectedDay = selectedDay.addingDays(-7)
                rebuildWeek(for: selectedDay)
                loadWeeklyPeriod(for: selectedDay)
            } label: { Image(systemName: "chevron.left") }

            Spacer()

            ForEach(weekDays, id: \.self) { d in
                let isSelected = Calendar.current.isDate(d, inSameDayAs: selectedDay)
                VStack(spacing: 4) {
                    Text(d.shortWeekday())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(d.monthDay())
                        .font(.footnote).bold()
                }
                .padding(.vertical, 6).frame(width: 44)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    selectedDay = d
                    loadCostsForSelectedDay() // populate costItems for that day
                }
            }

            Spacer()

            Button {
                selectedDay = selectedDay.addingDays(+7)
                rebuildWeek(for: selectedDay)
                loadWeeklyPeriod(for: selectedDay)
            } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
    }
    
    private func loadWeeklyPeriod(for anyDate: Date) {
        // choose one: send week_start (YYYY-MM-DD of week’s start) or period key
        let weekStart = Calendar.current.startOfWeek(for: anyDate).ymd()
        let urlStr = "http://localhost:8080/api/costs/weekly/\(username)?week_start=\(weekStart)"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let period = try? JSONDecoder().decode(WeeklyPeriod.self, from: data) else {
                // no file yet? treat as empty week
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
        // Pull day map from the loaded week, fall back to empty categories
        let dayKey = selectedDay.ymd()
        let dayMap = weeklyPeriod?.days[dayKey] ?? [:]
        // If you want to preserve previous input categories too:
        let keys = Set(dayMap.keys)
            .union(Set(budgetLimits.keys))
            .subtracting(trackerExclusions)
            .sorted()
        self.costItems = keys.map { BudgetItem(category: $0, amount: String(dayMap[$0] ?? 0.0)) }
    }



}

// For Days of the week at the top
extension Calendar {
    // Sunday-based weeks; switch to .iso8601 if you prefer ISO
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        // For Sunday-start: subtract weekday-1 from date
        let weekday = component(.weekday, from: date) // 1..7 (Sun=1)
        return self.date(byAdding: .day, value: -(weekday - 1), to: date.startOfDay) ?? date.startOfDay
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func addingDays(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: self) ?? self
    }
    func ymd() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
    func shortWeekday() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: self)
    }
    func monthDay() -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: self)
    }
}


// MARK: - Data Models
//struct BudgetResponse: Codable {
//    let username: String
//    let type: String
//    let budget: [String: Double]
//}
//
//struct WeeklyMonthlyCostResponse: Codable {
//    let username: String
//    let type: String
//    let costs: [String: Double]
//}
//
//struct BudgetItem: Identifiable, Codable {
//    var id = UUID()
//    let category: String
//    var amount: String
//}

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
