//
//  LongTermGoalEditor.swift
//  PlotLine
//
//  The sheet for adding or editing a long-term goal: title, steps, an optional target date and
//  reminders. Same layout as the weekly goal sheet.
//

import SwiftUI

struct LongTermGoalEditor: View {
    /// nil to add a new goal
    let existing: LongTermGoal?
    /// gets the finished goal; returns once it's saved (the sheet stays open if saving fails)
    let onSave: (LongTermGoal) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var steps: [LongTermStep]
    @State private var hasTarget: Bool
    @State private var target: Date
    @State private var reminders: [GoalReminder]
    @State private var newStep = ""
    @State private var isSaving = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, newStep, step(UUID) }

    /// the step being renamed; the others are plain text so press-and-hold drags them
    @State private var renaming: UUID?

    init(existing: LongTermGoal?, onSave: @escaping (LongTermGoal) async -> Bool) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _steps = State(initialValue: existing?.steps ?? [])
        _hasTarget = State(initialValue: existing?.target != nil)
        _target = State(initialValue: existing?.target
                        ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
        _reminders = State(initialValue: existing?.reminders ?? [])
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List { // a List (not Form) so press-and-hold drags steps
                Section {
                    TextField("What's the goal?", text: $title)
                        .focused($focus, equals: .title)
                    Toggle("Target date", isOn: $hasTarget.animation())
                    if hasTarget {
                        DatePicker("Date", selection: $target, displayedComponents: .date)
                    }
                }

                Section {
                    ForEach($steps) { $step in
                        HStack {
                            if renaming == step.id {
                                TextField("Step", text: $step.name)
                                    .focused($focus, equals: .step(step.id))
                                    .submitLabel(.done)
                                    .onSubmit { renaming = nil }
                            } else {
                                Text(step.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        renaming = step.id
                                        focus = .step(step.id)
                                    }
                                    .accessibilityHint("Tap to rename")
                            }
                            if step.weeklyGoalId != nil {
                                Text("Weekly")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PLColor.accent.opacity(0.15))
                                    .foregroundColor(PLColor.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 } // full-width divider
                        .swipeActions {
                            Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) } // press and hold, then drag

                    HStack {
                        TextField("Add a step", text: $newStep)
                            .focused($focus, equals: .newStep)
                            .submitLabel(.next)
                            .onSubmit(addStep)
                        Button(action: addStep) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add step")
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Tap a step to rename it, press and hold to move it, swipe to remove it. Open the goal to check steps off or make one a weekly goal.")
                }

                ReminderListSection(reminders: $reminders, anchorDate: hasTarget ? target : nil, anchorName: "target date")
            }
            .listStyle(.insetGrouped)
            .navigationTitle(existing == nil ? "New Long-Term Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(existing == nil ? "Add" : "Save", action: save)
                            .disabled(trimmedTitle.isEmpty)
                    }
                }
            }
            .onAppear { if existing == nil { focus = .title } }
            .onChange(of: focus) { _, field in // done renaming once the field loses focus
                if case .step = field {} else { renaming = nil }
            }
        }
        .tint(PLColor.accent)
    }

    private func addStep() {
        let name = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        steps.append(LongTermStep(id: UUID(), name: name, isCompleted: false))
        newStep = ""
        focus = .newStep
    }

    private func save() {
        addStep() // a step still typed in counts
        var goal = existing ?? LongTermGoal(id: UUID(), title: "", steps: [])
        goal.title = trimmedTitle
        goal.steps = steps.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        goal.targetDate = hasTarget ? GoalReminder.dayFormatter.string(from: target) : nil
        goal.reminders = reminders
        isSaving = true
        Task {
            let saved = await onSave(goal)
            isSaving = false
            if saved { dismiss() }
        }
    }
}
