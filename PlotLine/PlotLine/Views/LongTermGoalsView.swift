//
//  LongTermGoalsView.swift
//  PlotLine
//
//  Long-term goals, laid out like weekly goals: a compact list with progress. "+" adds a goal,
//  the archive button shows archived ones. Tap a goal for its steps, target date and reminders;
//  swipe to share or archive.
//

import SwiftUI

struct LongTermGoalsView: View {
    @Binding var longTermGoals: [LongTermGoal]
    @Binding var weeklyGoals: [TaskItem]
    let username: String
    var calendarVM: CalendarViewModel
    @ObservedObject private var router = GoalsRouter.shared

    private struct GoalRef: Identifiable { let id: UUID }

    @State private var archivedGoals: [LongTermGoal] = []
    @State private var showArchived = false
    @State private var adding = false
    @State private var editing: LongTermGoal?
    @State private var opened: GoalRef?
    @State private var sharing: LongTermGoal?
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                if longTermGoals.isEmpty {
                    emptyRow
                } else {
                    ForEach(longTermGoals) { goal in
                        goalRow(goal)
                    }
                }
            }
            .listRowBackground(PLColor.surface)

            if !longTermGoals.isEmpty {
                Section {
                    Button("Reset Long-Term Goals", role: .destructive) { confirmReset = true }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(PLColor.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showArchived = true } label: { Image(systemName: "archivebox") }
                    .accessibilityLabel("Archived goals")
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New long-term goal")
            }
        }
        .sheet(isPresented: $adding) {
            LongTermGoalEditor(existing: nil) { await addGoal($0) }
        }
        .sheet(item: $editing) { goal in
            LongTermGoalEditor(existing: goal) { await updateGoal($0) }
        }
        .sheet(item: $opened) { ref in
            LongTermGoalDetail(goalId: ref.id, goals: $longTermGoals, weeklyGoals: $weeklyGoals,
                               username: username, calendarVM: calendarVM, onArchive: archiveGoal)
        }
        .sheet(item: $sharing) { goal in
            ShareGoalSheet(goal: .longTerm(goal), username: username)
        }
        .sheet(isPresented: $showArchived) {
            ArchivedGoalsView(archivedGoals: $archivedGoals, unarchiveGoal: unarchiveGoal)
        }
        .confirmationDialog("Delete all your long-term goals?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete All", role: .destructive, action: resetGoals)
        } message: {
            Text("This also deletes your archived goals.") // the server clears both
        }
        .onAppear(perform: openRequestedGoal)
        // a tapped reminder: open that goal once it's loaded
        .onChange(of: router.request) { _, _ in openRequestedGoal() }
        .onChange(of: longTermGoals.map(\.id)) { _, _ in openRequestedGoal() }
    }

    // MARK: - Rows

    private var emptyRow: some View {
        VStack(spacing: 6) {
            Image(systemName: "flag")
                .font(.title2)
                .foregroundColor(PLColor.textSecondary)
            Text("No long-term goals yet")
                .font(.headline)
            Text("Tap + to add one, with the steps to get there.")
                .font(.subheadline)
                .foregroundColor(PLColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PLSpacing.md)
    }

    private func goalRow(_ goal: LongTermGoal) -> some View {
        let progress = goal.steps.isEmpty ? 0 : Double(goal.completedSteps) / Double(goal.steps.count)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: PLSpacing.sm) {
                Text(goal.title)
                    .font(.headline)
                    .foregroundColor(PLColor.textPrimary)
                if goal.isDone {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(PLColor.success)
                        .accessibilityLabel("Done")
                }
                Spacer(minLength: 0)
                if let target = goal.target {
                    Text(WeeklyGoalsView.shortDate(target))
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                        .accessibilityLabel("Target \(target.formatted(date: .long, time: .omitted))")
                }
                if !goal.reminders.isEmpty {
                    Text("\(Image(systemName: goal.isDone ? "bell.slash" : "bell.fill")) \(goal.reminders.count)")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                        .accessibilityLabel("\(goal.reminders.count) reminder\(goal.reminders.count == 1 ? "" : "s")")
                }
            }
            ProgressView(value: progress)
                .tint(PLColor.success)
            Text(goal.steps.isEmpty ? "No steps yet" : "\(goal.completedSteps) of \(goal.steps.count) steps")
                .font(.caption)
                .foregroundColor(PLColor.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { opened = GoalRef(id: goal.id) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { sharing = goal } label: { Label("Share", systemImage: "person.2.fill") }
                .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { archiveGoal(goal) } label: { Label("Archive", systemImage: "archivebox") }
                .tint(.orange)
        }
        .contextMenu {
            Button { opened = GoalRef(id: goal.id) } label: { Label("Open", systemImage: "list.bullet") }
            Button { editing = goal } label: { Label("Edit", systemImage: "pencil") }
            Button { sharing = goal } label: { Label("Share to Friends", systemImage: "person.2.fill") }
            Button { archiveGoal(goal) } label: { Label("Archive", systemImage: "archivebox") }
        }
    }

    // MARK: - Actions

    private func addGoal(_ goal: LongTermGoal) async -> Bool {
        do {
            try await GoalsAPI.addLongTerm(goal)
        } catch {
            AppBanner.report("add your goal", error)
            return false
        }
        longTermGoals.append(goal)
        GoalReminders.syncLongTerm(longTermGoals)
        return true
    }

    private func updateGoal(_ goal: LongTermGoal) async -> Bool {
        do {
            try await GoalsAPI.updateLongTerm(goal)
        } catch {
            AppBanner.report("save your changes to the goal", error)
            return false
        }
        if let i = longTermGoals.firstIndex(where: { $0.id == goal.id }) { longTermGoals[i] = goal }
        GoalReminders.syncLongTerm(longTermGoals)
        return true
    }

    private func archiveGoal(_ goal: LongTermGoal) {
        longTermGoals.removeAll { $0.id == goal.id }
        archivedGoals.append(goal)
        GoalReminders.syncLongTerm(longTermGoals) // archived goals don't remind
        Task {
            do {
                try await GoalsAPI.archiveLongTerm(goal.id)
            } catch {
                AppBanner.report("archive the goal", error)
                archivedGoals.removeAll { $0.id == goal.id }
                if !longTermGoals.contains(where: { $0.id == goal.id }) { longTermGoals.append(goal) }
                GoalReminders.syncLongTerm(longTermGoals)
            }
        }
    }

    private func unarchiveGoal(_ goal: LongTermGoal) {
        archivedGoals.removeAll { $0.id == goal.id }
        longTermGoals.append(goal)
        GoalReminders.syncLongTerm(longTermGoals)
        Task {
            do {
                try await GoalsAPI.unarchiveLongTerm(goal.id)
            } catch {
                AppBanner.report("unarchive the goal", error)
                longTermGoals.removeAll { $0.id == goal.id }
                if !archivedGoals.contains(where: { $0.id == goal.id }) { archivedGoals.append(goal) }
                GoalReminders.syncLongTerm(longTermGoals)
            }
        }
    }

    private func resetGoals() {
        Task {
            do {
                try await GoalsAPI.resetLongTerm()
            } catch {
                AppBanner.report("reset your goals", error, retry: { resetGoals() })
                return
            }
            longTermGoals.removeAll()
            GoalReminders.syncLongTerm([])
        }
    }

    private func openRequestedGoal() {
        guard let request = router.request, request.tab == .longTerm,
              let id = UUID(uuidString: request.goalId), longTermGoals.contains(where: { $0.id == id }) else { return }
        router.request = nil
        opened = GoalRef(id: id)
    }
}
