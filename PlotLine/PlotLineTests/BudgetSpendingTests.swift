//
//  BudgetSpendingTests.swift
//  PlotLineTests
//
//  Budget & spending pages: budgets, costs, subscriptions, membership.
//

import Testing
import Foundation
import StoreKit
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
        let status = try TestJSON.decode(MembershipStatus.self,
            #"{"plan":"trial","active":true,"expiresAt":"2026-11-04T18:30:00.123Z","autoRenews":null,"revoked":false}"#,
            iso8601: false)
        #expect(status.plan == "trial")
        #expect(status.active)
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-11-04T18:30:00Z"))
        #expect(abs(try #require(status.expiresDate).timeIntervalSince(expected) - 0.123) < 0.001)
        #expect(status.summary.hasPrefix("Free trial renews on"))

        // the server leaves out fractional seconds when they're zero
        let monthly = try TestJSON.decode(MembershipStatus.self,
            #"{"plan":"monthly","active":true,"expiresAt":"2026-11-04T18:30:00Z","autoRenews":false}"#, iso8601: false)
        #expect(monthly.expiresDate != nil)
        #expect(monthly.summary.contains("won't renew"))
    }

    @Test("Membership messages")
    func membershipSummaries() throws {
        func status(_ json: String) throws -> MembershipStatus {
            try TestJSON.decode(MembershipStatus.self, json, iso8601: false)
        }
        #expect(try status(#"{"plan":"lifetime","active":true}"#).summary.contains("free for you forever"))
        #expect(try status(#"{"plan":"none","active":false}"#).summary == "Start your free trial to use PlotLine.")
        #expect(try status(#"{"plan":"monthly","active":false,"expiresAt":"2026-01-01T00:00:00Z"}"#).summary == "Your membership has ended.")
        #expect(try status(#"{"plan":"monthly","active":false,"revoked":true}"#).summary.contains("refunded"))
        #expect(try status(#"{"plan":"free-week","active":true,"expiresAt":"2026-11-04T18:30:00Z"}"#).summary.hasPrefix("Your free week ends on"))
        #expect(try status(#"{"plan":"free-week","active":false,"expiresAt":"2026-01-01T00:00:00Z"}"#).summary.hasPrefix("Your free week has ended"))
    }

    @Test("Free week countdown")
    func freeWeekCountdown() throws {
        let week = try TestJSON.decode(MembershipStatus.self,
            #"{"plan":"free-week","active":true,"expiresAt":"2026-11-04T18:00:00Z"}"#, iso8601: false)
        let end = try #require(week.expiresDate)
        #expect(week.daysLeft(now: end.addingTimeInterval(-2.5 * 86_400)) == 3)
        #expect(week.daysLeft(now: end.addingTimeInterval(-3600)) == 1)
        #expect(week.isFreeWeek && !week.isSubscribed)

        #expect(FreeWeekBanner.message(daysLeft: 3) == "3 days left in your free week")
        #expect(FreeWeekBanner.message(daysLeft: 1) == "1 day left in your free week")
        #expect(FreeWeekBanner.message(daysLeft: 0) == "Your free week ends today")
    }

    @Test("Paywall price wording")
    func paywallPrice() {
        #expect(PaywallView.periodText(value: 1, unit: .month) == "1 month")
        #expect(PaywallView.periodText(value: 2, unit: .week) == "2 weeks")
        #expect(PaywallView.priceTerms(price: "$4.99", trialPeriod: "1 month") == "1 month free, then $4.99/month")
        #expect(PaywallView.priceTerms(price: "$4.99", trialPeriod: nil) == "$4.99/month")
    }

    @Test("Refused purchases show the server's reason")
    func purchaseRefusal() throws {
        let url = URL(string: "https://example.com/api/payments/apple/sync")!
        let body = Data(#"{"success":false,"error":"This App Store subscription is already used by another PlotLine account."}"#.utf8)
        let conflict = HTTPURLResponse(url: url, statusCode: 409, httpVersion: nil, headerFields: nil)!
        #expect(PaymentAPI.refusal(body, conflict)?.errorDescription?.contains("another PlotLine account") == true)

        let serverError = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        #expect(PaymentAPI.refusal(body, serverError) == nil)
    }
}
