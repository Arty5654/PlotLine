//
//  PlanAPI.swift
//  PlotLine
//
//  Requests for Budget → Plan: the saved plan, linked account balances, the monthly budget, the
//  budget quiz's answers (to fill in the calculators), and the paycheck calculator.
//

import Foundation

/// the budget quiz's answers the Plan tab can reuse
struct QuizAnswers {
    var yearlyIncome: Double?
    var state: String?
    var k401Percent: Double?
    var debts: [Debt] = []
    var monthlyNet: Double?          // take-home a month, worked out when the quiz was saved
}

/// POST budget-line: there isn't that much in Savings (or unassigned); `available` is the most it can be
struct NotEnoughInBudget: Error, Equatable {
    let available: Double
}

/// one paycheck (or a year) from the take-home calculator
struct TakeHome: Decodable, Equatable {
    struct Amounts: Decodable, Equatable {
        let gross, k401, preTaxHealth, federalTax, socialSecurity, medicare, stateTax, takeHome: Double
    }
    let year: Int
    let state: String
    let stateName: String?
    let stateNote: String?
    let payPeriods: Int
    let yearly: Amounts
    let perPaycheck: Amounts
    let k401Limit: Double
}

struct TaxState: Decodable, Identifiable, Hashable {
    let code: String
    let name: String
    let note: String?
    var id: String { code }
}

/// Budgeting → Tune your budget (see RetuneAdvisor on the server)
struct Retune: Decodable {
    struct Suggestion: Decodable, Identifiable, Equatable {
        struct Alternative: Decodable, Equatable {
            let label: String
            let message: String
            let changes: [String: Double]
        }
        let id: String
        let category: String
        let kind: String           // rebalance, partial, slowDown, lower
        let title: String
        let message: String
        let changes: [String: Double]
        let alternative: Alternative?
    }
    var bankLinked: Bool = false
    var ready: Bool = false
    var monthsUsed: [String] = []
    var warnings: [String] = []
    var suggestions: [Suggestion] = []

    enum CodingKeys: String, CodingKey { case bankLinked, ready, monthsUsed, warnings, suggestions }

    init() { }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bankLinked = (try? c.decode(Bool.self, forKey: .bankLinked)) ?? false
        ready = (try? c.decode(Bool.self, forKey: .ready)) ?? false
        monthsUsed = (try? c.decode([String].self, forKey: .monthsUsed)) ?? []
        warnings = (try? c.decode([String].self, forKey: .warnings)) ?? []
        suggestions = (try? c.decode([Suggestion].self, forKey: .suggestions)) ?? []
    }
}

enum PlanAPI {
    private static var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }

    private static func request(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: "\(BackendConfig.baseURLString)\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        BackendConfig.addApiKey(to: &request)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = 20
        return request
    }

    private static func load(_ request: URLRequest, okIfMissing: Bool = false) async throws -> Data? {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if okIfMissing && (http.statusCode == 404 || http.statusCode == 204) { return nil }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    static func fetchPlan() async throws -> Plan {
        let data = try await load(request("/api/plan/\(username)")) ?? Data("{}".utf8)
        return try JSONDecoder().decode(Plan.self, from: data)
    }

    static func savePlan(_ plan: Plan) async throws {
        _ = try await load(request("/api/plan/\(username)", method: "PUT", body: try JSONEncoder().encode(plan)))
    }

    /// "Can I afford it?": the answer for a purchase
    static func checkAfford(_ purchase: AffordRequest) async throws -> AffordResult {
        let data = try await affordCall("/api/afford/\(username)/check", body: try JSONEncoder().encode(purchase))
        return try JSONDecoder().decode(AffordResult.self, from: data)
    }

    /// "Save for it": a Plan goal funded by these cuts (budget lines), then Savings, then unassigned money
    static func saveForIt(_ purchase: AffordRequest, cuts: [String], wishlistId: String? = nil) async throws -> SaveForItResult {
        var body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(purchase)) as? [String: Any] ?? [:]
        body["cuts"] = cuts
        if let wishlistId { body["wishlistId"] = wishlistId }
        let data = try await affordCall("/api/afford/\(username)/save-for-it", body: try JSONSerialization.data(withJSONObject: body))
        return try JSONDecoder().decode(SaveForItResult.self, from: data)
    }

    /// the AI's estimate of what it costs to keep each month (counts toward the daily AI limit)
    static func estimateOngoingCosts(item: String, price: Double) async throws -> OngoingEstimate {
        let body = try JSONSerialization.data(withJSONObject: ["item": item, "price": price])
        let data = try await affordCall("/api/afford/ongoing-costs", body: body)
        return try JSONDecoder().decode(OngoingEstimate.self, from: data)
    }

    /// "I bought it": logged to today's spending; the goal and wishlist item close (the goal's cuts end)
    static func bought(goalId: String? = nil, wishlistId: String? = nil, item: String? = nil, price: Double? = nil) async throws -> BoughtResult {
        var body: [String: Any] = [:]
        if let goalId { body["goalId"] = goalId }
        if let wishlistId { body["wishlistId"] = wishlistId }
        if let item { body["item"] = item }
        if let price { body["price"] = price }
        let data = try await affordCall("/api/afford/\(username)/bought", body: try JSONSerialization.data(withJSONObject: body))
        return try JSONDecoder().decode(BoughtResult.self, from: data)
    }

    /// a POST whose error body ({error}) is shown as is
    private static func affordCall(_ path: String, body: Data) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "POST", body: body))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            struct Body: Decodable { let error: String? }
            if let message = (try? JSONDecoder().decode(Body.self, from: data))?.error { throw AffordError(message: message) }
            if let limit = AILimitError.from(data, response) { throw AffordError(message: limit.message) }
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// what the investing quiz fills in for an account ("BROKERAGE" / "ROTH_IRA")
    static func fetchInvestingFacts(account: String) async throws -> InvestingFacts {
        let data = try await load(request("/api/llm/portfolio/quiz/\(username)?account=\(account)")) ?? Data("{}".utf8)
        return try JSONDecoder().decode(InvestingFacts.self, from: data)
    }

    /// linked bank accounts with their balances (empty when none are linked)
    static func fetchAccounts() async throws -> [PlaidAccount] {
        guard let data = try await load(request("/api/plaid/accounts?username=\(username)"), okIfMissing: true) else { return [] }
        return try JSONDecoder().decode([PlaidAccount].self, from: data)
    }

    /// the monthly budget by category (nil before the budget quiz)
    static func fetchMonthlyBudget() async throws -> [String: Double]? {
        guard let data = try await load(request("/api/budget/\(username)/monthly"), okIfMissing: true) else { return nil }
        struct Wrapped: Decodable { let budget: [String: Double]? }
        return try JSONDecoder().decode(Wrapped.self, from: data).budget
    }

    /// what the budget quiz was told (nil before the quiz)
    static func fetchQuiz() async throws -> QuizAnswers? {
        guard let data = try await load(request("/api/llm/budget/last/\(username)"), okIfMissing: true),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], !json.isEmpty else { return nil }
        return quizAnswers(json)
    }

    static func quizAnswers(_ json: [String: Any]) -> QuizAnswers {
        func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: "")) }
            return nil
        }
        var answers = QuizAnswers(yearlyIncome: number(json["yearlyIncome"]),
                                  state: json["state"] as? String,
                                  k401Percent: number(json["401(k) Contribution"]),
                                  monthlyNet: number(json["monthlyNet"]))
        for item in json["debts"] as? [[String: Any]] ?? [] {
            guard let balance = number(item["principal"]), balance > 0 else { continue }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Debt"
            // the quiz saves "minPayment" (older ones: "minMonthly")
            let minimum = number(item["minPayment"]) ?? number(item["minMonthly"])
            answers.debts.append(Debt(name: name, balance: balance, apr: number(item["apr"]) ?? 0,
                                      minPayment: minimum.flatMap { $0 > 0 ? $0 : nil } ?? max(25, balance * 0.02)))
        }
        return answers
    }

    static func takeHome(salary: Double, state: String?, k401Percent: Double, preTaxHealthYearly: Double,
                         payPeriods: Int) async throws -> TakeHome {
        var body: [String: Any] = ["salary": salary, "k401Percent": k401Percent,
                                   "preTaxHealth": preTaxHealthYearly, "payPeriods": payPeriods]
        if let state { body["state"] = state }
        let data = try await load(request("/api/tools/take-home", method: "POST",
                                          body: try JSONSerialization.data(withJSONObject: body))) ?? Data()
        return try JSONDecoder().decode(TakeHome.self, from: data)
    }

    /// the prices a commute estimate needs (see CommutePrices on the server): {"gas": {"pricePerGallon": 3.19}, ...}
    static func commutePrices(mode: CommuteMode, homeState: String, homeCity: String, workPlace: String,
                              electric: Bool, routeHasTolls: Bool) async throws -> [String: [String: Double]] {
        let body: [String: Any] = ["mode": mode.rawValue, "homeState": homeState, "homeCity": homeCity,
                                   "workPlace": workPlace, "electric": electric, "routeHasTolls": routeHasTolls]
        let request = try request("/api/tools/commute-prices", method: "POST", body: try JSONSerialization.data(withJSONObject: body))
        let (data, response) = try await URLSession.shared.data(for: request)
        if let limit = AILimitError.from(data, response) { throw limit }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([String: [String: Double]].self, from: data)
    }

    // MARK: - Tune the budget

    static func retune() async throws -> Retune {
        let data = try await load(request("/api/budget/\(username)/retune")) ?? Data("{}".utf8)
        return try JSONDecoder().decode(Retune.self, from: data)
    }

    static func applyRetune(_ changes: [String: Double]) async throws {
        _ = try await load(request("/api/budget/\(username)/retune/apply", method: "POST",
                                   body: try JSONEncoder().encode(["changes": changes])))
    }

    /// what the budget puts toward the emergency fund or a goal each month ("Emergency Fund",
    /// "Savings - Trip"): more comes from `from` (default Savings, then money not assigned yet), less
    /// goes back to Savings. Returns the updated monthly budget.
    @discardableResult
    static func setBudgetLine(_ line: String, amount: Double, from: String? = nil) async throws -> [String: Double] {
        var body: [String: Any] = ["line": line, "amount": amount.rounded()]
        if let from { body["from"] = from }
        let req = try request("/api/plan/\(username)/budget-line", method: "POST", body: try JSONSerialization.data(withJSONObject: body))
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 409, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            throw NotEnoughInBudget(available: (json["available"] as? NSNumber)?.doubleValue ?? 0)
        }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        struct Wrapped: Decodable { let budget: [String: Double] }
        return try JSONDecoder().decode(Wrapped.self, from: data).budget
    }

    static func states() async throws -> [TaxState] {
        let data = try await load(request("/api/tools/states")) ?? Data("[]".utf8)
        return try JSONDecoder().decode([TaxState].self, from: data)
    }
}
