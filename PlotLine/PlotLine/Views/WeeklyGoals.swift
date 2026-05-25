//
//  WeeklyGoals.swift
//  PlotLine
//

import SwiftUI
import UserNotifications

// MARK: - Design tokens

private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.06)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let success       = Color.green
    static let danger        = Color.red
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

// MARK: - Helpers

private func priorityColor(_ priority: Priority) -> Color {
    switch priority {
    case .high:   return .red
    case .medium: return .orange
    case .low:    return .green
    }
}

// MARK: - View

struct WeeklyGoalsView: View {
    @Binding var tasks: [TaskItem]
    @Binding var newTask: String
    @Binding var newTaskPriority: Priority
    @Binding var newTaskDueDate: Date
    @Binding var selectedPriorityFilter: Priority?
    @Binding var notificationsEnabled: Bool
    @Binding var notificationType: String
    @Binding var notificationTime: Date
    let username: String
    var calendarVM: CalendarViewModel
    let fetchGoals: () -> Void

    @Environment(\.colorScheme) var colorScheme

    @State private var isFinancialGoalDeleted = false
    @State private var showingGroceryAlert = false
    @State private var showingHealthAlert = false
    @State private var showHealthRemindersView = false
    @State private var showingGroceryActionAlert = false
    @State private var groceryAlertTitle = ""
    @State private var groceryAlertMessage = ""
    @State private var taskNameForGrocList = ""
    @State private var isGeneratingGroceryList = false

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    private let groceryKeywords = [
        "eat", "healthy", "vegetarian", "vegan", "protein", "meal", "diet",
        "nutrition", "food", "cook", "grocery", "ingredients", "recipe",
        "shopping", "organic", "produce", "fruit", "vegetable", "meat"
    ]
    private let healthKeywords = [
        "mood", "water", "sleep", "exercise", "meditation", "mental health",
        "workout", "wellness", "fitness", "hydrate", "rest", "mindfulness",
        "anxiety", "stress", "relaxation", "therapy", "breathing"
    ]

    private var filteredTasks: [TaskItem] {
        tasks
            .filter { selectedPriorityFilter == nil || $0.priority == selectedPriorityFilter }
            .sorted { $0.priority.sortIndex < $1.priority.sortIndex }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Top config + create section ──
            VStack(spacing: PLSpacing.md) {

                // Notifications card
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Enable Notifications", systemImage: "bell.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(adaptiveTextColor)

                    if notificationsEnabled {
                        Picker("Notification Type", selection: $notificationType) {
                            Text("Due Date").tag("dueDate")
                            Text("Priority-based").tag("priority")
                        }
                        .pickerStyle(.segmented)

                        if notificationType == "custom" {
                            DatePicker("Select Time", selection: $notificationTime, displayedComponents: .hourAndMinute)
                                .tint(adaptiveTextColor)
                        }
                    }
                }
                .plCard()

                // Priority filter
                VStack(alignment: .leading, spacing: PLSpacing.xs) {
                    Text("Filter by Priority")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                    Picker("Priority Filter", selection: $selectedPriorityFilter) {
                        Text("All").tag(nil as Priority?)
                        ForEach(Priority.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level as Priority?)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .plCard()

                // Create task card
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Label("New Task", systemImage: "plus.circle")
                        .font(.headline)
                        .foregroundColor(adaptiveTextColor)

                    TextField("Enter task name", text: $newTask)
                        .textFieldStyle(.roundedBorder)
                        .tint(adaptiveTextColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Priority")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                        Picker("Priority", selection: $newTaskPriority) {
                            ForEach(Priority.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    DatePicker("Due Date", selection: $newTaskDueDate, displayedComponents: .date)
                        .tint(adaptiveTextColor)

                    HStack(spacing: PLSpacing.sm) {
                        Button(action: addFinancialGoal) {
                            Label("Financial", systemImage: "dollarsign.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(PLColor.success)
                                .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                        }
                        Button(action: addTask) {
                            Label("Add Task", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                        }
                    }
                }
                .plCard()
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.top, PLSpacing.sm)
            .padding(.bottom, PLSpacing.xs)

            Divider().padding(.top, PLSpacing.xs)

            // ── Task list ──
            List {
                ForEach(filteredTasks, id: \.id) { task in
                    if task.isEditing ?? false {
                        // Edit row
                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            TextField("Edit task", text: Binding(
                                get: { task.name },
                                set: { newName in
                                    if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                                        tasks[i].name = newName
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .tint(adaptiveTextColor)
                            .onSubmit { updateTask(task: task) }

                            Picker("Priority", selection: Binding(
                                get: { task.priority },
                                set: { newPriority in
                                    if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                                        tasks[i].priority = newPriority
                                    }
                                }
                            )) {
                                ForEach(Priority.allCases, id: \.self) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)

                            Button("Save") { updateTask(task: task) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(adaptiveTextColor)
                        }
                        .padding(.vertical, 6)
                    } else {
                        // Normal row
                        HStack(spacing: PLSpacing.md) {
                            // Priority indicator
                            if !task.isFinancialGoal {
                                Circle()
                                    .fill(priorityColor(task.priority))
                                    .frame(width: 10, height: 10)
                            } else {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundColor(PLColor.success)
                                    .font(.subheadline)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.name)
                                    .font(.headline)
                                    .strikethrough(task.isCompleted)
                                    .foregroundColor(task.isCompleted ? PLColor.textSecondary : PLColor.textPrimary)

                                if task.isFinancialGoal, let progress = task.progress {
                                    ProgressView(value: progress)
                                        .tint(PLColor.success)
                                    Text(String(format: "%.0f%% of budget used", progress * 100))
                                        .font(.caption)
                                        .foregroundColor(PLColor.textSecondary)
                                    if let budget = task.totalBudget, let costs = task.totalCosts {
                                        HStack(spacing: PLSpacing.sm) {
                                            Text(String(format: "Budget: $%.2f", budget))
                                            Text(String(format: "Spent: $%.2f", costs))
                                        }
                                        .font(.caption2)
                                        .foregroundColor(PLColor.textSecondary)
                                    }
                                } else {
                                    HStack(spacing: PLSpacing.sm) {
                                        Text(task.priority.rawValue)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(priorityColor(task.priority).opacity(0.15))
                                            .foregroundColor(priorityColor(task.priority))
                                            .clipShape(Capsule())
                                        if let dueDate = task.dueDate {
                                            Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundColor(PLColor.textSecondary)
                                        }
                                    }
                                }
                            }

                            Spacer()

                            Button { toggleTaskCompletion(task: task) } label: {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.isCompleted ? PLColor.success : PLColor.textSecondary)
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                                    tasks[i].isEditing?.toggle()
                                }
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTaskById(task.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete(perform: deleteTask)
            }
            .listStyle(.plain)

            // ── Reset button ──
            Button(action: resetGoals) {
                Text("Reset Weekly Goals")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PLColor.danger)
                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.sm)
        }
        .onAppear {
            fetchGoals()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.tasks.first(where: { $0.isFinancialGoal }) == nil {
                    let placeholder = TaskItem(
                        id: Int.random(in: 1000...9999),
                        name: "Save for Weekly Expenses",
                        isCompleted: false,
                        priority: .medium,
                        isEditing: false,
                        dueDate: nil,
                        notificationsEnabled: false,
                        notificationType: nil,
                        notificationTime: nil,
                        isFinancialGoal: true,
                        progress: 0.0
                    )
                    self.tasks.append(placeholder)
                }
                self.updateFinancialGoalProgress()
            }

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error { print("🔴 Notification error: \(error.localizedDescription)") }
            }
        }
        .alert("Create a Grocery List?", isPresented: $showingGroceryAlert) {
            Button("Cancel") { }
            Button("Create") { createGroceryListFromGoal() }
        } message: {
            Text("We noticed your goal contains food-related keywords. Would you like to create a grocery list of healthy foods?")
        }
        .alert("Set Up Health Reminders?", isPresented: $showingHealthAlert) {
            Button("Cancel") { }
            Button("Create") { showHealthRemindersView = true }
        } message: {
            Text("We noticed your goal contains health-related keywords. Would you like to set up recurring reminders?")
        }
        .alert(groceryAlertTitle, isPresented: $showingGroceryActionAlert) {
            Button("OK") { }
        } message: {
            Text(groceryAlertMessage)
        }
        .overlay {
            if isGeneratingGroceryList {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: PLSpacing.md) {
                        ProgressView().scaleEffect(1.5)
                        Text("Creating your grocery list…")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                    }
                    .padding(PLSpacing.lg)
                    .background(Color(.systemBackground).opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    .shadow(radius: 12)
                }
            }
        }
    }

    // MARK: - Logic (unchanged)

    private func deleteTaskById(_ id: Int) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            if tasks[index].isFinancialGoal { self.isFinancialGoalDeleted = true }

            guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/\(id)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            BackendConfig.addApiKey(to: &request)
            URLSession.shared.dataTask(with: request) { _, _, _ in
                DispatchQueue.main.async { tasks.remove(at: index) }
            }.resume()
        }
    }

    private func addTask() {
        guard !newTask.isEmpty else { return }
        let taskName = newTask
        let (hasGrocery, hasHealth) = detectKeywords(in: newTask)
        if hasGrocery { self.taskNameForGrocList = taskName; showingGroceryAlert = true }
        else if hasHealth { showingHealthAlert = true }

        let newTaskItem = TaskItem(
            id: Int.random(in: 1000...9999),
            name: newTask,
            isCompleted: false,
            priority: newTaskPriority,
            dueDate: newTaskDueDate,
            notificationsEnabled: notificationsEnabled,
            notificationType: notificationType,
            notificationTime: notificationTime
        )

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)

        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        encoder.dateEncodingStrategy = .formatted(formatter)

        guard let jsonData = try? encoder.encode(newTaskItem) else { return }
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error { print("❌ Network error: \(error.localizedDescription)"); return }
            DispatchQueue.main.async {
                calendarVM.createEvent(
                    title: "\(newTask)",
                    description: "Weekly Goal - Priority: \(newTaskPriority)",
                    startDate: newTaskDueDate,
                    endDate: newTaskDueDate,
                    eventType: "weekly-goal-\(newTask.lowercased())",
                    recurrence: "none",
                    invitedFriends: []
                )
                self.tasks.append(newTaskItem)
                self.newTask = ""
                self.newTaskPriority = .medium
                scheduleNotification(for: newTaskItem)
            }
        }.resume()
    }

    private func toggleTaskCompletion(task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted.toggle()

        // Write optimistically before the network call so the widget updates even if the
        // user closes the app before the PUT returns.
        WidgetDataWriter.writeGoals(tasks)
        WidgetDataWriter.reloadWidgets()

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/\(task.id)/completion") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        let body = ["isCompleted": tasks[index].isCompleted]
        guard let jsonData = try? JSONEncoder().encode(body) else { return }
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func updateTask(task: TaskItem) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/\(task.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        guard let jsonData = try? JSONEncoder().encode(task) else { return }
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[index].isEditing = false
                }
            }
        }.resume()
    }

    private func deleteTask(at offsets: IndexSet) {
        for index in offsets {
            let task = filteredTasks[index]
            guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/\(task.id)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            BackendConfig.addApiKey(to: &request)
            URLSession.shared.dataTask(with: request) { _, _, _ in
                DispatchQueue.main.async {
                    calendarVM.deleteEventByType("weekly-goal-\(task.name.lowercased())")
                    self.tasks.removeAll { $0.id == task.id }
                }
            }.resume()
        }
    }

    private func resetGoals() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/reset") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async { self.tasks.removeAll() }
        }.resume()
    }

    func scheduleNotification(for task: TaskItem) {
        guard task.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(task.name)"
        content.body = "Your goal \"\(task.name)\" is due soon!"
        content.sound = .default

        var triggerDate: Date?
        let now = Date()
        let calendar = Calendar.current

        switch task.notificationType {
        case "dueDate":
            if let dueDate = task.dueDate {
                if calendar.isDate(dueDate, inSameDayAs: now) {
                    triggerDate = now.addingTimeInterval(5)
                } else {
                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                    dateComponents.hour = 9; dateComponents.minute = 0
                    triggerDate = calendar.date(from: dateComponents)
                }
            }
        case "priority":
            switch task.priority {
            case .high:   triggerDate = now.addingTimeInterval(5)
            case .medium: triggerDate = now.addingTimeInterval(10)
            case .low:    triggerDate = now.addingTimeInterval(60 * 60)
            }
        case "custom":
            triggerDate = task.notificationTime
        default:
            break
        }

        guard let date = triggerDate else { return }
        let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let notifRequest = UNNotificationRequest(identifier: "\(task.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(notifRequest) { error in
            if let error = error { print("🔴 Error scheduling notification: \(error.localizedDescription)") }
        }
    }

    private func detectKeywords(in text: String) -> (Bool, Bool) {
        let lower = text.lowercased()
        return (
            groceryKeywords.contains { lower.contains($0) },
            healthKeywords.contains  { lower.contains($0) }
        )
    }

    private func addFinancialGoal() {
        fetchFinancialSummary { summary in
            guard let summary = summary else { return }

            let newTaskItem = TaskItem(
                id: Int.random(in: 1000...9999),
                name: "Save for Weekly Expenses",
                isCompleted: false,
                priority: .medium,
                dueDate: nil,
                notificationsEnabled: false,
                notificationType: nil,
                notificationTime: nil,
                isFinancialGoal: true,
                progress: summary.totalBudget > 0 ? min(summary.totalCosts / summary.totalBudget, 1.0) : 0.0,
                totalBudget: summary.totalBudget,
                totalCosts: summary.totalCosts
            )

            guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            BackendConfig.addApiKey(to: &request)

            let encoder = JSONEncoder()
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            encoder.dateEncodingStrategy = .formatted(formatter)
            guard let jsonData = try? encoder.encode(newTaskItem) else { return }
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { _, _, _ in
                DispatchQueue.main.async { self.tasks.append(newTaskItem) }
            }.resume()
        }
    }

    private func fetchFinancialSummary(completion: @escaping (FinancialSummary?) -> Void) {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/financial-data") else {
            completion(nil); return
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if error != nil { completion(nil); return }
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(FinancialSummary.self, from: data) else {
                completion(nil); return
            }
            completion(decoded)
        }.resume()
    }

    private func updateFinancialGoalProgress() {
        fetchFinancialSummary { summary in
            guard let summary = summary else { return }
            WidgetDataWriter.writeFinancial(period: "weekly", totalSpent: summary.totalCosts, totalBudget: summary.totalBudget)
            WidgetDataWriter.reloadWidgets()
            DispatchQueue.main.async {
                if self.isFinancialGoalDeleted { return }
                self.tasks.removeAll { $0.isFinancialGoal || $0.name == "Save for Weekly Expenses" }
                let updated = TaskItem(
                    id: Int.random(in: 1000...9999),
                    name: "Save for Weekly Expenses",
                    isCompleted: false,
                    priority: .medium,
                    isEditing: false,
                    dueDate: nil,
                    notificationsEnabled: false,
                    notificationType: nil,
                    notificationTime: nil,
                    isFinancialGoal: true,
                    progress: summary.totalBudget > 0 ? min(summary.totalCosts / summary.totalBudget, 1.0) : 0.0,
                    totalBudget: summary.totalBudget,
                    totalCosts: summary.totalCosts
                )
                self.tasks.append(updated)
            }
        }
    }

    private func createGroceryListFromGoal() {
        isGeneratingGroceryList = true
        Task {
            do {
                let groceryList = try await GroceryListAPI.generateGroceryListFromGoal(goalTitle: taskNameForGrocList)
                DispatchQueue.main.async {
                    isGeneratingGroceryList = false
                    showSuccess("Grocery List Created", "Your grocery list \(groceryList) has been created.")
                }
            } catch {
                DispatchQueue.main.async {
                    isGeneratingGroceryList = false
                    showError("Creation Failed", "Could not create grocery list: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showSuccess(_ title: String, _ message: String) {
        groceryAlertTitle = title; groceryAlertMessage = message; showingGroceryActionAlert = true
    }
    private func showError(_ title: String, _ message: String) {
        groceryAlertTitle = title; groceryAlertMessage = message; showingGroceryActionAlert = true
    }
}
