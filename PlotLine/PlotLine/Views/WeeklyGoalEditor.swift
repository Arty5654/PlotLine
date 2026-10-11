//
//  WeeklyGoalEditor.swift
//  PlotLine
//
//  The sheet for adding or editing a weekly goal: name, priority, due date and reminders.
//

import SwiftUI

struct WeeklyGoalEditor: View {
    /// the goal being edited, or nil to add a new one
    let existing: TaskItem?
    /// gets the finished goal; returns once it's saved (the sheet stays open if saving fails)
    let onSave: (TaskItem) async -> Bool
    private let start: TaskItem

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var priority: Priority
    @State private var dueDate: Date
    @State private var reminders: [GoalReminder]
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    /// `template` pre-fills a new goal (e.g. a long-term step made into a weekly goal)
    init(existing: TaskItem?, template: TaskItem? = nil, onSave: @escaping (TaskItem) async -> Bool) {
        self.existing = existing
        self.onSave = onSave
        let start = existing ?? template ?? TaskItem(id: Int.random(in: 1...Int(Int32.max)), name: "",
                                                     isCompleted: false, priority: .medium)
        self.start = start
        _name = State(initialValue: start.name)
        _priority = State(initialValue: start.priority)
        _dueDate = State(initialValue: start.dueDate ?? Date())
        _reminders = State(initialValue: start.reminders)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's the goal?", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                } footer: {
                    if start.longTermStepId != nil {
                        Text("This is a step of a long-term goal: checking off one checks off both.")
                    }
                }

                ReminderListSection(reminders: $reminders, anchorDate: dueDate, anchorName: "due date")
            }
            .navigationTitle(existing == nil ? "New Goal" : "Edit Goal")
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
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
            .onAppear { if start.name.isEmpty { nameFocused = true } }
        }
        .tint(PLColor.accent)
    }

    private func save() {
        var goal = start
        goal.name = trimmedName
        goal.priority = priority
        goal.dueDate = dueDate
        goal.reminders = reminders
        goal.isEditing = false
        isSaving = true
        Task {
            let saved = await onSave(goal)
            isSaving = false
            if saved { dismiss() }
        }
    }
}
