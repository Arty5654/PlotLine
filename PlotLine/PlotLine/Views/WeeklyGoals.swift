//
//  WeeklyGoals.swift
//  PlotLine
//
//  Weekly goals: the list fills the page; "+" (top right) opens the add sheet and the filter
//  button narrows by priority. Tap a goal to edit it (name, priority, due date, reminders),
//  swipe to share or delete.
//

import SwiftUI

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
    /// for "Step of …" on weekly goals made from a long-term step, and keeping those steps in step
    @Binding var longTermGoals: [LongTermGoal]
    @Binding var selectedPriorityFilter: Priority?
    let username: String
    var calendarVM: CalendarViewModel
    @ObservedObject private var router = GoalsRouter.shared

    @Environment(\.colorScheme) var colorScheme

    // The savings goal ("Save for Weekly Expenses") is built on the phone from the budget and is
    // never saved on the server. Deleting it hides it for this account; "+" › Show Savings Goal brings it back.
    @State private var savingsSummary: FinancialSummary?
    @State private var isSavingsGoalHidden = false
    private var savingsGoalHiddenKey: String { "savingsGoalHidden.\(username.lowercased())" }

    private enum Editor: Identifiable {
        case new
        case edit(TaskItem)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let task): return "edit-\(task.id)"
            }
        }
    }
    @State private var editor: Editor?
    @State private var sharing: TaskItem?
    @State private var confirmReset = false

    @State private var showingGroceryAlert = false
    @State private var showingGroceryActionAlert = false
    @State private var groceryAlertTitle = ""
    @State private var groceryAlertMessage = ""
    @State private var taskNameForGrocList = ""
    @State private var isGeneratingGroceryList = false

    private let groceryKeywords = [
        "eat", "healthy", "vegetarian", "vegan", "protein", "meal", "diet",
        "nutrition", "food", "cook", "grocery", "ingredients", "recipe",
        "shopping", "organic", "produce", "fruit", "vegetable", "meat"
    ]

    private var filteredTasks: [TaskItem] {
        tasks
            .filter { !$0.isFinancialGoal } // older versions saved copies of the savings goal on the server
            .filter { selectedPriorityFilter == nil || $0.priority == selectedPriorityFilter }
            .sorted { $0.priority.sortIndex < $1.priority.sortIndex }
    }

    private var showsSavingsGoal: Bool { !isSavingsGoalHidden && selectedPriorityFilter == nil }

    var body: some View {
        List {
            if showsSavingsGoal {
                Section { savingsRow }
                    .listRowBackground(PLColor.surface)
            }

            Section {
                if filteredTasks.isEmpty {
                    emptyRow
                } else {
                    ForEach(filteredTasks, id: \.id) { task in
                        goalRow(task)
                    }
                }
            } header: {
                if selectedPriorityFilter != nil {
                    Text("\(selectedPriorityFilter!.rawValue) priority")
                }
            }
            .listRowBackground(PLColor.surface)

            if !filteredTasks.isEmpty {
                Section {
                    Button("Reset Weekly Goals", role: .destructive) { confirmReset = true }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(PLColor.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterMenu
                addButton
            }
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .new:
                WeeklyGoalEditor(existing: nil) { await addGoal($0) }
            case .edit(let task):
                WeeklyGoalEditor(existing: task) { await updateGoal($0, previous: task) }
            }
        }
        .sheet(item: $sharing) { task in
            ShareGoalSheet(goal: .weekly(task), username: username)
        }
        .confirmationDialog("Delete all your weekly goals?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete All", role: .destructive, action: resetGoals)
        }
        .onAppear {
            isSavingsGoalHidden = UserDefaults.standard.bool(forKey: savingsGoalHiddenKey)
            loadSavingsSummary()
            openRequestedGoal()
        }
        // a tapped reminder: open that goal once it's loaded
        .onChange(of: router.request) { _, _ in openRequestedGoal() }
        .onChange(of: tasks.map(\.id)) { _, _ in openRequestedGoal() }
        .alert("Create a Grocery List?", isPresented: $showingGroceryAlert) {
            Button("Cancel") { }
            Button("Create") { createGroceryListFromGoal() }
        } message: {
            Text("We noticed your goal contains food-related keywords. Would you like to create a grocery list of healthy foods?")
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

    // MARK: - Toolbar

    private var filterMenu: some View {
        Menu {
            Picker("Priority", selection: $selectedPriorityFilter) {
                Text("All Goals").tag(nil as Priority?)
                ForEach(Priority.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level as Priority?)
                }
            }
        } label: {
            Image(systemName: selectedPriorityFilter == nil
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter by priority")
    }

    @ViewBuilder
    private var addButton: some View {
        if isSavingsGoalHidden {
            Menu {
                Button { editor = .new } label: { Label("New Goal", systemImage: "plus") }
                Button(action: showSavingsGoal) { Label("Show Savings Goal", systemImage: "dollarsign.circle") }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add")
        } else {
            Button { editor = .new } label: { Image(systemName: "plus") }
                .accessibilityLabel("New goal")
        }
    }

    // MARK: - Rows

    private var emptyRow: some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundColor(PLColor.textSecondary)
            Text(selectedPriorityFilter == nil ? "No goals yet" : "No \(selectedPriorityFilter!.rawValue.lowercased())-priority goals")
                .font(.headline)
            Text("Tap + to add one.")
                .font(.subheadline)
                .foregroundColor(PLColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PLSpacing.md)
    }

    private func goalRow(_ task: TaskItem) -> some View {
        HStack(spacing: PLSpacing.md) {
            Circle()
                .fill(priorityColor(task.priority))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? PLColor.textSecondary : PLColor.textPrimary)

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
                        Text("Due \(Self.shortDate(dueDate))")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    if let parent = parentTitle(of: task) {
                        Text("\(Image(systemName: "flag.fill")) \(parent)")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                            .lineLimit(1)
                            .accessibilityLabel("Step of \(parent)")
                    }
                    if !task.reminders.isEmpty {
                        Text("\(Image(systemName: task.isCompleted ? "bell.slash" : "bell.fill")) \(task.reminders.count)")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                            .accessibilityLabel("\(task.reminders.count) reminder\(task.reminders.count == 1 ? "" : "s")")
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
            .accessibilityLabel(task.isCompleted ? "Mark not done" : "Mark done")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { editor = .edit(task) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { sharing = task } label: { Label("Share", systemImage: "person.2.fill") }
                .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { deleteGoal(task) } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button { editor = .edit(task) } label: { Label("Edit", systemImage: "pencil") }
            Button { sharing = task } label: { Label("Share to Friends", systemImage: "person.2.fill") }
            Button(role: .destructive) { deleteGoal(task) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // "Oct 10", with the year only when it isn't this year
    static func shortDate(_ date: Date) -> String {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    private var savingsRow: some View {
        let budget = savingsSummary?.totalBudget ?? 0
        let costs = savingsSummary?.totalCosts ?? 0
        let progress = budget > 0 ? min(costs / budget, 1.0) : 0.0
        return HStack(spacing: PLSpacing.md) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundColor(PLColor.success)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Save for Weekly Expenses")
                    .font(.headline)
                    .foregroundColor(PLColor.textPrimary)
                ProgressView(value: progress)
                    .tint(PLColor.success)
                Text(budget > 0
                     ? String(format: "%.0f%% of budget used · $%.2f of $%.2f", progress * 100, costs, budget)
                     : "Set a weekly budget to track this.")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: hideSavingsGoal) { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button(role: .destructive, action: hideSavingsGoal) { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Saving goals

    /// widgets and the phone's reminders follow every change
    static func weeklyGoalsChanged(_ tasks: [TaskItem]) {
        WidgetDataWriter.writeGoals(tasks)
        WidgetDataWriter.reloadWidgets()
        GoalReminders.sync(tasks)
    }

    private func goalsChanged() { Self.weeklyGoalsChanged(tasks) }

    private func addGoal(_ goal: TaskItem) async -> Bool {
        do {
            try await GoalsAPI.addWeekly(goal)
        } catch {
            AppBanner.report("add your goal", error)
            return false
        }
        tasks.append(goal)
        goalsChanged()
        Self.addCalendarEvent(for: goal, calendarVM: calendarVM)
        if detectGroceryKeywords(in: goal.name) {
            taskNameForGrocList = goal.name
            showingGroceryAlert = true
        }
        return true
    }

    private func updateGoal(_ goal: TaskItem, previous: TaskItem) async -> Bool {
        do {
            try await GoalsAPI.updateWeekly(goal)
        } catch {
            AppBanner.report("save your changes to the goal", error)
            return false
        }
        if let i = tasks.firstIndex(where: { $0.id == goal.id }) { tasks[i] = goal }
        goalsChanged()
        if goal.name != previous.name || goal.dueDate != previous.dueDate {
            calendarVM.deleteEventByType(Self.calendarType(for: previous))
            Self.addCalendarEvent(for: goal, calendarVM: calendarVM)
        }
        return true
    }

    private func deleteGoal(_ task: TaskItem) {
        Task {
            do {
                try await GoalsAPI.deleteWeekly(task.id)
            } catch {
                AppBanner.report("delete the goal", error, retry: { deleteGoal(task) })
                return
            }
            tasks.removeAll { $0.id == task.id }
            goalsChanged()
            calendarVM.deleteEventByType(Self.calendarType(for: task))
            updateLinkedStep(of: task) { $0.weeklyGoalId = nil } // the server unlinked it
        }
    }

    private func toggleTaskCompletion(task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let done = !tasks[index].isCompleted
        tasks[index].isCompleted = done
        // before the network call, so the widget updates even if the app is closed right away
        goalsChanged()
        Task {
            do {
                try await GoalsAPI.setWeeklyCompleted(task.id, done)
            } catch {
                AppBanner.report("update the goal", error)
                if let i = tasks.firstIndex(where: { $0.id == task.id }) { // put the checkmark back
                    tasks[i].isCompleted = !done
                    goalsChanged()
                }
                return
            }
            updateLinkedStep(of: task) { $0.isCompleted = done } // the server checked off the step too
            GoalReminders.syncLongTerm(longTermGoals)
        }
    }

    private func resetGoals() {
        Task {
            do {
                try await GoalsAPI.resetWeekly()
            } catch {
                AppBanner.report("reset your goals", error, retry: { resetGoals() })
                return
            }
            for task in tasks { updateLinkedStep(of: task) { $0.weeklyGoalId = nil } }
            tasks.removeAll()
            goalsChanged()
        }
    }

    // MARK: - Links to long-term steps

    private func parentTitle(of task: TaskItem) -> String? {
        guard let id = task.longTermGoalId else { return nil }
        return longTermGoals.first { $0.id == id }?.title
    }

    private func updateLinkedStep(of task: TaskItem, _ change: (inout LongTermStep) -> Void) {
        guard let goalId = task.longTermGoalId, let stepId = task.longTermStepId,
              let g = longTermGoals.firstIndex(where: { $0.id == goalId }),
              let s = longTermGoals[g].steps.firstIndex(where: { $0.id == stepId }) else { return }
        change(&longTermGoals[g].steps[s])
    }

    private func openRequestedGoal() {
        guard let request = router.request, request.tab == .weekly,
              let id = Int(request.goalId), let task = tasks.first(where: { $0.id == id }) else { return }
        router.request = nil
        selectedPriorityFilter = nil
        editor = .edit(task)
    }

    static func calendarType(for task: TaskItem) -> String { "weekly-goal-\(task.name.lowercased())" }

    @MainActor
    static func addCalendarEvent(for goal: TaskItem, calendarVM: CalendarViewModel) {
        guard let due = goal.dueDate else { return }
        calendarVM.createEvent(
            title: goal.name,
            description: "Weekly Goal - Priority: \(goal.priority.rawValue)",
            startDate: due,
            endDate: due,
            eventType: Self.calendarType(for: goal),
            recurrence: "none",
            invitedFriends: []
        )
    }

    private func detectGroceryKeywords(in text: String) -> Bool {
        let lower = text.lowercased()
        return groceryKeywords.contains { lower.contains($0) }
    }

    // MARK: - Savings goal

    private func showSavingsGoal() {
        isSavingsGoalHidden = false
        UserDefaults.standard.removeObject(forKey: savingsGoalHiddenKey)
        loadSavingsSummary()
    }

    private func hideSavingsGoal() {
        isSavingsGoalHidden = true
        UserDefaults.standard.set(true, forKey: savingsGoalHiddenKey)
    }

    private func loadSavingsSummary() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/financial-data") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data,
                  let summary = try? JSONDecoder().decode(FinancialSummary.self, from: data) else { return }
            WidgetDataWriter.writeFinancial(period: "weekly", totalSpent: summary.totalCosts, totalBudget: summary.totalBudget)
            WidgetDataWriter.reloadWidgets()
            DispatchQueue.main.async { savingsSummary = summary }
        }.resume()
    }

    // MARK: - Grocery list from a goal

    private func createGroceryListFromGoal() {
        isGeneratingGroceryList = true
        Task {
            do {
                let groceryList = try await GroceryListAPI.generateGroceryListFromGoal(goalTitle: taskNameForGrocList)
                DispatchQueue.main.async {
                    isGeneratingGroceryList = false
                    showAlert("Grocery List Created", "Your grocery list \(groceryList) has been created.")
                }
            } catch {
                DispatchQueue.main.async {
                    isGeneratingGroceryList = false
                    if let limit = error as? AILimitError {
                        showAlert("Daily AI limit reached", limit.message)
                    } else {
                        showAlert("Creation Failed", "Could not create grocery list: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        groceryAlertTitle = title; groceryAlertMessage = message; showingGroceryActionAlert = true
    }
}
