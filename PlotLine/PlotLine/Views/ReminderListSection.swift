//
//  ReminderListSection.swift
//  PlotLine
//
//  The "Reminders" part of the goal sheets (weekly and long-term): any number of reminders,
//  each on the due/target date, 1 day or 1 week before (at a time you pick), or a custom date.
//

import SwiftUI

struct ReminderListSection: View {
    @Binding var reminders: [GoalReminder]
    /// the due date (weekly) or target date (long-term); relative reminders need one
    let anchorDate: Date?
    /// "due date" or "target date"
    let anchorName: String

    var body: some View {
        Section {
            ForEach($reminders) { $reminder in
                row($reminder)
            }
            .onDelete { reminders.remove(atOffsets: $0) }

            Menu {
                ForEach(GoalReminder.Kind.allCases, id: \.self) { kind in
                    if kind == .custom {
                        Button("Custom date & time") { add(kind) }
                    } else if anchorDate != nil {
                        Button(kind.label(anchor: anchorName)) { add(kind) }
                    }
                }
            } label: {
                Label("Add Reminder", systemImage: "bell.badge")
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var parts: [String] = []
        if anchorDate == nil { parts.append("Set a \(anchorName) to add reminders relative to it.") }
        parts.append(reminders.isEmpty ? "Add as many as you like." : "Swipe a reminder to remove it.")
        parts.append("They stop once the goal is done.")
        return parts.joined(separator: " ")
    }

    private func row(_ reminder: Binding<GoalReminder>) -> some View {
        let value = reminder.wrappedValue
        let fire = value.fireDate(dueDate: anchorDate)
        return VStack(alignment: .leading, spacing: 4) {
            if value.type == .custom {
                DatePicker("Custom", selection: customDateBinding(reminder), displayedComponents: [.date, .hourAndMinute])
            } else {
                DatePicker(value.type?.label(anchor: anchorName) ?? "Reminder", selection: timeBinding(reminder),
                           displayedComponents: .hourAndMinute)
            }
            if value.type != .custom, anchorDate == nil {
                Text("Needs a \(anchorName), so it won't go off.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if let fire, fire <= Date() {
                Text("This time has already passed, so it won't go off.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // "HH:mm" and "yyyy-MM-dd" text <-> the pickers
    private func timeBinding(_ reminder: Binding<GoalReminder>) -> Binding<Date> {
        Binding(
            get: { GoalReminder.timeFormatter.date(from: reminder.wrappedValue.time) ?? Date() },
            set: { reminder.wrappedValue.time = GoalReminder.timeFormatter.string(from: $0) }
        )
    }

    private func customDateBinding(_ reminder: Binding<GoalReminder>) -> Binding<Date> {
        Binding(
            get: { reminder.wrappedValue.fireDate(dueDate: anchorDate) ?? Date() },
            set: {
                reminder.wrappedValue.date = GoalReminder.dayFormatter.string(from: $0)
                reminder.wrappedValue.time = GoalReminder.timeFormatter.string(from: $0)
            }
        )
    }

    private func add(_ kind: GoalReminder.Kind) {
        var reminder = GoalReminder(kind: kind)
        if kind == .custom {
            // tomorrow at 9 AM to start with
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            reminder.date = GoalReminder.dayFormatter.string(from: tomorrow)
        }
        reminders.append(reminder)
        Task { _ = await GoalReminders.requestPermission() }
    }
}
