//
//  PlanViewModel.swift
//  PlotLine
//
//  Budget → Plan: loads the plan, linked balances, the monthly budget and the quiz answers, and
//  saves changes (shortly after the last one, so typing doesn't send a request per keystroke).
//  Also what the budget puts toward the emergency fund and each goal, and the monthly check-in
//  for savings that aren't in a linked account.
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
    /// previews and tests: changes stay on the phone
    private var isPreview = false

    init() { }

    /// already loaded, for previews and screenshots
    init(preview plan: Plan, accounts: [PlaidAccount] = [], monthlyBudget: [String: Double]? = nil, quiz: QuizAnswers? = nil) {
        self.plan = plan
        self.accounts = accounts
        self.monthlyBudget = monthlyBudget
        self.quiz = quiz
        self.loaded = true
        self.isPreview = true
    }

    /// `reportErrors: false` for the Budget page's summary (the Plan tab reports its own)
    func load(reportErrors: Bool = true) async {
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
            SavingsCheckInReminder.update(total: checkInLines.map(\.amount).reduce(0, +))
            WishlistReminder.update(self.plan.wishlist)
        } catch {
            loadFailed = !loaded
            if reportErrors { AppBanner.report("load your plan", error, retry: { [weak self] in Task { await self?.load() } }) }
        }
    }

    /// change the plan; saved a moment after the last change
    func update(_ change: (inout Plan) -> Void) {
        guard loaded else { return } // never overwrite a plan that didn't load
        change(&plan)
        guard !isPreview else { return }
        saveTask?.cancel()
        let snapshot = plan
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await PlanAPI.savePlan(snapshot)
                // the server keeps the budget's debt and goal lines in step: show them as they are now
                if let budget = try? await PlanAPI.fetchMonthlyBudget() { self.monthlyBudget = budget }
            } catch {
                AppBanner.report("save your plan", error, retry: { [weak self] in self?.update { _ in } })
            }
        }
    }

    /// a change waiting to be saved is saved now (before the server changes the plan itself)
    func flushSave() async {
        guard let task = saveTask, !isPreview else { return }
        task.cancel()
        saveTask = nil
        try? await PlanAPI.savePlan(plan)
    }

    // MARK: - Wishlist ("Can I afford it?" → think it over)

    /// `ongoingCosts`: the monthly costs they kept from the estimate, so reopening it needs no new AI call
    func addToWishlist(item: String, price: Double, days: Int, ongoingCosts: [OngoingCost]? = nil, now: Date = Date()) {
        let remind = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        update { $0.wishlist.append(WishItem(item: item.isEmpty ? "Something" : item, price: price,
                                             addedOn: Plan.dayKey(now), remindOn: Plan.dayKey(remind),
                                             ongoingCosts: ongoingCosts)) }
        guard !isPreview else { return }
        Task {
            _ = await NotificationPermission.ensure(for: "your wishlist reminder")
            WishlistReminder.update(plan.wishlist)
        }
    }

    func removeFromWishlist(_ id: String) {
        update { $0.wishlist.removeAll { $0.id == id } }
        if !isPreview { WishlistReminder.update(plan.wishlist) }
    }

    /// the goal a wishlist item is being saved for
    func goal(for wish: WishItem) -> SavingsGoal? {
        wish.goalId.flatMap { id in plan.savingsGoals.first { $0.id == id } }
    }

    /// "I bought it": logged to today's spending; the goal and wishlist item close (the goal's cuts end)
    func bought(goalId: String? = nil, wishlistId: String? = nil) async throws -> BoughtResult {
        await flushSave()
        let result = try await PlanAPI.bought(goalId: goalId, wishlistId: wishlistId)
        await load(reportErrors: false)
        return result
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

    // MARK: - The budget's Plan lines

    /// take-home a month (from the budget quiz)
    var monthlyNet: Double? { quiz?.monthlyNet }

    func budgetAmount(_ line: String) -> Double { BudgetLine.amount(line, in: monthlyBudget) ?? 0 }
    var emergencyBudget: Double { budgetAmount(BudgetLine.emergencyFund) }
    func budget(for goal: SavingsGoal) -> Double { budgetAmount(BudgetLine.goal(goal.name)) }
    var budgetSavings: Double { budgetAmount(BudgetLine.savings) }
    var hasBudget: Bool { !(monthlyBudget ?? [:]).isEmpty }

    /// take-home the budget doesn't hand out yet (nil when take-home isn't known)
    var unassigned: Double? {
        guard let net = monthlyNet, net > 0, let budget = monthlyBudget else { return nil }
        return max(0, (net - budget.values.reduce(0, +)).rounded(.down))
    }

    /// the most a line can be: what it has, plus Savings, plus what isn't assigned
    func mostFor(_ line: String) -> Double { budgetAmount(line) + budgetSavings + (unassigned ?? 0) }

    /// the other Plan lines with money in the budget a line can take from (the emergency fund, goals)
    func otherSources(for line: String) -> [(line: String, title: String, amount: Double)] {
        var out: [(String, String, Double)] = []
        if line != BudgetLine.emergencyFund && emergencyBudget > 0 {
            out.append((BudgetLine.emergencyFund, "Emergency fund", emergencyBudget))
        }
        for goal in plan.savingsGoals where BudgetLine.goal(goal.name) != line && budget(for: goal) > 0 {
            out.append((BudgetLine.goal(goal.name), goal.name, budget(for: goal)))
        }
        return out
    }

    /// what the budget puts toward the emergency fund or a goal each month (throws NotEnoughInBudget)
    func setBudgetLine(_ line: String, amount: Double, from: String? = nil) async throws {
        monthlyBudget = try await PlanAPI.setBudgetLine(line, amount: amount, from: from)
        SavingsCheckInReminder.update(total: checkInLines.map(\.amount).reduce(0, +))
    }

    /// months until the emergency fund is full at what the budget puts in (nil: not budgeted, or full)
    var emergencyMonthsToFull: Int? {
        guard let target = emergencyTarget, emergencySaved < target, emergencyBudget > 0 else { return nil }
        return Int(((target - emergencySaved) / emergencyBudget).rounded(.up))
    }

    // MARK: - Suggestions (Budgeting → Put your savings to work)

    var suggestions: [PlanSuggestion] {
        guard loaded, let budget = monthlyBudget else { return [] }
        return PlanSuggestions.make(.init(plan: plan, budget: budget, emergencySaved: emergencySaved,
                                          emergencyTarget: emergencyTarget,
                                          goalSaved: Dictionary(plan.savingsGoals.map { ($0.id, saved($0)) }, uniquingKeysWith: { a, _ in a }),
                                          unassigned: unassigned))
    }

    /// accepts a suggestion (each step in order; stops at the first that fails)
    func apply(_ suggestion: PlanSuggestion) async throws {
        switch suggestion.action {
        case .lines(let steps):
            for step in steps { try await setBudgetLine(step.line, amount: step.amount, from: step.from) }
        case .extraDebt(let amount):
            update { $0.extraDebtPayment = amount } // saved a moment later; the budget's line follows
        }
    }

    // MARK: - Monthly savings check-in

    /// savings the budget sets aside that no linked account tracks: confirmed once a month
    struct CheckInLine: Identifiable, Equatable {
        static let fundId = "emergency-fund"
        let id: String              // fundId, or the goal's id
        let name: String
        let amount: Double
    }

    var checkInLines: [CheckInLine] {
        var out: [CheckInLine] = []
        if plan.emergencyFund.linkedAccountId == nil, emergencyBudget > 0, emergencyTarget.map({ emergencySaved < $0 }) ?? true {
            out.append(CheckInLine(id: CheckInLine.fundId, name: "Emergency fund", amount: emergencyBudget))
        }
        for goal in plan.savingsGoals where goal.linkedAccountId == nil && goal.saved < goal.target && budget(for: goal) > 0 {
            out.append(CheckInLine(id: goal.id, name: goal.name, amount: budget(for: goal)))
        }
        return out
    }

    /// this month's savings haven't been confirmed (or skipped) yet
    func needsCheckIn(now: Date = Date()) -> Bool {
        loaded && !checkInLines.isEmpty && plan.savingsCheckIn != Plan.monthKey(now)
    }

    /// what they moved this month (by line id) is added to the fund and goals
    func confirmCheckIn(_ amounts: [String: Double], now: Date = Date()) {
        update { plan in
            for (id, amount) in amounts where amount > 0 {
                if id == CheckInLine.fundId {
                    plan.emergencyFund.saved += amount
                } else if let i = plan.savingsGoals.firstIndex(where: { $0.id == id }) {
                    plan.savingsGoals[i].saved += amount
                }
            }
            plan.savingsCheckIn = Plan.monthKey(now)
        }
    }

    func skipCheckIn(now: Date = Date()) {
        update { $0.savingsCheckIn = Plan.monthKey(now) }
    }

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
