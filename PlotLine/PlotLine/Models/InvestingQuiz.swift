//
//  InvestingQuiz.swift
//  PlotLine
//
//  Stocks → the Roth IRA and Brokerage quizzes: what PlotLine already knows (from the budget quiz,
//  the budget and the Plan), the answers (the same words the server's prompt uses), and the payload.
//

import Foundation

/// GET /api/llm/portfolio/quiz/{username}?account=: what the quiz fills in and shows
struct InvestingFacts: Codable, Equatable {
    struct Debt: Codable, Equatable { let name: String; let apr: Double; let balance: Double }
    struct Ira: Codable, Equatable {
        let year: Int
        let limit: Double
        let catchUpAge: Int
        let catchUp: Double
        let rothSingle: [Double]
        let rothJoint: [Double]
    }

    var yearlyIncome: Double?
    var k401Yearly: Double = 0
    var monthlyAmount: Double = 0           // the account's budget line
    var federalBracket: Int?                // percent, single filer
    var emergencySaved: Double = -1         // -1: a linked account holds it (the app reads its balance)
    var emergencyTarget: Double = 0
    var emergencyMonths: Int = 3
    var highInterestDebts: [Debt] = []
    var otherHoldings: [String] = []        // the other account's tickers
    var otherMonthly: Double = 0
    var answers: [String: String] = [:]     // last time's (or the other quiz's shared ones)
    var ira: Ira?

    init() { }

    // missing fields keep their defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yearlyIncome = try? c.decodeIfPresent(Double.self, forKey: .yearlyIncome)
        k401Yearly = (try? c.decodeIfPresent(Double.self, forKey: .k401Yearly)) ?? 0
        monthlyAmount = (try? c.decodeIfPresent(Double.self, forKey: .monthlyAmount)) ?? 0
        federalBracket = try? c.decodeIfPresent(Int.self, forKey: .federalBracket)
        emergencySaved = (try? c.decodeIfPresent(Double.self, forKey: .emergencySaved)) ?? -1
        emergencyTarget = (try? c.decodeIfPresent(Double.self, forKey: .emergencyTarget)) ?? 0
        emergencyMonths = (try? c.decodeIfPresent(Int.self, forKey: .emergencyMonths)) ?? 3
        highInterestDebts = (try? c.decodeIfPresent([Debt].self, forKey: .highInterestDebts)) ?? []
        otherHoldings = (try? c.decodeIfPresent([String].self, forKey: .otherHoldings)) ?? []
        otherMonthly = (try? c.decodeIfPresent(Double.self, forKey: .otherMonthly)) ?? 0
        answers = (try? c.decodeIfPresent([String: String].self, forKey: .answers)) ?? [:]
        ira = try? c.decodeIfPresent(Ira.self, forKey: .ira)
    }
}

struct InvestingAnswers: Equatable {
    typealias Account = InvestmentQuizView.InvestmentAccount

    // both quizzes
    var age = ""
    var experience = ""
    var dropReaction = ""
    var style = ""
    var esg = false
    // Roth IRA
    var retireAge = 65
    var filingStatus = ""
    var contributedThisYear = ""
    var workplacePlan = ""
    var earlyAccess = ""
    // Brokerage
    var purpose = ""
    var horizon = ""
    var taxBracket = ""

    static let experiences = ["Beginner", "Intermediate", "Advanced"]
    static let dropReactions: [(value: String, title: String)] = [
        ("Sell to stop the loss", "Sell, so I don't lose more"),
        ("Wait it out", "Wait it out"),
        ("Buy more while it's cheaper", "Buy more while it's cheaper"),
    ]
    static func styles(for account: Account) -> [(value: String, title: String)] {
        [("One fund", account == .rothIRA ? "One target-date fund: set it and forget it" : "One all-in-one fund"),
         ("A few index funds", "A few index funds"),
         ("Index funds plus some stocks", "Index funds plus a few stocks I pick")]
    }
    static let retireAges = Array(stride(from: 55, through: 70, by: 1))
    static let filingStatuses: [(value: String, title: String)] = [("Single", "Single"), ("Married filing jointly", "Married"), ("Not sure", "Not sure")]
    static let workplacePlans: [(value: String, title: String)] = [
        ("Full match", "Yes, and I get the full match"),
        ("Partial match", "Yes, but I don't get the full match yet"),
        ("No match", "Yes, with no match"),
        ("None", "No workplace plan"),
        ("Not sure", "Not sure"),
    ]
    static let earlyAccesses = ["Very unlikely", "Possibly", "Likely"]
    static let purposes: [(value: String, title: String)] = [
        ("Long-term wealth", "Grow my money long-term"),
        ("A home", "A home down payment"),
        ("A big purchase", "A big purchase (car, wedding...)"),
        ("Extra retirement", "Extra for retirement"),
        ("Dividend income", "Income from dividends"),
    ]
    static let horizons: [(value: String, title: String)] = [
        ("Under 3 years", "< 3 yrs"), ("3-5 years", "3–5"), ("5-10 years", "5–10"), ("10+ years", "10+"),
    ]
    static let taxBrackets: [(value: String, title: String)] = [("10–12%", "10–12%"), ("22–24%", "22–24%"), ("32% or more", "32%+"), ("Not sure", "Not sure")]

    static func bracketChoice(_ percent: Int) -> String {
        percent <= 12 ? "10–12%" : percent <= 24 ? "22–24%" : "32% or more"
    }

    /// Sell → Low, Wait → Medium, Buy more → High (the server and the news page use this)
    var riskTolerance: String {
        dropReaction.hasPrefix("Sell") ? "Low" : dropReaction.hasPrefix("Buy") ? "High" : "Medium"
    }

    func isComplete(for account: Account) -> Bool { missing(for: account).isEmpty }

    /// the questions still to answer, in the order they're asked
    func missing(for account: Account) -> [String] {
        var out: [String] = []
        if Int(age) == nil { out.append("age") }
        if experience.isEmpty { out.append("experience") }
        if dropReaction.isEmpty { out.append("a 20% drop") }
        if style.isEmpty { out.append("how hands-on") }
        if account == .rothIRA {
            if filingStatus.isEmpty { out.append("how you file") }
            if workplacePlan.isEmpty { out.append("your 401(k)") }
            if earlyAccess.isEmpty { out.append("taking money out early") }
        } else {
            if purpose.isEmpty { out.append("what it's for") }
            if horizon.isEmpty { out.append("when you'll need it") }
        }
        return out
    }

    /// fills what's still blank from last time's answers (and the bracket from the salary)
    mutating func prefill(from facts: InvestingFacts) {
        let a = facts.answers
        func fill(_ field: inout String, _ key: String) { if field.isEmpty, let v = a[key], !v.isEmpty { field = v } }
        fill(&age, "age"); fill(&experience, "experience"); fill(&dropReaction, "dropReaction"); fill(&style, "style")
        if a["esg"] == "Yes" { esg = true }
        if let r = a["retireAge"].flatMap(Int.init), Self.retireAges.contains(r) { retireAge = r }
        fill(&filingStatus, "filingStatus"); fill(&workplacePlan, "workplacePlan"); fill(&earlyAccess, "earlyAccess")
        fill(&purpose, "purpose"); fill(&horizon, "horizon"); fill(&taxBracket, "taxBracket")
        if taxBracket.isEmpty, let b = facts.federalBracket { taxBracket = Self.bracketChoice(b) }
        // last year's contributions don't count this year: asked fresh each time
    }

    /// POST /api/llm/portfolio (only the account's own questions)
    func payload(username: String, account: Account, emergencySaved: Double?) -> [String: String] {
        var p: [String: String] = [
            "username": username, "account": account.apiValue,
            "age": age, "experience": experience, "dropReaction": dropReaction, "style": style,
            "esg": esg ? "Yes" : "No", "riskTolerance": riskTolerance,
        ]
        if account == .rothIRA {
            p["retireAge"] = String(retireAge)
            p["filingStatus"] = filingStatus
            p["workplacePlan"] = workplacePlan
            p["earlyAccess"] = earlyAccess
            let typed = contributedThisYear.filter { $0.isNumber || $0 == "." }
            if !typed.isEmpty { p["contributedThisYear"] = typed }
        } else {
            p["purpose"] = purpose
            p["horizon"] = horizon
            p["taxBracket"] = taxBracket.isEmpty ? "Not sure" : taxBracket
        }
        if let emergencySaved { p["emergencySaved"] = String(Int(emergencySaved.rounded())) }
        return p
    }

    /// Roth IRA room left this year (the limit, plus the catch-up at 50+, minus what's in)
    func rothRoom(_ ira: InvestingFacts.Ira) -> Double {
        let limit = ira.limit + ((Int(age) ?? 0) >= ira.catchUpAge ? ira.catchUp : 0)
        return max(0, limit - (Double(contributedThisYear.filter { $0.isNumber || $0 == "." }) ?? 0))
    }
}
