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
                                  k401Percent: number(json["401(k) Contribution"]))
        for item in json["debts"] as? [[String: Any]] ?? [] {
            guard let balance = number(item["principal"]), balance > 0 else { continue }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Debt"
            answers.debts.append(Debt(name: name, balance: balance, apr: number(item["apr"]) ?? 0,
                                      minPayment: number(item["minMonthly"]) ?? max(25, balance * 0.02)))
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

    static func states() async throws -> [TaxState] {
        let data = try await load(request("/api/tools/states")) ?? Data("[]".utf8)
        return try JSONDecoder().decode([TaxState].self, from: data)
    }
}
