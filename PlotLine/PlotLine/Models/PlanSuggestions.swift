//
//  PlanSuggestions.swift
//  PlotLine
//
//  Budgeting → "Put your savings to work": where the budget's saving money should go, from the
//  Plan tab. A full emergency fund or a reached goal that's still budgeted gives its money to a goal
//  that's behind; money the budget doesn't assign goes to the fund, a goal or extra debt payments;
//  Savings tops up a goal that's short. Nothing changes until a suggestion is accepted.
//

import Foundation

struct PlanSuggestion: Identifiable, Equatable {
    /// a budget-line change (POST budget-line), in order: an amount set to 0 goes back to Savings first
    struct Step: Equatable {
        let line: String
        let amount: Double
        var from: String? = nil
    }

    enum Action: Equatable {
        case lines([Step])
        case extraDebt(Double)      // the payoff planner's extra each month (its budget line follows)
    }

    let id: String
    let title: String
    let message: String
    let button: String
    let action: Action
}

enum PlanSuggestions {
    static let maxShown = 3

    struct Input {
        var plan: Plan
        var budget: [String: Double]
        var emergencySaved: Double
        var emergencyTarget: Double?
        var goalSaved: [String: Double] = [:]     // by goal id (linked balances already in)
        var unassigned: Double?
        var now = Date()
    }

    private static func line(_ name: String, _ budget: [String: Double]) -> Double { BudgetLine.amount(name, in: budget) ?? 0 }

    static func make(_ input: Input) -> [PlanSuggestion] {
        guard !input.budget.isEmpty else { return [] }
        let budget = input.budget, plan = input.plan
        let fundLine = line(BudgetLine.emergencyFund, budget)
        var savings = line(BudgetLine.savings, budget)
        let fundFull = input.emergencyTarget.map { input.emergencySaved >= $0 } ?? false
        let fundNeeds = input.emergencyTarget.map { input.emergencySaved < $0 } ?? false
        func saved(_ goal: SavingsGoal) -> Double { input.goalSaved[goal.id] ?? goal.saved }
        func month(_ goal: SavingsGoal) -> String {
            goal.targetDate.flatMap(Plan.day).map { " by \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? ""
        }

        // goals short of what they need each month, nearest date first: (goal, budgeted, needed).
        // A goal gets one suggestion; each is worked out from the budget as it is now (they don't depend
        // on each other), and the list is worked out again after one is accepted.
        let behind0: [(goal: SavingsGoal, budgeted: Double, needed: Double)] = plan.savingsGoals.compactMap { goal in
            guard saved(goal) < goal.target, let needed = goal.monthlyNeeded(saved: saved(goal), now: input.now) else { return nil }
            let budgeted = line(BudgetLine.goal(goal.name), budget), need = needed.rounded(.up)
            return need - budgeted >= 5 ? (goal, budgeted, need) : nil
        }.sorted { ($0.goal.targetDate ?? "9999") < ($1.goal.targetDate ?? "9999") }
        var behind = behind0

        var out: [PlanSuggestion] = []

        /// money freed from `source` (set to 0, so it's in Savings) goes to the first goal that's behind
        func freed(_ amount: Double, from source: String) -> (steps: [PlanSuggestion.Step], to: String) {
            var steps = [PlanSuggestion.Step(line: source, amount: 0)]
            if let next = behind.first {
                let give = min(amount, next.needed - next.budgeted)
                steps.append(.init(line: BudgetLine.goal(next.goal.name), amount: next.budgeted + give))
                behind.removeFirst() // one suggestion per goal: each is worked out from the budget as it is
                return (steps, next.goal.name)
            }
            if source != BudgetLine.emergencyFund && fundNeeds {
                return (steps + [.init(line: BudgetLine.emergencyFund, amount: fundLine + amount)], "your emergency fund")
            }
            return (steps, "Savings")
        }

        if fundFull && fundLine > 0 {
            let move = freed(fundLine, from: BudgetLine.emergencyFund)
            out.append(PlanSuggestion(id: "fund-full", title: "Your emergency fund is full",
                message: "You have \(input.emergencySaved.dollars()) set aside, \(plan.emergencyFund.months) months of spending. Move its \(fundLine.dollars()) a month to \(move.to)?",
                button: "Move It", action: .lines(move.steps)))
        }

        for goal in plan.savingsGoals where saved(goal) >= goal.target {
            let budgeted = line(BudgetLine.goal(goal.name), budget)
            guard budgeted > 0 else { continue }
            let move = freed(budgeted, from: BudgetLine.goal(goal.name))
            out.append(PlanSuggestion(id: "reached:\(goal.id)", title: "You reached \(goal.name)!",
                message: "Your budget still puts \(budgeted.dollars()) a month toward it. Move that to \(move.to)?",
                button: "Move It", action: .lines(move.steps)))
        }

        if let free = input.unassigned, free >= 25 {
            if fundNeeds {
                out.append(PlanSuggestion(id: "unassigned", title: "\(free.dollars()) a month isn't assigned",
                    message: "Your budget leaves \(free.dollars()) of your take-home unassigned. Put it toward your emergency fund?",
                    button: "Add \(free.dollars())",
                    action: .lines([.init(line: BudgetLine.emergencyFund, amount: fundLine + free, from: "unassigned")])))
            } else if let next = behind.first {
                let give = min(free, next.needed - next.budgeted)
                out.append(PlanSuggestion(id: "unassigned", title: "\(free.dollars()) a month isn't assigned",
                    message: "\(next.goal.name) needs \(next.needed.dollars()) a month to be ready\(month(next.goal)). Put \(give.dollars()) of your unassigned money toward it?",
                    button: "Add \(give.dollars())",
                    action: .lines([.init(line: BudgetLine.goal(next.goal.name), amount: next.budgeted + give, from: "unassigned")])))
                behind.removeFirst()
            } else if !plan.debts.isEmpty {
                out.append(PlanSuggestion(id: "unassigned", title: "\(free.dollars()) a month isn't assigned",
                    message: "Your emergency fund and goals are on track. Put it toward your debts as an extra payment, so you're debt-free sooner?",
                    button: "Add \(free.dollars())", action: .extraDebt(plan.extraDebtPayment + free)))
            }
        }

        for item in behind where savings >= 5 {
            let give = min(item.needed - item.budgeted, savings)
            savings -= give
            out.append(PlanSuggestion(id: "behind:\(item.goal.id)", title: "\(item.goal.name) is behind",
                message: "It needs \(item.needed.dollars()) a month to be ready\(month(item.goal)); your budget gives it \(item.budgeted.dollars()). Move \(give.dollars()) from Savings?",
                button: "Move \(give.dollars())",
                action: .lines([.init(line: BudgetLine.goal(item.goal.name), amount: item.budgeted + give, from: BudgetLine.savings)])))
        }

        if fundNeeds && fundLine == 0 && savings >= 50 {
            let half = (savings / 2).rounded(.down)
            out.append(PlanSuggestion(id: "start-fund", title: "Start your emergency fund",
                message: "Nothing in your budget goes to it yet. Move \(half.dollars()) a month from Savings, so a surprise bill doesn't go on a card?",
                button: "Move \(half.dollars())",
                action: .lines([.init(line: BudgetLine.emergencyFund, amount: half, from: BudgetLine.savings)])))
        }
        return Array(out.prefix(maxShown))
    }
}
