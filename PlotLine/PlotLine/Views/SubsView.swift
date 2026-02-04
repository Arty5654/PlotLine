//
//  SubsView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 1/10/26.
//

import SwiftUI
import UserNotifications

struct SubsView: View {
    @EnvironmentObject var calendarVM: CalendarViewModel

    @State private var subscriptions: [SubscriptionItem] = []
    @State private var newName: String = ""
    @State private var newCost: String = ""
    @State private var newDueDate: Date = Date()
    @State private var showSavedAlert = false

    // Comparison against inputted monthly costs (from WeeklyMonthlyCostView)
    @State private var inputtedSubscriptionsCost: Double = 0
    @State private var showCostWarning = false
    @State private var showAdjustCostPrompt = false
    @State private var fullMonthlyCosts: [String: Double] = [:]

    // Plaid recurring charge detection
    @State private var recurringPrompts: [RecurringChargePromptModel] = []
    @State private var showNewRecurringAlert = false
    @State private var newRecurringCount = 0
    @State private var dismissedPromptKeys: Set<String> = []

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    private var totalSubscriptionsCost: Double {
        subscriptions.compactMap { Double($0.cost) }.reduce(0, +)
    }

    private var isOverInputtedCost: Bool {
        inputtedSubscriptionsCost > 0 && totalSubscriptionsCost > inputtedSubscriptionsCost
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text("Subscriptions")
                        .font(.headline)
                    Text("Add reminders for recurring bills. We'll notify you the day before they're due.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Budget Summary Card
                if inputtedSubscriptionsCost > 0 || !subscriptions.isEmpty {
                    budgetSummaryCard
                }

                // Plaid Detected Recurring Charges
                if !visiblePrompts.isEmpty {
                    plaidSuggestionsCard
                }

                // Add Subscription Form
                addSubscriptionForm

                // Your Subscriptions List
                subscriptionsListCard
            }
            .padding()
        }
        .navigationTitle("Subscriptions")
        .onAppear {
            requestNotificationPermission()
            loadDismissedPrompts()
            Task {
                await calendarVM.fetchEvents()
                fetchSubscriptions()
                fetchInputtedMonthlyCosts()
                await fetchRecurringPrompts()
            }
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
        .alert("Subscriptions Mismatch", isPresented: $showCostWarning) {
            Button("Update Monthly Costs", role: .none) {
                showAdjustCostPrompt = true
            }
            Button("Ignore", role: .cancel) {}
        } message: {
            Text("Your tracked subscriptions ($\(String(format: "%.2f", totalSubscriptionsCost))) exceed what you entered for monthly Subscriptions ($\(String(format: "%.2f", inputtedSubscriptionsCost))). Would you like to update your monthly costs?")
        }
        .alert("Update Monthly Costs", isPresented: $showAdjustCostPrompt) {
            Button("Yes, Update") {
                adjustInputtedCostToMatchTotal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will update your monthly Subscriptions cost to $\(String(format: "%.2f", totalSubscriptionsCost)).")
        }
        .alert("Recurring Charges Detected", isPresented: $showNewRecurringAlert) {
            Button("View Suggestions", role: .none) {}
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("We detected \(newRecurringCount) potential subscription\(newRecurringCount == 1 ? "" : "s") from your transactions. Review them below to add to your tracking.")
        }
    }

    // MARK: - Budget Summary Card

    private var budgetSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Monthly Summary")
                    .font(.headline)
                Spacer()
                if isOverInputtedCost {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            HStack {
                Text("Tracked Subscriptions:")
                Spacer()
                Text("$\(String(format: "%.2f", totalSubscriptionsCost))")
                    .fontWeight(.semibold)
                    .foregroundColor(isOverInputtedCost ? .orange : .primary)
            }

            HStack {
                Text("Inputted Monthly Cost:")
                Spacer()
                Text("$\(String(format: "%.2f", inputtedSubscriptionsCost))")
                    .foregroundColor(.secondary)
            }

            if isOverInputtedCost {
                HStack {
                    Text("Exceeds by:")
                    Spacer()
                    Text("$\(String(format: "%.2f", totalSubscriptionsCost - inputtedSubscriptionsCost))")
                        .foregroundColor(.orange)
                        .fontWeight(.semibold)
                }

                Button("Update Monthly Costs") {
                    showAdjustCostPrompt = true
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Plaid Suggestions Card

    private var visiblePrompts: [RecurringChargePromptModel] {
        recurringPrompts.filter { prompt in
            !dismissedPromptKeys.contains(prompt.snoozeKey) &&
            !subscriptions.contains(where: { $0.name.caseInsensitiveCompare(prompt.name) == .orderedSame })
        }
    }

    private var plaidSuggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("Detected Subscriptions")
                    .font(.headline)
                Spacer()
                Text("\(visiblePrompts.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }

            Text("We found these recurring charges in your transactions:")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(visiblePrompts) { prompt in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 8) {
                            Text("~$\(String(format: "%.2f", prompt.averageAmount))/mo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Day \(prompt.dayOfMonth)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(prompt.consecutiveMonths) months")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    Spacer()

                    Button {
                        dismissPrompt(prompt)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button("Add") {
                        addFromPrompt(prompt)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 6)

                if prompt.id != visiblePrompts.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Add Subscription Form

    private var addSubscriptionForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Subscription")
                .font(.headline)

            TextField("Company name", text: $newName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("$")
                    .foregroundColor(.secondary)
                TextField("Monthly cost", text: $newCost)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
            }

            DatePicker("Due date", selection: $newDueDate, displayedComponents: .date)

            Button("Add") {
                addSubscription()
            }
            .buttonStyle(.borderedProminent)
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Subscriptions List

    private var subscriptionsListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Subscriptions")
                .font(.headline)

            if subscriptions.isEmpty {
                Text("No subscriptions yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(subscriptions) { sub in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sub.name)
                                .font(.headline)
                            HStack(spacing: 8) {
                                if let cost = Double(sub.cost), cost > 0 {
                                    Text("$\(String(format: "%.2f", cost))/mo")
                                        .font(.footnote)
                                        .foregroundColor(.blue)
                                }
                                Text("Due: \(sub.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteSubscription(sub)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .padding(.vertical, 6)

                    if sub.id != subscriptions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func addSubscription() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let costValue = newCost.trimmingCharacters(in: .whitespacesAndNewlines)

        if !subscriptions.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            subscriptions.append(SubscriptionItem(name: trimmed, cost: costValue, dueDate: newDueDate))
            saveSubscriptions()
            checkCostWarning()
        }
        newName = ""
        newCost = ""
    }

    private func addFromPrompt(_ prompt: RecurringChargePromptModel) {
        // Calculate due date based on day of month
        var components = Calendar.current.dateComponents([.year, .month], from: Date())
        components.day = prompt.dayOfMonth
        let dueDate = Calendar.current.date(from: components) ?? Date()

        let costString = String(format: "%.2f", prompt.averageAmount)

        if !subscriptions.contains(where: { $0.name.caseInsensitiveCompare(prompt.name) == .orderedSame }) {
            subscriptions.append(SubscriptionItem(name: prompt.name, cost: costString, dueDate: dueDate))
            saveSubscriptions()
            checkCostWarning()
        }
    }

    private func dismissPrompt(_ prompt: RecurringChargePromptModel) {
        dismissedPromptKeys.insert(prompt.snoozeKey)
        saveDismissedPrompts()

        // Also snooze on backend
        Task {
            await snoozePromptOnBackend(prompt.snoozeKey)
        }
    }

    private func deleteSubscription(_ sub: SubscriptionItem) {
        subscriptions.removeAll { $0.name.caseInsensitiveCompare(sub.name) == .orderedSame }
        removeCalendarEvent(for: sub)
        removeNotification(for: sub)
        saveSubscriptions()
    }

    private func checkCostWarning() {
        if isOverInputtedCost {
            showCostWarning = true
        }
    }

    // MARK: - API Calls

    private func fetchSubscriptions() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/\(username)") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, !data.isEmpty,
                  let decoded = try? JSONDecoder().decode(SubscriptionMapResponse.self, from: data) else {
                return
            }
            let list = decoded.subscriptions.map { (name, subData) in
                SubscriptionItem(name: name, cost: subData.cost, dueDate: subData.dueDate)
            }
            DispatchQueue.main.async {
                self.subscriptions = list
                for sub in list {
                    self.ensureCalendarEvent(for: sub)
                    self.scheduleMonthlyReminder(for: sub)
                }
                self.mergeFromCalendar()
            }
        }.resume()
    }

    private func fetchInputtedMonthlyCosts() {
        // Get current month in YYYY-MM format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/monthly/\(username)?month=\(currentMonth)") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(MonthlyCostsResponse.self, from: data) else {
                // If no costs exist yet, set to 0
                DispatchQueue.main.async {
                    self.fullMonthlyCosts = [:]
                    self.inputtedSubscriptionsCost = 0
                }
                return
            }
            DispatchQueue.main.async {
                self.fullMonthlyCosts = decoded.totals
                self.inputtedSubscriptionsCost = decoded.totals["Subscriptions"] ?? 0
            }
        }.resume()
    }

    private func fetchRecurringPrompts() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/recurring/analyze/\(username)?months=6&remindAfterMonths=2") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(RecurringPromptsResponse.self, from: data)

            await MainActor.run {
                let previousCount = self.visiblePrompts.count
                self.recurringPrompts = decoded.prompts

                let newVisibleCount = self.visiblePrompts.count
                if newVisibleCount > previousCount && previousCount == 0 && newVisibleCount > 0 {
                    self.newRecurringCount = newVisibleCount
                    self.showNewRecurringAlert = true
                }
            }
        } catch {
            print("Failed to fetch recurring prompts: \(error)")
        }
    }

    private func snoozePromptOnBackend(_ snoozeKey: String) async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/recurring/snooze") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": username,
            "snoozeKey": snoozeKey,
            "months": 6
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        _ = try? await URLSession.shared.data(for: request)
    }

    private func adjustInputtedCostToMatchTotal() {
        // Update the Subscriptions cost in the user's monthly costs via merge-dated endpoint
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/merge-dated") else { return }

        // Only update the Subscriptions field - the merge will add or update it
        let payload: [String: Any] = [
            "username": username,
            "type": "monthly",
            "date": today,
            "costs": ["Subscriptions": totalSubscriptionsCost]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.inputtedSubscriptionsCost = self.totalSubscriptionsCost
                self.fullMonthlyCosts["Subscriptions"] = self.totalSubscriptionsCost
            }
        }.resume()
    }

    private func mergeFromCalendar() {
        let calendarSubs = calendarVM.events.filter {
            $0.eventType.lowercased().hasPrefix("subscription")
        }

        var merged = subscriptions
        for ev in calendarSubs {
            if !merged.contains(where: { $0.name.caseInsensitiveCompare(ev.title) == .orderedSame }) {
                merged.append(SubscriptionItem(name: ev.title, cost: "", dueDate: ev.startDate))
            }
        }
        if merged.count != subscriptions.count {
            subscriptions = merged
            saveSubscriptions()
        }
    }

    private func saveSubscriptions() {
        var dict: [String: SubscriptionData] = [:]
        for sub in subscriptions {
            dict[sub.name] = SubscriptionData(name: sub.name, cost: sub.cost, dueDate: sub.dueDate)
            ensureCalendarEvent(for: sub)
            scheduleMonthlyReminder(for: sub)
        }

        let payload = SubscriptionUpload(username: username, subscriptions: dict)
        guard let body = try? JSONEncoder().encode(payload),
              let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { self.showSavedAlert = true }
        }.resume()
    }

    private func ensureCalendarEvent(for sub: SubscriptionItem) {
        let exists = calendarVM.events.contains {
            $0.eventType.lowercased().hasPrefix("subscription") &&
            $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
        }
        if !exists {
            let costInfo = Double(sub.cost).map { " ($\(String(format: "%.2f", $0)))" } ?? ""
            calendarVM.createEvent(
                title: sub.name,
                description: "Subscription reminder\(costInfo)",
                startDate: sub.dueDate,
                endDate: sub.dueDate,
                eventType: "subscription",
                recurrence: "monthly",
                invitedFriends: []
            )
        }
    }

    private func removeCalendarEvent(for sub: SubscriptionItem) {
        let matches = calendarVM.events.filter {
            $0.eventType.lowercased().hasPrefix("subscription") &&
            $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
        }
        for ev in matches {
            calendarVM.deleteEvent(ev.id)
        }
    }

    private func scheduleMonthlyReminder(for sub: SubscriptionItem) {
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

        let costInfo = Double(sub.cost).map { " ($\(String(format: "%.2f", $0)))" } ?? ""
        content.body = day == 1 ? "\(sub.name)\(costInfo) is due today." : "\(sub.name)\(costInfo) is due tomorrow."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    private func removeNotification(for sub: SubscriptionItem) {
        let id = "subscription-reminder-\(sub.name.lowercased())"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - Local Storage for Dismissed Prompts

    private func loadDismissedPrompts() {
        if let data = UserDefaults.standard.data(forKey: "dismissedRecurringPrompts_\(username)"),
           let keys = try? JSONDecoder().decode(Set<String>.self, from: data) {
            dismissedPromptKeys = keys
        }
    }

    private func saveDismissedPrompts() {
        if let data = try? JSONEncoder().encode(dismissedPromptKeys) {
            UserDefaults.standard.set(data, forKey: "dismissedRecurringPrompts_\(username)")
        }
    }
}

// MARK: - Supporting Models

// Response from /api/costs/monthly/{username}?month={YYYY-MM}
private struct MonthlyCostsResponse: Codable {
    let periodKey: String?
    let start: String?
    let end: String?
    let days: [String: [String: Double]]?
    let totals: [String: Double]
}

private struct RecurringPromptsResponse: Codable {
    let prompts: [RecurringChargePromptModel]
    let remindAfterMonths: Int?
}

#Preview {
    SubsView()
        .environmentObject(CalendarViewModel())
}
