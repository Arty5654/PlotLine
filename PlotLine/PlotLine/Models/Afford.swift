//
//  Afford.swift
//  PlotLine
//
//  Budget → Plan → "Can I afford it?": what's sent (the purchase) and what comes back (the answer,
//  where the money comes from, and a short-term cut plan). The server does the math.
//

import Foundation

struct AffordRequest: Encodable, Equatable {
    enum Payment: String, CaseIterable, Identifiable, Encodable {
        case cash, cardFull = "card-full", cardBalance = "card-balance", payIn4 = "pay-in-4"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cash: return "Cash or debit"
            case .cardFull: return "Card, paid off in full"
            case .cardBalance: return "Card, carrying a balance"
            case .payIn4: return "Pay in 4"
            }
        }
    }

    var item: String
    var price: Double
    var by: String?            // "2027-02-15" (nil: now)
    var payment: Payment = .cash
    var apr: Double = 0
    var monthly = false
    var ongoingCosts: [OngoingCost] = []   // what it costs to keep each month (included ones)
}

/// a monthly cost of owning something (a car's insurance), from the AI's estimate
struct OngoingCost: Codable, Equatable, Identifiable {
    let name: String
    let monthly: Double
    var id: String { name }
}

struct OngoingEstimate: Decodable, Equatable {
    let costs: [OngoingCost]
    let note: String
}

extension OngoingEstimate {
    /// what a wishlist item kept from an earlier estimate
    init(saved costs: [OngoingCost]) {
        self.init(costs: costs, note: costs.isEmpty ? "No real monthly costs." : "Saved with your wishlist item.")
    }
}

struct BoughtResult: Decodable, Equatable {
    let logged: Double
    let category: String
    let item: String
}

struct AffordResult: Decodable, Equatable {
    struct Source: Decodable, Equatable { let kind: String; let label: String; let amount: Double }
    struct Payment: Decodable, Equatable { let date: String; let amount: Double }
    struct Cut: Decodable, Equatable, Identifiable {
        let kind: String
        let line: String
        let label: String
        let amount: Double
        let note: String?
        let applies: Bool
        let suggested: Bool
        var name: String? = nil     // the subscription it pauses
        var id: String { kind + ":" + label }

        /// how "Save for it" names it: a subscription by name (several share one budget line), else its line
        var pick: String { kind == "subscription" ? "subscription:" + (name ?? "") : line }
    }
    struct CutPlan: Decodable, Equatable {
        let monthlyNeeded: Double
        let months: Int
        let cutsTotal: Double
        let readyBy: String?
        let cuts: [Cut]
    }

    let verdict: String          // fits | fitsIfYouSkip | fitsByDate | delaysGoal | notYet | emergencyOnly | noBudget
    let headline: String
    let detail: String
    let sources: [Source]
    let availableNow: Double
    let perMonth: Double
    let readyBy: String?         // "2027-02"
    let hoursOfWork: Double
    let interest: Double?
    let payIn4: [Payment]?
    let cutPlan: CutPlan?
    let warnings: [String]

    enum Tone { case good, okay, caution, bad }

    var tone: Tone {
        switch verdict {
        case "fits", "fitsIfYouSkip": return .good
        case "fitsByDate": return .okay
        case "emergencyOnly", "noBudget": return .bad
        default: return .caution
        }
    }

    /// money already set aside covers it now ("Save for it" is for everything else)
    var fitsNow: Bool { verdict == "fits" }

    /// when it's saved with these cuts a month ("2027-03"), starting this month (as the Plan tab dates a goal)
    func readyBy(price: Double, cutsPerMonth: Double, now: Date = Date()) -> String? {
        let pace = perMonth + cutsPerMonth
        guard pace > 0 else { return nil }
        let months = max(1, Int((price / pace).rounded(.up)))
        guard let date = Calendar.current.date(byAdding: .month, value: months, to: now) else { return nil }
        return Self.monthKey.string(from: date)
    }

    private static let monthKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// "2027-02" → "February 2027"
    static func monthName(_ key: String) -> String {
        guard let date = monthKey.date(from: key) else { return key }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

struct SaveForItResult: Decodable, Equatable {
    struct Goal: Decodable, Equatable { let name: String; let target: Double; let targetDate: String? }
    let goal: Goal
    let monthly: Double
    let readyBy: String
    var pausedSubscriptions: [String]? = nil
}

/// a server message ({error}) for a failed request
struct AffordError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
