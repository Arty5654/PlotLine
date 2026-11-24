//
//  BudgetReview.swift
//  PlotLine
//
//  The checks on the review screen after the quiz builds a budget: needs / wants / savings,
//  housing and savings as a share of take-home, warnings, and Rebalance. Nothing here saves anything.
//

import Foundation

enum BudgetLineKind: String, CaseIterable {
    case need = "Needs", want = "Wants", saving = "Savings & investing"
}

enum BudgetReview {

    static let savingCategories: Set<String> = ["savings", "brokerage", "roth ira", "emergency fund", "investments",
                                                "investing", "401k", "401k contribution", "401(k) contribution"]
    static let needCategories: Set<String> = ["rent", "mortgage", "utilities", "internet", "phone", "groceries", "transportation",
                                              "commute", "gas", "car insurance", "car payment", "health insurance", "insurance",
                                              "renters insurance", "medical", "childcare", "parking", "tolls", "dental", "vision",
                                              "pet care", "baby supplies", "education", "car registration", "car maintenance",
                                              "mortgage", "insurance", "taxes & fees"]
    static let housingCategories: Set<String> = ["rent", "mortgage", "utilities", "renters insurance"]

    static func kind(of category: String) -> BudgetLineKind {
        let key = category.lowercased().trimmingCharacters(in: .whitespaces)
        if savingCategories.contains(key) || BudgetLine.isPlanSaving(category) { return .saving }
        if needCategories.contains(key) || key.hasPrefix("debt - ") { return .need }
        return .want
    }

    struct Summary: Equatable {
        var takeHome: Double
        var total: Double
        var byKind: [BudgetLineKind: Double]
        var housing: Double

        var unassigned: Double { takeHome - total }
        func share(_ amount: Double) -> Double { takeHome > 0 ? amount / takeHome : 0 }
        var savingsShare: Double { share(byKind[.saving] ?? 0) }
        var housingShare: Double { share(housing) }
    }

    static func summary(_ budget: [String: Double], takeHome: Double) -> Summary {
        var byKind: [BudgetLineKind: Double] = [:]
        var housing = 0.0
        for (category, amount) in budget {
            byKind[kind(of: category), default: 0] += amount
            if housingCategories.contains(category.lowercased()) { housing += amount }
        }
        return Summary(takeHome: takeHome, total: budget.values.reduce(0, +), byKind: byKind, housing: housing)
    }

    struct Warning: Equatable, Identifiable {
        var id: String { text }
        let text: String
        let severe: Bool
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    static func warnings(_ s: Summary, style: BudgetingStyleChoice, savePercent: Double) -> [Warning] {
        var out: [Warning] = []
        guard s.takeHome > 0 else { return out }
        if s.unassigned < -0.5 {
            out.append(Warning(text: "This plans \((-s.unassigned).dollars()) more than you bring home each month.", severe: true))
        }
        if s.housingShare > 0.35 {
            out.append(Warning(text: "Housing is \(percent(s.housingShare)) of your take-home (aim for about 30–35%).", severe: false))
        }
        let savingsGoal: Double? = switch style {
        case .fiftyThirtyTwenty: 0.20
        case .payYourselfFirst: savePercent / 100
        default: nil
        }
        if let savingsGoal, s.savingsShare + 0.005 < savingsGoal {
            out.append(Warning(text: "You're saving \(percent(s.savingsShare)); your plan is \(percent(savingsGoal)).", severe: false))
        } else if savingsGoal == nil, s.savingsShare < 0.10 {
            out.append(Warning(text: "You're saving \(percent(s.savingsShare)). 10–20% is a common goal.", severe: false))
        }
        if style == .fiftyThirtyTwenty {
            let needs = s.share(s.byKind[.need] ?? 0), wants = s.share(s.byKind[.want] ?? 0)
            if needs > 0.55 { out.append(Warning(text: "Needs are \(percent(needs)) (50/30/20 aims for 50%).", severe: false)) }
            if wants > 0.35 { out.append(Warning(text: "Wants are \(percent(wants)) (50/30/20 aims for 30%).", severe: false)) }
        }
        if style == .everyDollar, s.unassigned >= 1 {
            out.append(Warning(text: "\(s.unassigned.dollars()) isn't assigned yet.", severe: false))
        }
        return out
    }

    // MARK: - Rebalance

    /// how low Rebalance may take savings: the plan's share (pay yourself first, 50/30/20), else nothing
    static func savingsFloor(style: BudgetingStyleChoice, savePercent: Double, takeHome: Double) -> Double {
        switch style {
        case .payYourselfFirst: return takeHome * savePercent / 100
        case .fiftyThirtyTwenty: return takeHome * 0.20
        default: return 0
        }
    }

    struct Rebalanced: Equatable {
        var budget: [String: Double]
        /// still more than take-home: the locked lines alone are too much
        var stillOver: Double
    }

    /// Fits the budget to take-home without touching `locked` lines (the ones they changed, bills,
    /// debt minimums) or needs: over → wants are trimmed evenly first, then savings down to
    /// `savingsFloor`; under → what's left goes to Savings. Whole dollars.
    static func rebalance(_ budget: [String: Double], takeHome: Double, locked: Set<String>, savingsFloor: Double) -> Rebalanced {
        var out = budget
        let total = budget.values.reduce(0, +)
        guard takeHome > 0 else { return Rebalanced(budget: out, stillOver: 0) }

        if total > takeHome {
            var need = total - takeHome
            // trims these lines evenly by up to `available`; returns how much came off
            func trim(_ lines: [String], available: Double) -> Double {
                let pool = lines.map { out[$0] ?? 0 }.reduce(0, +)
                guard pool > 0, available > 0, need > 0 else { return 0 }
                let target = min(need, available)
                var cut = 0.0
                for line in lines {
                    let amount = out[line] ?? 0
                    let reduced = max(0, (amount - amount / pool * target).rounded(.down))
                    cut += amount - reduced
                    out[line] = reduced
                }
                return cut
            }
            let wants = budget.keys.filter { kind(of: $0) == .want && !locked.contains($0) }.sorted()
            let wantsCut = trim(wants, available: wants.map { out[$0] ?? 0 }.reduce(0, +)) // separate: trim reads `need`
            need -= wantsCut
            let savings = budget.keys.filter { kind(of: $0) == .saving && !locked.contains($0) }.sorted()
            let savingsNow = savings.map { out[$0] ?? 0 }.reduce(0, +)
            let savingsCut = trim(savings, available: max(0, savingsNow - savingsFloor))
            need -= savingsCut
            return Rebalanced(budget: out, stillOver: max(0, need.rounded()))
        }

        let left = (takeHome - total).rounded(.down)
        if left >= 1 {
            // into Savings, or another savings line when Savings is locked
            let target = !locked.contains("Savings") ? "Savings"
                : budget.keys.filter { kind(of: $0) == .saving && !locked.contains($0) }.sorted().first
            if let target { out[target, default: 0] += left }
        }
        return Rebalanced(budget: out, stillOver: 0)
    }
}
