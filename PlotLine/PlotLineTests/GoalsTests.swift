//
//  GoalsTests.swift
//  PlotLineTests
//
//  Goals page: weekly to-dos and long-term goals as the server sends them.
//

import Testing
import Foundation
@testable import PlotLine

struct GoalsTests {

    @Test("Weekly goal from the server decodes ('completed' maps to isCompleted)")
    func weeklyGoal() throws {
        let task = try TestJSON.decode(TaskItem.self,
            #"{"id":3,"name":"Gym 3x","completed":true,"priority":"High","notificationsEnabled":false}"#)
        #expect(task.id == 3)
        #expect(task.isCompleted)
        #expect(task.dueDate == nil)
        #expect(task.notificationsEnabled == false)
    }

    @Test("Long-term goal with steps decodes")
    func longTermGoal() throws {
        let goal = try TestJSON.decode(LongTermGoal.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","title":"Emergency fund",
         "steps":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302","name":"Save $500","completed":true},
                  {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3303","name":"Save $1000","completed":false}]}
        """, iso8601: false)
        #expect(goal.title == "Emergency fund")
        #expect(goal.steps.map(\.isCompleted) == [true, false])
    }
}

// Reminders on weekly goals: when each kind goes off, which ones get scheduled, and the saved format
struct GoalReminderTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    @Test("Each kind goes off at the right local time")
    func fireDates() {
        let due = date("2026-10-20 00:00")
        #expect(GoalReminder(kind: .dueDate, time: "09:00").fireDate(dueDate: due, calendar: calendar) == date("2026-10-20 09:00"))
        #expect(GoalReminder(kind: .dayBefore, time: "18:30").fireDate(dueDate: due, calendar: calendar) == date("2026-10-19 18:30"))
        #expect(GoalReminder(kind: .weekBefore, time: "07:05").fireDate(dueDate: due, calendar: calendar) == date("2026-10-13 07:05"))
        #expect(GoalReminder(kind: .custom, time: "12:00", date: "2026-10-15").fireDate(dueDate: due, calendar: calendar) == date("2026-10-15 12:00"))
        // can't be worked out
        #expect(GoalReminder(kind: .dayBefore).fireDate(dueDate: nil, calendar: calendar) == nil)
        #expect(GoalReminder(kind: .custom).fireDate(dueDate: due, calendar: calendar) == nil)
        var unknown = GoalReminder(kind: .dueDate)
        unknown.kind = "everyFullMoon" // from a newer app version
        #expect(unknown.fireDate(dueDate: due, calendar: calendar) == nil)
    }

    @Test("Only future reminders of unfinished goals are scheduled")
    func pending() {
        let now = date("2026-10-18 12:00")
        var goal = TaskItem(id: 42, name: "Dentist", isCompleted: false, priority: .high, dueDate: date("2026-10-20 00:00"),
                            reminders: [GoalReminder(kind: .weekBefore), GoalReminder(kind: .dayBefore), GoalReminder(kind: .dueDate)])
        let scheduled = GoalReminders.pending(for: goal, now: now)
        #expect(scheduled.count == 2) // the week-before one already passed
        #expect(scheduled.allSatisfy { $0.id.hasPrefix("goal-42-") })

        goal.isCompleted = true
        #expect(GoalReminders.pending(for: goal, now: now).isEmpty)
    }

    @Test("The notification says when the goal is due")
    func body() {
        let goal = TaskItem(id: 1, name: "Dentist", isCompleted: false, priority: .high, dueDate: date("2026-10-20 00:00"))
        #expect(GoalReminders.body(for: goal, at: date("2026-10-20 09:00"), calendar: calendar) == "This goal is due today.")
        #expect(GoalReminders.body(for: goal, at: date("2026-10-19 18:00"), calendar: calendar) == "This goal is due tomorrow.")
        #expect(GoalReminders.body(for: goal, at: date("2026-10-13 09:00"), calendar: calendar).hasSuffix("(in 7 days)."))
    }

    @Test("Reminders round-trip in the server's format; goals without any still decode")
    func savedFormat() throws {
        let decoder = JSONDecoder() // as GoalsView loads goals
        decoder.dateDecodingStrategy = .formatted(GoalReminder.dayFormatter)
        let goal = try decoder.decode(TaskItem.self, from: Data("""
        {"id":7,"name":"Dentist","completed":false,"priority":"High","dueDate":"2026-10-20",
         "reminders":[{"id":"r1","kind":"dayBefore","time":"18:30"},{"id":"r2","kind":"custom","time":"08:00","date":"2026-10-11"}]}
        """.utf8))
        #expect(goal.dueDate != nil)
        #expect(goal.reminders.map(\.kind) == ["dayBefore", "custom"])
        #expect(goal.reminders[1].date == "2026-10-11")

        let old = try TestJSON.decode(TaskItem.self, #"{"id":3,"name":"Gym","completed":false,"priority":"Low"}"#)
        #expect(old.reminders.isEmpty)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(GoalReminder.dayFormatter)
        let json = String(decoding: try encoder.encode(goal), as: UTF8.self)
        #expect(json.contains(#""dueDate":"2026-10-20""#)) // what the server expects
        #expect(json.contains(#""kind":"dayBefore""#))
    }

    @Test("A shared weekly goal in the feed decodes")
    func weeklyFeedPost() throws {
        let post = try TestJSON.decode(FriendPost.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","username":"sam",
         "goal":{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","title":"Gym 3x","steps":[]},
         "weeklyGoal":{"name":"Gym 3x","priority":"High","dueDate":"2026-10-12","completed":true},
         "comment":"Done early!","likedBy":[],"comments":[]}
        """, iso8601: false)
        #expect(post.weeklyGoal?.name == "Gym 3x")
        #expect(post.weeklyGoal?.completed == true)
        #expect(post.comment == "Done early!")
    }
}

// Long-term goals: target dates, reminders, step links, and opening a goal from its notification
struct LongTermGoalTests {
    private func day(_ text: String, _ time: String = "00:00") -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: "\(text) \(time)")!
    }

    @Test("Goals saved before target dates, reminders and links still load")
    func oldFormat() throws {
        let goal = try TestJSON.decode(LongTermGoal.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","title":"Emergency fund",
         "steps":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302","name":"Save $500","completed":true}]}
        """, iso8601: false)
        #expect(goal.targetDate == nil)
        #expect(goal.reminders.isEmpty)
        #expect(goal.steps[0].weeklyGoalId == nil)
        #expect(goal.isDone)

        let linked = try TestJSON.decode(LongTermGoal.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","title":"Spanish","targetDate":"2027-03-01",
         "reminders":[{"id":"r1","kind":"weekBefore","time":"10:00"}],
         "steps":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302","name":"Class","completed":false,"weeklyGoalId":55}]}
        """, iso8601: false)
        #expect(linked.target == day("2027-03-01"))
        #expect(linked.steps[0].weeklyGoalId == 55)
        #expect(!linked.isDone)

        let task = try TestJSON.decode(TaskItem.self, """
        {"id":55,"name":"Class","completed":false,"priority":"Medium",
         "longTermGoalId":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","longTermStepId":"3F2504E0-4F89-11D3-9A0C-0305E82C3302"}
        """)
        #expect(task.longTermStepId?.uuidString == "3F2504E0-4F89-11D3-9A0C-0305E82C3302")
    }

    @Test("Long-term reminders count back from the target date and stop once every step is done")
    func reminders() {
        var goal = LongTermGoal(id: UUID(), title: "Half marathon",
                                steps: [LongTermStep(id: UUID(), name: "10k", isCompleted: false)],
                                targetDate: "2027-03-15",
                                reminders: [GoalReminder(kind: .weekBefore, time: "08:00"),
                                            GoalReminder(kind: .custom, time: "12:00", date: "2027-01-01")])
        let scheduled = GoalReminders.pending(for: goal, now: day("2026-12-01"))
        #expect(scheduled.count == 2)
        #expect(scheduled.contains { $0.date == day("2027-03-08", "08:00") })
        #expect(scheduled.allSatisfy { $0.id.hasPrefix("lgoal-") })

        goal.targetDate = nil // relative ones need a target date; custom still works
        #expect(GoalReminders.pending(for: goal, now: day("2026-12-01")).count == 1)

        goal.steps[0].isCompleted = true
        #expect(GoalReminders.pending(for: goal, now: day("2026-12-01")).isEmpty)
    }

    @Test("Long-term notification text")
    func body() {
        let goal = LongTermGoal(id: UUID(), title: "Half marathon",
                                steps: [LongTermStep(id: UUID(), name: "10k", isCompleted: true),
                                        LongTermStep(id: UUID(), name: "15k", isCompleted: false)],
                                targetDate: "2027-03-15")
        #expect(GoalReminders.longTermBody(for: goal, at: day("2027-03-14", "09:00")) == "Target date is tomorrow. 1 of 2 steps done.")
        #expect(GoalReminders.longTermBody(for: LongTermGoal(id: UUID(), title: "x", steps: []), at: Date())
                == "Reminder for your long-term goal.")
    }

    @MainActor
    @Test("Tapping a reminder asks Goals to open that goal on the right tab")
    func router() {
        let router = GoalsRouter.shared
        defer { router.request = nil }
        router.open(["navigateTo": "goals", "goalsTab": "longTerm", "goalId": "3F2504E0-4F89-11D3-9A0C-0305E82C3301"])
        #expect(router.request == .init(tab: .longTerm, goalId: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        router.open(["navigateTo": "goals", "goalsTab": "weekly", "goalId": "42"])
        #expect(router.request == .init(tab: .weekly, goalId: "42"))
        router.request = nil
        router.open(["navigateTo": "calendar"]) // not ours
        #expect(router.request == nil)
    }
}
