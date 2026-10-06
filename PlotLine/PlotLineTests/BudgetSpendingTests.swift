//
//  BudgetSpendingTests.swift
//  PlotLineTests
//
//  Budget & spending pages: budgets, costs, subscriptions, membership.
//

import Testing
import Foundation
@testable import PlotLine

struct BudgetSpendingTests {

    @Test("Budget from the server decodes")
    func budget() throws {
        let budget = try TestJSON.decode(BudgetResponse.self,
            #"{"username":"alex","type":"monthly","budget":{"Rent":1200.0,"Food":400}}"#)
        #expect(budget.budget["Rent"] == 1200)
        #expect(budget.budget["Food"] == 400)
    }

    @Test("Weekly/monthly costs decode")
    func costs() throws {
        let costs = try TestJSON.decode(WeeklyMonthlyCostResponse.self,
            #"{"username":"alex","type":"weekly","costs":{"Gas":30.5}}"#)
        #expect(costs.costs["Gas"] == 30.5)
    }

    @Test("Days are written as yyyy-MM-dd for the backend")
    func dayKeys() {
        #expect(TestJSON.day(2026, 10, 5).ymd() == "2026-10-05")
        #expect(TestJSON.day(2026, 1, 9).ymd() == "2026-01-09")
    }

    @Test("Subscription due dates are sent in the exact format the backend parses")
    func subscriptionDateFormat() throws {
        struct Wrapper: Codable { @CodableDate var dueDate: Date }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let due = utc.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!

        let body = try TestJSON.object(Wrapper(dueDate: due))
        #expect(body["dueDate"] as? String == "2026-10-20T09:00:00.000Z")

        // and reads it back, with or without fractional seconds
        let back = try TestJSON.decode(Wrapper.self, #"{"dueDate":"2026-10-20T09:00:00Z"}"#, iso8601: false)
        #expect(back.dueDate == due)
    }

    @Test("Detected recurring charges decode")
    func recurringPrompts() throws {
        let response = try TestJSON.decode(RecurringPromptResponse.self, """
        {"prompts":[{"snoozeKey":"netflix-15.49","name":"Netflix","averageAmount":15.49,"dayOfMonth":12,
          "consecutiveMonths":3,"lastSeen":"2026-09-12","nextReminderAfter":"2026-11-12"}],"remindAfterMonths":2}
        """, iso8601: false)
        #expect(response.prompts.first?.name == "Netflix")
        #expect(response.prompts.first?.id == "netflix-15.49")
    }

    @Test("Membership status decodes")
    func membership() throws {
        let status = try TestJSON.decode(SubscriptionStatus.self,
            #"{"plan":"trial","monthlyPrice":5.0,"trialEndsAt":"2026-11-04","autoRenews":true,"message":"Trial ends soon"}"#,
            iso8601: false)
        #expect(status.plan == "trial")
        #expect(status.monthlyPrice == 5)
        #expect(status.cancelled == nil)
    }
}
