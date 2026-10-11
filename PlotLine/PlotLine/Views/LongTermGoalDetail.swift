//
//  LongTermGoalDetail.swift
//  PlotLine
//
//  One long-term goal: its progress, target date and reminders, and its steps. Check steps off
//  here, or make one a weekly goal (they stay linked: checking off one checks off both).
//

import SwiftUI

struct LongTermGoalDetail: View {
    let goalId: UUID
    @Binding var goals: [LongTermGoal]
    @Binding var weeklyGoals: [TaskItem]
    let username: String
    var calendarVM: CalendarViewModel
    let onArchive: (LongTermGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var sharing = false
    @State private var makingWeekly: LongTermStep?

    private var index: Int? { goals.firstIndex { $0.id == goalId } }

    var body: some View {
        NavigationStack {
            Group {
                if let index {
                    content(goals[index])
                } else {
                    Text("This goal is no longer here.")
                        .foregroundColor(PLColor.textSecondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let index {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button { sharing = true } label: { Label("Share to Friends", systemImage: "person.2.fill") }
                            Button {
                                let goal = goals[index]
                                dismiss()
                                onArchive(goal)
                            } label: { Label("Archive", systemImage: "archivebox") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                        Button("Edit") { editing = true }
                    }
                }
            }
        }
        .tint(PLColor.accent)
        .sheet(isPresented: $editing) {
            if let index {
                LongTermGoalEditor(existing: goals[index]) { await save($0) }
            }
        }
        .sheet(isPresented: $sharing) {
            if let index {
                ShareGoalSheet(goal: .longTerm(goals[index]), username: username)
            }
        }
        .sheet(item: $makingWeekly) { step in
            WeeklyGoalEditor(existing: nil, template: weeklyTemplate(for: step)) { await makeWeekly($0, from: step) }
        }
    }

    private func content(_ goal: LongTermGoal) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text(goal.title)
                        .font(.title2.bold())
                        .foregroundColor(PLColor.textPrimary)
                    let meta = [goal.target.map { "Target \(WeeklyGoalsView.shortDate($0))" },
                                goal.reminders.isEmpty ? nil : "\(goal.reminders.count) reminder\(goal.reminders.count == 1 ? "" : "s")"]
                        .compactMap { $0 }
                    if !meta.isEmpty {
                        Text(meta.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    ProgressView(value: goal.steps.isEmpty ? 0 : Double(goal.completedSteps) / Double(goal.steps.count))
                        .tint(PLColor.success)
                    Text(goal.isDone ? "All steps done 🎉" : "\(goal.completedSteps) of \(goal.steps.count) steps done")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(PLColor.surface)

            Section {
                if goal.steps.isEmpty {
                    Text("No steps yet. Tap Edit to add some.")
                        .foregroundColor(PLColor.textSecondary)
                } else {
                    ForEach(goal.steps) { step in
                        stepRow(step, goal: goal)
                    }
                    .onMove { moveSteps(in: goal, from: $0, to: $1) } // press and hold a step, then drag
                }
            } header: {
                Text("Steps")
            } footer: {
                if !goal.steps.isEmpty {
                    Text("Press and hold a step to move it. \"Make weekly\" adds a step to your weekly goals; checking off either one checks off both.")
                }
            }
            .listRowBackground(PLColor.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func stepRow(_ step: LongTermStep, goal: LongTermGoal) -> some View {
        HStack(spacing: PLSpacing.md) {
            Button { toggle(step, in: goal) } label: {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(step.isCompleted ? PLColor.success : PLColor.textSecondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.isCompleted ? "Mark not done" : "Mark done")

            Text(step.name)
                .strikethrough(step.isCompleted)
                .foregroundColor(step.isCompleted ? PLColor.textSecondary : PLColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if step.weeklyGoalId != nil {
                Text("Weekly")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PLColor.accent.opacity(0.15))
                    .foregroundColor(PLColor.tint)
                    .clipShape(Capsule())
            } else if !step.isCompleted {
                // a plain-style button: a bordered one stops press-and-hold from dragging the row
                Button { makingWeekly = step } label: {
                    Text("Make weekly")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(PLColor.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PLColor.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func save(_ goal: LongTermGoal) async -> Bool {
        do {
            try await GoalsAPI.updateLongTerm(goal)
        } catch {
            AppBanner.report("save your changes to the goal", error)
            return false
        }
        if let i = goals.firstIndex(where: { $0.id == goal.id }) { goals[i] = goal }
        GoalReminders.syncLongTerm(goals)
        return true
    }

    private func toggle(_ step: LongTermStep, in goal: LongTermGoal) {
        guard let g = goals.firstIndex(where: { $0.id == goal.id }),
              let s = goals[g].steps.firstIndex(where: { $0.id == step.id }) else { return }
        let done = !goals[g].steps[s].isCompleted
        goals[g].steps[s].isCompleted = done
        Task {
            do {
                try await GoalsAPI.setStepCompleted(goalId: goal.id, stepId: step.id, done)
            } catch {
                AppBanner.report("update the step", error)
                if let g = goals.firstIndex(where: { $0.id == goal.id }),
                   let s = goals[g].steps.firstIndex(where: { $0.id == step.id }) {
                    goals[g].steps[s].isCompleted = !done // put it back
                }
                return
            }
            GoalReminders.syncLongTerm(goals)
            // the server checked off the linked weekly goal too
            if let weeklyId = step.weeklyGoalId, let w = weeklyGoals.firstIndex(where: { $0.id == weeklyId }) {
                weeklyGoals[w].isCompleted = done
                WeeklyGoalsView.weeklyGoalsChanged(weeklyGoals)
            }
        }
    }

    private func moveSteps(in goal: LongTermGoal, from source: IndexSet, to destination: Int) {
        guard let g = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        let before = goals[g].steps
        goals[g].steps.move(fromOffsets: source, toOffset: destination)
        let updated = goals[g]
        Task {
            do {
                try await GoalsAPI.updateLongTerm(updated)
            } catch {
                AppBanner.report("save the new step order", error)
                if let g = goals.firstIndex(where: { $0.id == goal.id }) { goals[g].steps = before }
            }
        }
    }

    private func weeklyTemplate(for step: LongTermStep) -> TaskItem {
        let inAWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let target = index.flatMap { goals[$0].target }
        var task = TaskItem(id: Int.random(in: 1...Int(Int32.max)), name: step.name, isCompleted: false,
                            priority: .medium, dueDate: min(target ?? inAWeek, inAWeek))
        task.longTermGoalId = goalId
        task.longTermStepId = step.id
        return task
    }

    private func makeWeekly(_ task: TaskItem, from step: LongTermStep) async -> Bool {
        do {
            try await GoalsAPI.addWeekly(task) // the server links the step to it
        } catch {
            AppBanner.report("add your weekly goal", error)
            return false
        }
        weeklyGoals.append(task)
        WeeklyGoalsView.weeklyGoalsChanged(weeklyGoals)
        WeeklyGoalsView.addCalendarEvent(for: task, calendarVM: calendarVM)
        if let g = goals.firstIndex(where: { $0.id == goalId }),
           let s = goals[g].steps.firstIndex(where: { $0.id == step.id }) {
            goals[g].steps[s].weeklyGoalId = task.id
        }
        return true
    }
}
