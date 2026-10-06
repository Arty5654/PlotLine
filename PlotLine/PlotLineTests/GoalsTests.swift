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
