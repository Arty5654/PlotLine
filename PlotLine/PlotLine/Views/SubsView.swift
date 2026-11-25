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
    @State private var subscriptionsLoaded = false
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

    /// what they pay a month now (a subscription paused for a "Can I afford it?" goal doesn't count)
    private var totalSubscriptionsCost: Double {
        subscriptions.filter { !$0.isPaused }.compactMap { Double($0.cost) }.reduce(0, +)
    }

    /// a removed subscription: offer to lower the fixed Subscriptions cost by what it cost
    @State private var removedCost: (name: String, cost: Double)?

    /// the budget's Subscriptions line (what they plan to pay); nil until it's loaded
    @State private var budgetedSubscriptions: Double?

    /// tracked subscriptions cost more than the budget plans for
    private var isOverInputtedCost: Bool {
        guard let budgeted = budgetedSubscriptions else { return false }
        return totalSubscriptionsCost > budgeted + 0.005
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.md) {
                // Header
                Text("Add reminders for recurring bills. We'll notify you the day before they're due.")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Budget Summary Card
                if inputtedSubscriptionsCost > 0 || !subscriptions.isEmpty || (budgetedSubscriptions ?? 0) > 0 {
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
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.md)
        }
        .navigationTitle("Subscriptions")
        .onAppear {
            loadDismissedPrompts()
            Task {
                await calendarVM.reloadEvents() // subscriptions are matched against these
                fetchSubscriptions()
                fetchInputtedMonthlyCosts()
                await fetchRecurringPrompts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            fetchSubscriptions()
            fetchInputtedMonthlyCosts()
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
        .alert("Subscriptions Mismatch", isPresented: $showCostWarning) {
            Button("Update Budget") {
                adjustInputtedCostToMatchTotal()
            }
            Button("Ignore", role: .cancel) {}
        } message: {
            Text("Your tracked subscriptions ($\(String(format: "%.2f", totalSubscriptionsCost))) add up to more than your budget's Subscriptions line ($\(String(format: "%.2f", budgetedSubscriptions ?? 0))). Raise it to $\(String(format: "%.2f", totalSubscriptionsCost)) a month?")
        }
        .alert("Update Your Budget", isPresented: $showAdjustCostPrompt) {
            Button("Yes, Update") {
                adjustInputtedCostToMatchTotal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sets your budget's Subscriptions line to $\(String(format: "%.2f", totalSubscriptionsCost)) a month.")
        }
        .alert("Lower Your Budget?", isPresented: Binding(get: { removedCost != nil }, set: { if !$0 { removedCost = nil } })) {
            if let removed = removedCost {
                Button("Lower by $\(String(format: "%.2f", removed.cost))") { lowerInputtedCost(by: removed.cost) }
            }
            Button("Keep It", role: .cancel) {}
        } message: {
            if let removed = removedCost {
                Text("Your budget's Subscriptions line is $\(String(format: "%.2f", budgetedSubscriptions ?? 0)). Lower it by \(removed.name)'s $\(String(format: "%.2f", removed.cost)) to $\(String(format: "%.2f", max(0, (budgetedSubscriptions ?? 0) - removed.cost)))?")
            }
        }
        .alert("Recurring Charges Detected", isPresented: $showNewRecurringAlert) {
            Button("View Suggestions", role: .none) {}
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("We detected \(newRecurringCount) potential subscription\(newRecurringCount == 1 ? "" : "s") from your transactions. Review them below to add to your tracking.")
        }
        .onChange(of: calendarVM.events.count) { _, _ in
            mergeFromCalendar()
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
                Text("In Your Budget:")
                Spacer()
                Text(budgetedSubscriptions.map { "$\(String(format: "%.2f", $0))" } ?? "–")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Spent This Month:")
                Spacer()
                Text("$\(String(format: "%.2f", inputtedSubscriptionsCost))")
                    .foregroundColor(.secondary)
            }
            Text("Charges count here when your linked card records them, or add them on Monthly Costs.")
                .font(.caption)
                .foregroundColor(.secondary)

            if isOverInputtedCost {
                HStack {
                    Text("Over budget by:")
                    Spacer()
                    Text("$\(String(format: "%.2f", totalSubscriptionsCost - (budgetedSubscriptions ?? 0)))")
                        .foregroundColor(.orange)
                        .fontWeight(.semibold)
                }

                Button("Update Budget") {
                    showAdjustCostPrompt = true
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        .plCard()
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

            Button {
                addSubscription()
            } label: {
                Label("Add Subscription", systemImage: "plus")
            }
            .buttonStyle(PrimaryButton())
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .plCard()
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
                                        .font(.footnote.weight(.semibold))
                                        .strikethrough(sub.isPaused)
                                        .foregroundColor(sub.isPaused ? PLColor.textSecondary : PLColor.textPrimary)
                                }
                                if sub.isPaused {
                                    Label("Paused for \(sub.pausedForName ?? "a goal")", systemImage: "pause.circle")
                                        .font(.footnote)
                                        .foregroundColor(PLColor.warning)
                                } else {
                                    Text("Due: \(sub.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
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
        .plCard()
    }

    // MARK: - Actions

    private func addSubscription() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let costValue = newCost.trimmingCharacters(in: .whitespacesAndNewlines)

        if !subscriptions.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            let newSub = SubscriptionItem(name: trimmed, cost: costValue, dueDate: newDueDate)
            subscriptions.append(newSub)
            saveSubscriptions()
            checkCostWarning()
            ensureCalendarEvent(for: newSub)
            scheduleMonthlyReminder(for: newSub)
            Task { await NotificationPermission.ensure(for: "subscription reminders") }
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
            let newSub = SubscriptionItem(name: prompt.name, cost: costString, dueDate: dueDate)
            subscriptions.append(newSub)
            saveSubscriptions()
            checkCostWarning()
            ensureCalendarEvent(for: newSub)
            scheduleMonthlyReminder(for: newSub)
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
        // one question: the fixed Subscriptions cost can come down by what it cost (a paused one already did)
        if !sub.isPaused, let cost = Double(sub.cost), cost > 0, (budgetedSubscriptions ?? 0) > 0 {
            removedCost = (sub.name, cost)
        }
    }

    private func checkCostWarning() {
        if isOverInputtedCost {
            showCostWarning = true
        }
    }

    // MARK: - API Calls

    private func fetchSubscriptions() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/\(username)") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { data, response, error in
            if AppBanner.reportIfFailed("load your subscriptions", data, response, error, retry: { fetchSubscriptions() }) { return }
            guard let data = data else { return }
            // the server answers {} when there are none yet
            if (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?.isEmpty == true {
                DispatchQueue.main.async {
                    self.subscriptionsLoaded = true
                    self.mergeFromCalendar()
                }
                return
            }
            guard let decoded = try? JSONDecoder().decode(SubscriptionMapResponse.self, from: data) else {
                AppBanner.report("load your subscriptions", URLError(.cannotParseResponse), retry: { fetchSubscriptions() })
                return
            }
            let list = decoded.subscriptions.map { (name, subData) in
                SubscriptionItem(name: name, cost: subData.cost ?? "", dueDate: subData.dueDate,
                                 pausedFor: subData.pausedFor, pausedForName: subData.pausedForName)
            }
            DispatchQueue.main.async {
                self.subscriptions = list
                self.subscriptionsLoaded = true
                for sub in list {
                    self.ensureCalendarEvent(for: sub)
                    self.scheduleMonthlyReminder(for: sub)
                }
                self.mergeFromCalendar()
            }
        }.resume()
    }

    /// the budget's Subscriptions line
    private func fetchBudgetedSubscriptions() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/budget/\(username)/monthly") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            struct Wrapped: Decodable { let budget: [String: Double]? }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let budget = (try? JSONDecoder().decode(Wrapped.self, from: data))?.budget else { return }
            let line = budget.first { $0.key.caseInsensitiveCompare("Subscriptions") == .orderedSame }?.value ?? 0
            DispatchQueue.main.async { self.budgetedSubscriptions = line }
        }.resume()
    }

    /// sets the budget's Subscriptions line (0 removes it)
    private func setBudgetedSubscriptions(_ amount: Double) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/budget/\(username)/line") else { return }
        let rounded = max(0, (amount * 100).rounded() / 100)
        guard let body = try? JSONSerialization.data(withJSONObject: ["line": "Subscriptions", "amount": rounded]) else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, response, error in
            if AppBanner.reportIfFailed("update your budget", data, response, error,
                                        retry: { setBudgetedSubscriptions(amount) }) { return }
            DispatchQueue.main.async {
                self.budgetedSubscriptions = rounded
                WidgetDataWriter.refreshFinancialData()
            }
        }.resume()
    }

    private func fetchInputtedMonthlyCosts() {
        fetchBudgetedSubscriptions()
        // Get current month in YYYY-MM format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/monthly/\(username)?month=\(currentMonth)") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { data, _, _ in
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
            var request = URLRequest(url: url)
            BackendConfig.addApiKey(to: &request)
            request.httpMethod = "GET"
            let (data, _) = try await URLSession.shared.data(for: request)
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
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": username,
            "snoozeKey": snoozeKey,
            "months": 6
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            AppBanner.reportIfFailed("snooze the reminder", data, response, nil)
        } catch {
            AppBanner.report("snooze the reminder", error)
        }
    }

    /// the budget's Subscriptions line becomes what's tracked here
    private func adjustInputtedCostToMatchTotal() {
        setBudgetedSubscriptions(totalSubscriptionsCost)
    }

    /// the budget's Subscriptions line, lowered by a removed subscription's cost
    private func lowerInputtedCost(by cost: Double) {
        setBudgetedSubscriptions((budgetedSubscriptions ?? 0) - cost)
    }

    private func mergeFromCalendar() {
        let calendarSubs = calendarVM.events.filter {
            $0.eventType.lowercased().hasPrefix("subscription")
        }

        var merged = subscriptions
        for ev in calendarSubs {
            if !merged.contains(where: { $0.name.caseInsensitiveCompare(ev.title) == .orderedSame }) {
                // Extract cost from description (format: "Subscription reminder ($10.99)")
                var cost = ""
                if let range = ev.description.range(of: #"\$(\d+\.?\d*)"#, options: .regularExpression) {
                    cost = String(ev.description[range].dropFirst()) // drop the $
                }
                merged.append(SubscriptionItem(name: ev.title, cost: cost, dueDate: ev.startDate))
            }
        }
        if merged.count != subscriptions.count {
            subscriptions = merged
            saveSubscriptions()
        }
    }

    private func saveSubscriptions() {
        // saving replaces the whole list, so it waits until the real one has loaded
        guard subscriptionsLoaded else {
            AppBanner.shared.show("Your subscriptions didn't load, so saving now could erase them.", retry: { fetchSubscriptions() })
            return
        }
        var dict: [String: SubscriptionData] = [:]
        for sub in subscriptions {
            dict[sub.name] = SubscriptionData(name: sub.name, cost: sub.cost, dueDate: sub.dueDate,
                                              pausedFor: sub.pausedFor, pausedForName: sub.pausedForName)
            ensureCalendarEvent(for: sub)
            scheduleMonthlyReminder(for: sub)
        }

        let payload = SubscriptionUpload(username: username, subscriptions: dict)
        guard let body = try? JSONEncoder().encode(payload),
              let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions") else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { data, response, error in
            if AppBanner.reportIfFailed("save your subscriptions", data, response, error, retry: { saveSubscriptions() }) { return }
            // one alert at a time: the mismatch question (if it's up) already says it was added
            DispatchQueue.main.async { if !self.showCostWarning && self.removedCost == nil { self.showSavedAlert = true } }
        }.resume()
    }

    private func ensureCalendarEvent(for sub: SubscriptionItem) {
        // Check against freshly fetched events from backend instead of stale local state
        Task {
            do {
                let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
                let freshEvents = try await CalendarAPI.getEvents(username: username)
                let exists = freshEvents.contains {
                    $0.eventType.lowercased().hasPrefix("subscription") &&
                    $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
                }
                if !exists {
                    let costInfo = Double(sub.cost).map { " ($\(String(format: "%.2f", $0)))" } ?? ""
                    await MainActor.run {
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
            } catch {
                // If fetch fails, create the event anyway to avoid silent failure
                let costInfo = Double(sub.cost).map { " ($\(String(format: "%.2f", $0)))" } ?? ""
                await MainActor.run {
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
        }
    }

    private func removeCalendarEvent(for sub: SubscriptionItem) {
        Task {
            do {
                let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
                let freshEvents = try await CalendarAPI.getEvents(username: username)
                let matches = freshEvents.filter {
                    $0.eventType.lowercased().hasPrefix("subscription") &&
                    $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
                }
                await MainActor.run {
                    for ev in matches {
                        calendarVM.deleteEvent(ev.seriesKey)
                    }
                }
            } catch {
                // Fallback to local events if fetch fails
                let matches = calendarVM.events.filter {
                    $0.eventType.lowercased().hasPrefix("subscription") &&
                    $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
                }
                for ev in matches {
                    calendarVM.deleteEvent(ev.seriesKey)
                }
            }
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
