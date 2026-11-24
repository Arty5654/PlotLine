//
//  PlanBudgetTests.swift
//  PlotLineTests
//
//  Budget → Plan and the budget: the Plan's budget lines, one debt list shared with the quiz,
//  the monthly savings check-in, and "Put your savings to work".
//

import Testing
import Foundation
@testable import PlotLine

private func day(monthsFromNow months: Int) -> String {
    Plan.dayKey(Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date())
}

struct PlanBudgetLineTests {
    @Test("Goal lines, the emergency fund and extra debt payments are savings; debt minimums are spending")
    func kinds() {
        let budget: [String: Double] = ["Rent": 1200, "Debt - Visa": 40, "Savings": 100, "Emergency Fund": 200,
                                        "Savings - Trip": 150, "Extra Debt Payment": 75]
        #expect(Plan.monthlySpending(budget: budget) == 1240)
        #expect(BudgetReview.kind(of: "Savings - Trip") == .saving)
        #expect(BudgetReview.kind(of: "Extra Debt Payment") == .saving)
        #expect(BudgetReview.kind(of: "Debt - Visa") == .need)
        #expect(BudgetLine.amount("savings - trip", in: budget) == 150)
        #expect(Plan.monthKey(Plan.day("2026-11-16") ?? Date()) == "2026-11")
    }

    @Test("A loan whose first payment is two months away has no budget line yet")
    func startsLater() {
        var loan = Debt(name: "Student loan", balance: 20000, apr: 5, minPayment: 200)
        #expect(!loan.startsLater())
        loan.dueDate = day(monthsFromNow: 2)
        #expect(loan.startsLater())
        loan.dueDate = Plan.dayKey(Date().addingTimeInterval(10 * 86_400))
        #expect(!loan.startsLater())
    }
}

@MainActor
struct QuizPlanDebtTests {
    @Test("The quiz shows the Plan's debts (a linked one at its balance) and the planner's extra")
    func adopt() {
        let model = BudgetQuizModel()
        model.debts = [DebtItem(name: "Old quiz debt", principal: "500")]
        var plan = Plan()
        plan.debts = [Debt(id: "d1", name: "Visa", balance: 900, apr: 24, minPayment: 40, linkedAccountId: "card"),
                      Debt(id: "d2", name: "Student loan", balance: 18000, apr: 5.5, minPayment: 200, dueDate: "2027-01-15")]
        plan.extraDebtPayment = 100
        model.setPlan(plan, balances: ["card": 650])
        #expect(model.hasDebt)
        #expect(model.debts.map(\.name) == ["Visa", "Student loan"])
        #expect(model.debts[0].principal == "650")
        #expect(model.debts[0].planId == "d1")
        #expect(model.debts[1].apr == "5.5")
        #expect(Plan.dayKey(model.debts[1].dueDate) == "2027-01-15")
        #expect(model.extraDebtPayment == "100")
        let sent = model.payload()
        #expect(sent["extraDebtPayment"] as? Double == 100)
        #expect((sent["debts"] as? [[String: Any]])?.first?["planId"] as? String == "d1")
    }

    @Test("A Plan that never had debts keeps the quiz's own (they become the Plan's on save)")
    func keepsQuizDebtsBeforeTheFirstSave() {
        let model = BudgetQuizModel()
        model.hasDebt = true
        model.debts = [DebtItem(name: "Car loan", principal: "9000")]
        model.setPlan(Plan())
        #expect(model.debts.map(\.name) == ["Car loan"])
    }

    @Test("Saving the quiz writes its debts to the Plan: ids and linked accounts kept, a blank minimum from the budget")
    func writeBack() {
        var plan = Plan()
        plan.debts = [Debt(id: "d1", name: "Visa", balance: 900, apr: 24, minPayment: 40, linkedAccountId: "card"),
                      Debt(id: "d2", name: "Old loan", balance: 100, apr: 3, minPayment: 25)]
        var visa = DebtItem(plan: plan.debts[0], balance: 650)
        visa.minPayment = "55"
        let car = DebtItem(name: "Car loan", principal: "9000", apr: "7", minPayment: "")
        let budget: [String: Double] = ["Debt - Visa": 55, "Debt - Car loan": 230, "Extra Debt Payment": 60]
        let out = BudgetQuizModel.plan(plan, withDebts: [visa, car], budget: budget)
        #expect(out.debts.count == 2)                          // the deleted one is gone
        #expect(out.debts[0].id == "d1")
        #expect(out.debts[0].balance == 900)                   // linked: follows the card, not what the quiz showed
        #expect(out.debts[0].minPayment == 55)
        #expect(out.debts[1].name == "Car loan")
        #expect(out.debts[1].balance == 9000)
        #expect(out.debts[1].minPayment == 230)                // blank: what the budget worked out
        #expect(out.debts[1].dueDate != nil)
        #expect(out.extraDebtPayment == 60)
        #expect(out.importedQuizDebts)
    }
}

@MainActor
struct SavingsCheckInTests {
    private func model() -> PlanViewModel {
        var plan = Plan()
        plan.emergencyFund = EmergencyFund(months: 3, saved: 1000)
        plan.savingsGoals = [SavingsGoal(id: "trip", name: "Trip", target: 3000, saved: 200),
                             SavingsGoal(id: "car", name: "Car", target: 9000, saved: 0, linkedAccountId: "savings-acct"),
                             SavingsGoal(id: "done", name: "Done", target: 500, saved: 500)]
        return PlanViewModel(preview: plan, monthlyBudget: ["Rent": 1500, "Groceries": 500, "Emergency Fund": 200,
                                                             "Savings - Trip": 150, "Savings - Car": 100, "Savings - Done": 50])
    }

    @Test("Each month: the fund and goals the budget funds that no linked account tracks; confirming adds them once")
    func checkIn() {
        let m = model()
        #expect(m.checkInLines.map(\.name) == ["Emergency fund", "Trip"])
        #expect(m.needsCheckIn())
        m.confirmCheckIn([PlanViewModel.CheckInLine.fundId: 200, "trip": 100])
        #expect(m.plan.emergencyFund.saved == 1200)
        #expect(m.plan.savingsGoals[0].saved == 300)
        #expect(!m.needsCheckIn())
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        #expect(m.needsCheckIn(now: nextMonth))
        m.skipCheckIn(now: nextMonth)
        #expect(!m.needsCheckIn(now: nextMonth))
        #expect(m.plan.emergencyFund.saved == 1200)
    }

    @Test("Budget amounts: the fund's pace and what's unassigned")
    func amounts() {
        let m = PlanViewModel(preview: Plan(), monthlyBudget: ["Rent": 1500, "Groceries": 500, "Emergency Fund": 500, "Savings": 300],
                              quiz: QuizAnswers(monthlyNet: 3000))
        #expect(m.emergencyTarget == 6000)
        #expect(m.emergencyMonthsToFull == 12)
        #expect(m.unassigned == 200)
        #expect(m.mostFor(BudgetLine.emergencyFund) == 1000)
    }
}

struct PlanSuggestionTests {
    private let goal = SavingsGoal(id: "trip", name: "Trip", target: 3000, saved: 0, targetDate: day(monthsFromNow: 10))

    private func input(_ budget: [String: Double], saved: Double, goals: [SavingsGoal] = [], debts: [Debt] = [],
                       unassigned: Double? = nil) -> PlanSuggestions.Input {
        var plan = Plan()
        plan.savingsGoals = goals
        plan.debts = debts
        return .init(plan: plan, budget: budget, emergencySaved: saved, emergencyTarget: 6000, unassigned: unassigned)
    }

    @Test("A full emergency fund's money goes to a goal that's behind")
    func fundFull() {
        let s = PlanSuggestions.make(input(["Rent": 2000, "Emergency Fund": 200, "Savings - Trip": 100], saved: 6500, goals: [goal]))
        #expect(s.first?.id == "fund-full")
        #expect(s.first?.message.contains("to Trip") == true)
        let need = (goal.monthlyNeeded(saved: 0) ?? 0).rounded(.up)
        #expect(s.first?.action == .lines([.init(line: "Emergency Fund", amount: 0),
                                           .init(line: "Savings - Trip", amount: min(100 + 200, need))]))
    }

    @Test("Unassigned money: the fund first, then a goal that's behind, then extra debt payments")
    func unassigned() {
        let toFund = PlanSuggestions.make(input(["Rent": 2000], saved: 1000, unassigned: 150))
        #expect(toFund.first { $0.id == "unassigned" }?.action
                == .lines([.init(line: "Emergency Fund", amount: 150, from: "unassigned")]))

        let debt = Debt(name: "Visa", balance: 900, apr: 24, minPayment: 40)
        let toDebt = PlanSuggestions.make(input(["Rent": 2000], saved: 7000, debts: [debt], unassigned: 120))
        #expect(toDebt.first { $0.id == "unassigned" }?.action == .extraDebt(120))
    }

    @Test("Savings tops up a goal that's short; a reached goal's money moves on; nothing without a budget")
    func behindAndReached() {
        let behind = PlanSuggestions.make(input(["Rent": 2000, "Savings": 400, "Emergency Fund": 100], saved: 1000, goals: [goal]))
        let need = (goal.monthlyNeeded(saved: 0) ?? 0).rounded(.up)
        #expect(behind.first { $0.id == "behind:trip" }?.action
                == .lines([.init(line: "Savings - Trip", amount: min(need, 400), from: "Savings")]))

        let done = SavingsGoal(id: "done", name: "Laptop", target: 1200, saved: 1200)
        let reached = PlanSuggestions.make(input(["Rent": 2000, "Savings - Laptop": 100], saved: 7000, goals: [done]))
        #expect(reached.first?.id == "reached:done")
        #expect(reached.first?.action == .lines([.init(line: "Savings - Laptop", amount: 0)]))

        #expect(PlanSuggestions.make(input([:], saved: 0, unassigned: 500)).isEmpty)
    }
}
