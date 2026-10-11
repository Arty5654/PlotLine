//
//  GoalReminders.swift
//  PlotLine
//
//  Puts weekly and long-term goals' reminders on the phone as local notifications. The reminders
//  themselves are saved with each goal on the server, so a new phone gets them back the next time
//  Goals loads. Tapping one opens that goal.
//

import Foundation
import UserNotifications

enum GoalReminders {
    private static let prefix = "goal-"          // weekly goals
    private static let longTermPrefix = "lgoal-" // long-term goals

    static func identifier(goalId: Int, reminderId: String) -> String { "\(prefix)\(goalId)-\(reminderId)" }
    static func identifier(longTermId: UUID, reminderId: String) -> String { "\(longTermPrefix)\(longTermId)-\(reminderId)" }

    /// The reminders to schedule for a goal: none once it's done, and only ones still in the future.
    static func pending(for goal: TaskItem, now: Date = Date()) -> [(id: String, date: Date)] {
        guard !goal.isCompleted, !goal.isFinancialGoal else { return [] }
        return goal.reminders.compactMap { reminder in
            guard let date = reminder.fireDate(dueDate: goal.dueDate), date > now else { return nil }
            return (identifier(goalId: goal.id, reminderId: reminder.id), date)
        }
    }

    /// Long-term goals: none once every step is checked off. Relative reminders count back from the target date.
    static func pending(for goal: LongTermGoal, now: Date = Date()) -> [(id: String, date: Date)] {
        guard !goal.isDone else { return [] }
        return goal.reminders.compactMap { reminder in
            guard let date = reminder.fireDate(dueDate: goal.target), date > now else { return nil }
            return (identifier(longTermId: goal.id, reminderId: reminder.id), date)
        }
    }

    /// Makes the phone's long-term reminders match these (active) goals.
    static func syncLongTerm(_ goals: [LongTermGoal]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(longTermPrefix) })
            for goal in goals {
                for (id, date) in pending(for: goal) {
                    center.add(request(id: id, title: goal.title, body: longTermBody(for: goal, at: date), date: date,
                                       tab: "longTerm", goalId: goal.id.uuidString))
                }
            }
        }
    }

    /// Makes the phone's goal reminders match these goals (after loading them, or any change).
    static func sync(_ goals: [TaskItem]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            // ours, plus the old one-per-goal reminders that used the bare goal id
            let goalIds = Set(goals.map { String($0.id) })
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) || goalIds.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for goal in goals {
                for (id, date) in pending(for: goal) {
                    center.add(request(id: id, title: goal.name, body: body(for: goal, at: date), date: date,
                                       tab: "weekly", goalId: String(goal.id)))
                }
            }
        }
    }

    /// Signing out: the next account on this phone shouldn't get these.
    static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier)
                .filter { $0.hasPrefix(prefix) || $0.hasPrefix(longTermPrefix) })
        }
    }

    /// Asks for notification permission the first time someone adds a reminder.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // tapping it opens that goal (AppDelegate → GoalsRouter)
    private static func request(id: String, title: String, body: String, date: Date,
                                tab: String, goalId: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["navigateTo": "goals", "goalsTab": tab, "goalId": goalId]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    static func longTermBody(for goal: LongTermGoal, at date: Date, calendar: Calendar = .current) -> String {
        let progress = "\(goal.completedSteps) of \(goal.steps.count) steps done"
        guard let target = goal.target else { return goal.steps.isEmpty ? "Reminder for your long-term goal." : progress + "." }
        let when = dueText(target, at: date, calendar: calendar, isDue: "Target date is", wasDue: "Target date was")
        return goal.steps.isEmpty ? when : "\(when) \(progress)."
    }

    static func body(for goal: TaskItem, at date: Date, calendar: Calendar = .current) -> String {
        guard let due = goal.dueDate else { return "Reminder for your weekly goal." }
        return dueText(due, at: date, calendar: calendar, isDue: "This goal is due", wasDue: "This goal was due")
    }

    private static func dueText(_ due: Date, at date: Date, calendar: Calendar, isDue: String, wasDue: String) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0: return "\(wasDue) \(due.formatted(date: .abbreviated, time: .omitted))."
        case 0: return "\(isDue) today."
        case 1: return "\(isDue) tomorrow."
        default: return "\(isDue) \(due.formatted(date: .abbreviated, time: .omitted)) (in \(days) days)."
        }
    }
}
