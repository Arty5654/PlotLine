//
//  PlanTests.swift
//  PlotLineTests
//
//  Budget → Plan: debt payoff, savings goals, net worth, the 401(k) match and the rent check.
//

import Testing
import Foundation
@testable import PlotLine

struct DebtPayoffTests {
    private let card = Debt(id: "card", name: "Credit card", balance: 3000, apr: 24, minPayment: 90)
    private let loan = Debt(id: "loan", name: "Student loan", balance: 1000, apr: 5, minPayment: 50)

    @Test("One debt at 0%: balance ÷ payment months, no interest")
    func simple() {
        let r = DebtPayoff.simulate([Debt(id: "a", name: "A", balance: 1200, apr: 0, minPayment: 100)], extra: 0, strategy: .avalanche)
        #expect(r.months == 12)
        #expect(r.totalInterest == 0)
    }

    @Test("Interest is charged monthly: $1,000 at 12% paying $100 takes 11 months")
    func withInterest() {
        let r = DebtPayoff.simulate([Debt(id: "a", name: "A", balance: 1000, apr: 12, minPayment: 100)], extra: 0, strategy: .avalanche)
        #expect(r.months == 11)
        #expect(r.totalInterest > 55 && r.totalInterest < 60) // about $58
    }

    @Test("Avalanche pays the high-rate card first and less interest; snowball clears the small loan first")
    func strategies() {
        let avalanche = DebtPayoff.simulate([card, loan], extra: 200, strategy: .avalanche)
        let snowball = DebtPayoff.simulate([card, loan], extra: 200, strategy: .snowball)
        #expect(avalanche.order.first?.id == "card")
        #expect(snowball.order.first?.id == "loan")
        #expect(avalanche.totalInterest < snowball.totalInterest)
        // extra money and rolled-over minimums beat minimums only
        let minimums = DebtPayoff.simulate([card, loan], extra: 0, strategy: .avalanche, rollover: false)
        #expect((minimums.months ?? 999) > (avalanche.months ?? 0))
        #expect(minimums.totalInterest > avalanche.totalInterest)
    }

    @Test("A minimum that doesn't cover the interest never pays off")
    func neverPaysOff() {
        let stuck = Debt(id: "s", name: "S", balance: 10000, apr: 30, minPayment: 200) // interest is $250/month
        #expect(DebtPayoff.minimumTooLow(stuck))
        #expect(DebtPayoff.simulate([stuck], extra: 0, strategy: .avalanche).months == nil)
    }
}

struct PlanMathTests {
    @Test("Savings goal: what's left ÷ months to the date")
    func monthlyNeeded() {
        let now = Plan.day("2026-10-01")!
        let goal = SavingsGoal(name: "Japan", target: 3000, saved: 600, targetDate: "2027-10-01")
        #expect(goal.monthlyNeeded(saved: 600, now: now) == 200)
        #expect(goal.monthlyNeeded(saved: 3000, now: now) == nil)
    }

    @Test("Emergency fund uses spending from the budget, not savings or investing")
    func monthlySpending() {
        #expect(Plan.monthlySpending(budget: ["Rent": 1200, "Groceries": 400, "Savings": 500, "Roth IRA": 300]) == 1600)
    }

    @Test("Net worth: linked accounts and things you own, minus debts; a debt tied to a linked card counts once")
    func netWorth() {
        var plan = Plan()
        plan.assets = [Holding(name: "Car", value: 8000)]
        plan.debts = [Debt(name: "Student loan", balance: 20000, apr: 5, minPayment: 200),
                      Debt(name: "Visa", balance: 999, apr: 24, minPayment: 40, linkedAccountId: "visa")]
        let linked = [LinkedBalance(id: "chk", name: "Checking", kind: .cash, balance: 2500),
                      LinkedBalance(id: "visa", name: "Visa ••1234", kind: .owed, balance: 650),
                      LinkedBalance(id: "amex", name: "Amex", kind: .owed, balance: 100)]
        let worth = NetWorth.of(plan: plan, linked: linked)
        #expect(worth.total == 2500 + 8000 - 20000 - 650 - 100) // the Visa debt uses the account's $650, once
        #expect(worth.owed.count == 3)
    }

    @Test("401(k) match: free money at each contribution")
    func match() {
        let safeHarbor = MatchFormula.presets[4].formula
        #expect(safeHarbor.fullMatchPercent == 5)
        #expect(safeHarbor.employerPercent(for: 3) == 3)
        #expect(safeHarbor.employerPercent(for: 5) == 4)
        #expect(safeHarbor.employerPercent(for: 10) == 4)
        #expect(MatchFormula.presets[3].formula.employerPercent(for: 6) == 3)
    }

    @Test("Rent: 25% comfortable, 30% the usual rule, 35% tight")
    func rent() {
        #expect(RentCheck.verdict(rent: 1000, grossMonthly: 5000) == .comfortable)
        #expect(RentCheck.verdict(rent: 1500, grossMonthly: 5000) == .standard)
        #expect(RentCheck.verdict(rent: 1700, grossMonthly: 5000) == .tight)
        #expect(RentCheck.verdict(rent: 2000, grossMonthly: 5000) == .tooMuch)
    }
}
