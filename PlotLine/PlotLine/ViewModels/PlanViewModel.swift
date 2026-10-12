//
//  PlanViewModel.swift
//  PlotLine
//
//  Budget → Plan: loads the plan, linked balances, the monthly budget and the quiz answers, and
//  saves changes (shortly after the last one, so typing doesn't send a request per keystroke).
//

import SwiftUI

@MainActor
final class PlanViewModel: ObservableObject {
    @Published var plan = Plan()
    @Published private(set) var accounts: [PlaidAccount] = []
    @Published private(set) var monthlyBudget: [String: Double]?
    @Published private(set) var quiz: QuizAnswers?
    @Published private(set) var loaded = false
    @Published private(set) var loadFailed = false

    private var saveTask: Task<Void, Never>?

    init() { }

    /// already loaded, for previews and screenshots
    init(preview plan: Plan, accounts: [PlaidAccount] = [], monthlyBudget: [String: Double]? = nil, quiz: QuizAnswers? = nil) {
        self.plan = plan
        self.accounts = accounts
        self.monthlyBudget = monthlyBudget
        self.quiz = quiz
        self.loaded = true
    }

    func load() async {
        do {
            async let plan = PlanAPI.fetchPlan()
            async let accounts = PlanAPI.fetchAccounts()
            async let budget = PlanAPI.fetchMonthlyBudget()
            async let quiz = PlanAPI.fetchQuiz()
            self.plan = try await plan
            // the rest are extras: the plan still works without them
            self.accounts = (try? await accounts) ?? []
            self.monthlyBudget = try? await budget
            self.quiz = try? await quiz
            loaded = true
            loadFailed = false
        } catch {
            loadFailed = !loaded
            AppBanner.report("load your plan", error, retry: { [weak self] in Task { await self?.load() } })
        }
    }

    /// change the plan; saved a moment after the last change
    func update(_ change: (inout Plan) -> Void) {
        guard loaded else { return } // never overwrite a plan that didn't load
        change(&plan)
        saveTask?.cancel()
        let snapshot = plan
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await PlanAPI.savePlan(snapshot)
            } catch {
                AppBanner.report("save your plan", error, retry: { [weak self] in self?.update { _ in } })
            }
        }
    }

    // MARK: - Linked accounts

    var linked: [LinkedBalance] { accounts.compactMap(LinkedBalance.init) }

    /// accounts money can be saved in (checking, savings)
    var savingsAccounts: [LinkedBalance] { linked.filter { $0.kind == .cash } }

    /// cards and loans a debt can follow
    var owedAccounts: [LinkedBalance] { linked.filter { $0.kind == .owed } }

    func balance(of accountId: String?) -> Double? {
        accountId.flatMap { id in linked.first { $0.id == id }?.balance }
    }

    // MARK: - Amounts

    func saved(_ goal: SavingsGoal) -> Double { balance(of: goal.linkedAccountId) ?? goal.saved }

    var emergencySaved: Double { balance(of: plan.emergencyFund.linkedAccountId) ?? plan.emergencyFund.saved }

    var monthlySpending: Double? {
        monthlyBudget.map(Plan.monthlySpending).flatMap { $0 > 0 ? $0 : nil }
    }

    var emergencyTarget: Double? {
        monthlySpending.map { $0 * Double(plan.emergencyFund.months) }
    }

    /// debts with a linked card's or loan's current balance
    var debtsNow: [Debt] {
        plan.debts.map { debt in
            var d = debt
            if let balance = balance(of: debt.linkedAccountId) { d.balance = balance }
            return d
        }
    }

    var netWorth: NetWorth { NetWorth.of(plan: plan, linked: linked) }

    /// the budget quiz's debts, offered once when the planner is empty
    var quizDebtsToOffer: [Debt] {
        guard loaded, !plan.importedQuizDebts, plan.debts.isEmpty else { return [] }
        return quiz?.debts ?? []
    }
}

extension Double {
    /// "$1,234" (whole dollars) or "$12.50"
    func dollars(cents: Bool = false) -> String {
        formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
    }
}
