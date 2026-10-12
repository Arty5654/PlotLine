//
//  Plan.swift
//  PlotLine
//
//  Budget → Plan: savings goals, the emergency fund, debts for the payoff planner, and things
//  owned for net worth. Saved on the server as one document (PlanAPI); the math is here.
//

import Foundation

struct Plan: Codable, Equatable {
    var savingsGoals: [SavingsGoal] = []
    var emergencyFund = EmergencyFund()
    var debts: [Debt] = []
    var extraDebtPayment: Double = 0       // on top of the minimums, each month
    var assets: [Holding] = []             // typed in: a car, cash at home, an account that isn't linked
    var importedQuizDebts = false          // the budget quiz's debts were offered once

    init() { }

    // a plan saved by an older (or newer) app still loads
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savingsGoals = (try? c.decode([SavingsGoal].self, forKey: .savingsGoals)) ?? []
        emergencyFund = (try? c.decode(EmergencyFund.self, forKey: .emergencyFund)) ?? EmergencyFund()
        debts = (try? c.decode([Debt].self, forKey: .debts)) ?? []
        extraDebtPayment = (try? c.decode(Double.self, forKey: .extraDebtPayment)) ?? 0
        assets = (try? c.decode([Holding].self, forKey: .assets)) ?? []
        importedQuizDebts = (try? c.decode(Bool.self, forKey: .importedQuizDebts)) ?? false
    }
}

struct SavingsGoal: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var target: Double
    var saved: Double = 0                  // typed-in deposits (ignored when linked to an account)
    var targetDate: String?                // "2027-06-01"
    var linkedAccountId: String?           // a linked savings account: its balance is the saved amount

    /// how much a month to reach the target by the date (nil without a date, or once reached)
    func monthlyNeeded(saved: Double, now: Date = Date()) -> Double? {
        guard let targetDate, let date = Plan.day(targetDate), saved < target else { return nil }
        let months = max(1, Calendar.current.dateComponents([.month], from: now, to: date).month ?? 1)
        return (target - saved) / Double(months)
    }
}

struct EmergencyFund: Codable, Equatable {
    var months: Int = 3                    // months of spending to have set aside
    var saved: Double = 0
    var linkedAccountId: String?
}

struct Debt: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var balance: Double
    var apr: Double                        // percent, e.g. 5.5
    var minPayment: Double                 // per month
    var linkedAccountId: String?           // a linked card or loan: its balance is used
}

struct Holding: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var value: Double
}

extension Plan {
    static func day(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// budget lines that are saving or investing, not spending
    static let notSpending: Set<String> = ["savings", "brokerage", "roth ira", "401k contribution", "401(k) contribution",
                                           "emergency fund", "investments", "investing"]

    /// a month of spending from the monthly budget (savings and investing lines left out)
    static func monthlySpending(budget: [String: Double]) -> Double {
        budget.filter { !notSpending.contains($0.key.lowercased().trimmingCharacters(in: .whitespaces)) }
            .values.reduce(0, +)
    }
}

// MARK: - Net worth

/// A linked bank account as net worth sees it.
struct LinkedBalance: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: Kind
    let balance: Double

    enum Kind { case cash, investment, owed }

    /// Plaid's type: depository and investment accounts are owned; credit and loan accounts are owed
    init?(_ account: PlaidAccount) {
        guard let current = account.current else { return nil }
        id = account.id
        name = account.display
        balance = current
        switch account.type?.lowercased() {
        case "depository": kind = .cash
        case "investment", "brokerage": kind = .investment
        case "credit", "loan": kind = .owed
        default: return nil
        }
    }

    init(id: String, name: String, kind: Kind, balance: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.balance = balance
    }
}

struct NetWorth: Equatable {
    var owned: [(name: String, amount: Double)]
    var owed: [(name: String, amount: Double)]
    var total: Double { owned.map(\.amount).reduce(0, +) - owed.map(\.amount).reduce(0, +) }

    static func == (a: NetWorth, b: NetWorth) -> Bool { a.total == b.total && a.owned.count == b.owned.count && a.owed.count == b.owed.count }

    /// Linked accounts, plus what's typed in. A debt tied to a linked card/loan counts once (with
    /// the account's balance). Savings goals aren't added again: that money is in an account.
    static func of(plan: Plan, linked: [LinkedBalance]) -> NetWorth {
        let tiedToDebts = Set(plan.debts.compactMap(\.linkedAccountId))
        var owned: [(String, Double)] = []
        var owed: [(String, Double)] = []
        for account in linked {
            switch account.kind {
            case .cash, .investment: owned.append((account.name, account.balance))
            case .owed where !tiedToDebts.contains(account.id): owed.append((account.name, account.balance))
            case .owed: break
            }
        }
        for asset in plan.assets { owned.append((asset.name, asset.value)) }
        for debt in plan.debts {
            let balance = debt.linkedAccountId.flatMap { id in linked.first { $0.id == id }?.balance } ?? debt.balance
            owed.append((debt.name, balance))
        }
        return NetWorth(owned: owned, owed: owed)
    }
}

// MARK: - Debt payoff

enum DebtStrategy: String, CaseIterable, Identifiable {
    case avalanche, snowball
    var id: String { rawValue }
    var title: String { self == .avalanche ? "Avalanche" : "Snowball" }
    var explanation: String {
        self == .avalanche
            ? "Extra money goes to the highest interest rate first. Pays the least interest."
            : "Extra money goes to the smallest balance first. Quick wins keep you going."
    }
}

struct PayoffResult: Equatable {
    var months: Int?                       // nil: never paid off at these payments
    var totalInterest: Double
    var order: [(id: String, month: Int)]  // when each debt is paid off

    static func == (a: PayoffResult, b: PayoffResult) -> Bool {
        a.months == b.months && abs(a.totalInterest - b.totalInterest) < 0.01 && a.order.map(\.id) == b.order.map(\.id)
    }

    func payoffDate(from start: Date = Date()) -> Date? {
        months.flatMap { Calendar.current.date(byAdding: .month, value: $0, to: start) }
    }
}

enum DebtPayoff {
    static let maxMonths = 600

    /// Month by month: interest is added, every debt gets its minimum, and the extra (plus the
    /// minimums of debts already paid off) goes to the strategy's next target.
    /// `rollover: false` is "minimums only": paid-off debts' minimums aren't reused.
    static func simulate(_ debts: [Debt], extra: Double, strategy: DebtStrategy, rollover: Bool = true) -> PayoffResult {
        var balances = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, max(0, $0.balance)) })
        let monthlyBudget = debts.map(\.minPayment).reduce(0, +) + max(0, extra)
        var interestTotal = 0.0
        var order: [(String, Int)] = []
        for debt in debts where balances[debt.id, default: 0] < 0.005 { order.append((debt.id, 0)) }

        for month in 1...maxMonths {
            let open = debts.filter { balances[$0.id, default: 0] >= 0.005 }
            if open.isEmpty { return PayoffResult(months: month - 1, totalInterest: interestTotal, order: order) }

            for debt in open {
                let interest = balances[debt.id, default: 0] * debt.apr / 100 / 12
                balances[debt.id, default: 0] += interest
                interestTotal += interest
            }
            var budget = rollover ? monthlyBudget : open.map(\.minPayment).reduce(0, +) + max(0, extra)
            for debt in open {
                let pay = min(debt.minPayment, balances[debt.id, default: 0], budget)
                balances[debt.id, default: 0] -= pay
                budget -= pay
            }
            for debt in targets(open, strategy: strategy, balances: balances) where budget > 0 {
                let pay = min(budget, balances[debt.id, default: 0])
                balances[debt.id, default: 0] -= pay
                budget -= pay
            }
            for debt in open where balances[debt.id, default: 0] < 0.005 {
                balances[debt.id] = 0
                order.append((debt.id, month))
            }
        }
        let paidOff = debts.allSatisfy { balances[$0.id, default: 0] < 0.005 }
        return PayoffResult(months: paidOff ? maxMonths : nil, totalInterest: interestTotal, order: order)
    }

    /// avalanche: highest rate first (smaller balance breaks ties); snowball: smallest balance first
    static func targets(_ debts: [Debt], strategy: DebtStrategy, balances: [String: Double]) -> [Debt] {
        debts.sorted { a, b in
            let ba = balances[a.id, default: 0], bb = balances[b.id, default: 0]
            switch strategy {
            case .avalanche: return a.apr != b.apr ? a.apr > b.apr : ba < bb
            case .snowball: return ba != bb ? ba < bb : a.apr > b.apr
            }
        }
    }

    /// a debt whose minimum doesn't cover its interest never shrinks
    static func minimumTooLow(_ debt: Debt) -> Bool {
        debt.balance > 0 && debt.minPayment <= debt.balance * debt.apr / 100 / 12
    }
}

// MARK: - 401(k) match

struct MatchFormula: Equatable {
    /// "100% of the first 3%" then "50% of the next 2%"
    struct Tier: Equatable {
        var matchRate: Double      // percent of what you put in that they add (100 = dollar for dollar)
        var upToPercent: Double    // of your salary this tier covers
    }
    var tiers: [Tier]

    static let presets: [(name: String, formula: MatchFormula)] = [
        ("100% up to 3%", MatchFormula(tiers: [Tier(matchRate: 100, upToPercent: 3)])),
        ("100% up to 4%", MatchFormula(tiers: [Tier(matchRate: 100, upToPercent: 4)])),
        ("100% up to 6%", MatchFormula(tiers: [Tier(matchRate: 100, upToPercent: 6)])),
        ("50% up to 6%", MatchFormula(tiers: [Tier(matchRate: 50, upToPercent: 6)])),
        ("100% of 3% + 50% of next 2%", MatchFormula(tiers: [Tier(matchRate: 100, upToPercent: 3), Tier(matchRate: 50, upToPercent: 2)])),
    ]

    /// the contribution (% of salary) that gets the whole match
    var fullMatchPercent: Double { tiers.map(\.upToPercent).reduce(0, +) }

    /// what the employer adds, as % of salary, when you put in `percent`
    func employerPercent(for percent: Double) -> Double {
        var left = max(0, percent)
        var total = 0.0
        for tier in tiers {
            let covered = min(left, tier.upToPercent)
            total += covered * tier.matchRate / 100
            left -= covered
        }
        return total
    }
}

// MARK: - Rent

enum RentCheck {
    enum Verdict: Equatable { case comfortable, standard, tight, tooMuch }

    /// share of gross monthly income: up to 25% comfortable; 30% is the usual rule (and what a
    /// landlord's "income of 40 times the rent" works out to); up to 35% tight; more is too much
    static func verdict(rent: Double, grossMonthly: Double) -> Verdict {
        guard grossMonthly > 0 else { return .tooMuch }
        let share = rent / grossMonthly
        if share <= 0.25 { return .comfortable }
        if share <= 0.30 { return .standard }
        if share <= 0.35 { return .tight }
        return .tooMuch
    }
}
