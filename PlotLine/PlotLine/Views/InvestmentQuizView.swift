//
//  InvestmentQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//
//  Stocks → the quiz for the tab it was opened from. Both quizzes ask about you (age, experience,
//  how you'd react to a drop, how hands-on, ESG); the Roth IRA quiz asks about retirement, the
//  yearly limit and a workplace match, the Brokerage quiz about what the money is for, when, and
//  your tax bracket. What PlotLine already knows (budget, budget quiz, Plan) is shown and used, and
//  last time's answers are filled in.
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct InvestmentQuizView: View {
    enum InvestmentAccount: String, CaseIterable, Identifiable {
        case brokerage = "Brokerage"
        case rothIRA = "Roth IRA"
        var id: String { rawValue }
        var apiValue: String { self == .brokerage ? "BROKERAGE" : "ROTH_IRA" }
    }

    /// the Stocks tab the quiz was opened from
    let account: InvestmentAccount
    // Sometimes pie chart wont refresh
    var onFinish: (() -> Void)? = nil

    init(account: InvestmentAccount, onFinish: (() -> Void)? = nil) {
        self.account = account
        self.onFinish = onFinish
    }

    @State private var answers = InvestingAnswers()
    @State private var facts: InvestingFacts?
    /// a linked emergency-fund account's balance (the server can't see it)
    @State private var linkedEmergency: Double?
    /// couldn't load them (an older server, no connection): the quiz still works without them
    @State private var factsFailed = false

    @State private var quizCompleted = false
    @State private var llmRecommendation: String? = nil
    @Environment(\.dismiss) var dismiss

    @State private var showBudgetMissingAlert = false
    @State private var aiLimitMessage: String?

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    // For Calander
    @EnvironmentObject var calendarViewModel: CalendarViewModel

    private var isRoth: Bool { account == .rothIRA }

    var body: some View {
        VStack {
            if let recommendation = llmRecommendation {
                ScrollView {
                    Text("Your AI-Powered Portfolio")
                        .font(.title2)
                        .bold()
                        .padding(.bottom)
                    Text(recommendation)
                        .font(.body)
                        .padding()
                    Button("Back to Stocks Page") {
                        onFinish?()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if quizCompleted {
                ProgressView("Building your \(account.rawValue) portfolio...")
                    .task { await generatePortfolioFromLLM() }
            } else {
                questions
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(account.rawValue) Quiz").font(.headline)
            }
        }
        .tint(PLColor.accent)
        .task { await loadFacts() }
        .alert("Daily AI limit reached", isPresented: Binding(
            get: { aiLimitMessage != nil },
            set: { if !$0 { aiLimitMessage = nil } })) {
            // back to the quiz instead of the "Generating..." spinner
            Button("OK", role: .cancel) { quizCompleted = false }
        } message: {
            Text(aiLimitMessage ?? "")
        }
        .alert("Add to Budget First", isPresented: $showBudgetMissingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a monthly amount for “\(account.rawValue)” in your Budget first, so the portfolio knows how much to invest.")
        }
    }

    // MARK: - Questions

    private var questions: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                knownCard

                PLSectionHeader(title: "About you")
                card(title: "Age") {
                    TextField("Your age", text: $answers.age)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                card(title: "Investing experience") {
                    Picker("", selection: $answers.experience) {
                        ForEach(InvestingAnswers.experiences, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                card(title: "If this account dropped 20% in a month, you'd…",
                     note: "The best sign of how much ups and downs you can live with.") {
                    choices(InvestingAnswers.dropReactions, selection: $answers.dropReaction)
                }
                card(title: "How hands-on do you want to be?") {
                    choices(InvestingAnswers.styles(for: account), selection: $answers.style)
                }
                card(title: "Values") {
                    Toggle("Prefer ESG funds (environmental, social, governance)", isOn: $answers.esg)
                }

                if isRoth { rothQuestions } else { brokerageQuestions }

                Button("Build My \(account.rawValue) Portfolio") {
                    hideKeyboard()
                    if let facts, !factsFailed, facts.monthlyAmount <= 0 {
                        showBudgetMissingAlert = true
                    } else {
                        quizCompleted = true
                    }
                }
                .buttonStyle(PrimaryButton())
                .disabled(!answers.isComplete(for: account))

                let missing = answers.missing(for: account)
                if !missing.isEmpty {
                    Text("Still to answer: \(missing.joined(separator: ", ")).")
                        .font(.footnote).foregroundColor(PLColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // the number pads have no return key
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }

    @ViewBuilder private var rothQuestions: some View {
        PLSectionHeader(title: "Your Roth IRA")
        card(title: "When do you want to retire?") {
            Picker("Retire at", selection: $answers.retireAge) {
                ForEach(InvestingAnswers.retireAges, id: \.self) { Text("Age \($0)").tag($0) }
            }
            .pickerStyle(.menu)
            if let age = Int(answers.age), answers.retireAge > age {
                Text("About \(answers.retireAge - age) years from now: that sets how much growth vs. safety.")
                    .font(.footnote).foregroundColor(PLColor.textSecondary)
            }
        }
        card(title: "How do you file taxes?",
             note: "Roth IRAs have an income limit, and it depends on this.") {
            Picker("", selection: $answers.filingStatus) {
                ForEach(InvestingAnswers.filingStatuses, id: \.value) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.segmented)
        }
        card(title: "Already put in this year (optional)") {
            TextField("$0", text: $answers.contributedThisYear)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            if let ira = facts?.ira {
                Text("You can add \(answers.rothRoom(ira).dollars()) more in \(String(ira.year)) (the limit is \(ira.limit.dollars())\((Int(answers.age) ?? 0) >= ira.catchUpAge ? ", plus \(ira.catchUp.dollars()) at \(ira.catchUpAge)+" : "")).")
                    .font(.footnote).foregroundColor(PLColor.textSecondary)
            }
        }
        card(title: "Does your job offer a 401(k)?",
             note: "A 401(k) match is free money, so it usually comes before a Roth IRA.") {
            choices(InvestingAnswers.workplacePlans, selection: $answers.workplacePlan)
        }
        card(title: "Might you take money out before retirement?",
             note: "What you put in can come out anytime. Earnings taken out before 59½ are usually taxed plus a 10% penalty.") {
            Picker("", selection: $answers.earlyAccess) {
                ForEach(InvestingAnswers.earlyAccesses, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var brokerageQuestions: some View {
        PLSectionHeader(title: "Your Brokerage account")
        card(title: "What's this money for?") {
            choices(InvestingAnswers.purposes, selection: $answers.purpose)
        }
        card(title: "When will you need it?",
             note: "Money you need within a few years should stay mostly safe.") {
            Picker("", selection: $answers.horizon) {
                ForEach(InvestingAnswers.horizons, id: \.value) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.segmented)
        }
        card(title: "Federal tax bracket",
             note: facts?.federalBracket.map { "About \($0)%, estimated from the salary in your budget quiz (single filer)." }
                ?? "Brokerage gains and dividends are taxed, so your bracket picks the most tax-efficient funds.") {
            Picker("", selection: $answers.taxBracket) {
                ForEach(InvestingAnswers.taxBrackets, id: \.value) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// what PlotLine already knows and uses
    @ViewBuilder private var knownCard: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Text("What PlotLine already knows").font(.headline)
            if factsFailed {
                Text("Couldn't load your budget and Plan right now. Your answers still work.")
                    .font(.subheadline).foregroundColor(PLColor.textSecondary)
            } else if let f = facts {
                known("dollarsign.circle", f.monthlyAmount > 0
                      ? "\(f.monthlyAmount.dollars()) a month from your budget's “\(account.rawValue)” line"
                      : "No “\(account.rawValue)” line in your budget yet. Add one first.",
                      warn: f.monthlyAmount <= 0)
                if let income = f.yearlyIncome {
                    known("briefcase", "\(income.dollars()) salary" + (f.k401Yearly > 0 ? ", \((f.k401Yearly / 12).dollars()) a month into your 401(k)" : ""))
                }
                if let saved = linkedEmergency ?? (f.emergencySaved >= 0 ? f.emergencySaved : nil), f.emergencyTarget > 0 {
                    known("cross.case", saved >= f.emergencyTarget
                          ? "Emergency fund is full (\(saved.dollars()))"
                          : "Emergency fund: \(saved.dollars()) of \(f.emergencyTarget.dollars())", warn: saved < f.emergencyTarget)
                }
                if let debt = f.highInterestDebts.first {
                    known("creditcard", "\(debt.name) at \(debt.apr.formatted())% interest", warn: true)
                }
                if !f.otherHoldings.isEmpty {
                    known("chart.pie", "Your \(isRoth ? "Brokerage" : "Roth IRA") holds \(f.otherHoldings.joined(separator: ", ")). This portfolio works with it.")
                }
                Text("Your answers and these are used to build the portfolio, along with tips on what to do first.")
                    .font(.footnote).foregroundColor(PLColor.textSecondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    private func known(_ icon: String, _ text: String, warn: Bool = false) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundColor(warn ? PLColor.warning : PLColor.tint)
                .frame(width: 24)   // the text lines up whatever the icon's width
        }
    }

    private func card<Content: View>(title: String, note: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Text(title).font(.headline)
            content()
            if let note {
                Text(note).font(.footnote).foregroundColor(PLColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    /// a short list of full-sentence options, one tap each
    private func choices(_ options: [(value: String, title: String)], selection: Binding<String>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { Divider() }
                Button {
                    selection.wrappedValue = option.value
                } label: {
                    HStack {
                        Text(option.title).foregroundColor(.primary).multilineTextAlignment(.leading)
                        Spacer()
                        if selection.wrappedValue == option.value {
                            Image(systemName: "checkmark").foregroundColor(PLColor.tint)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func hideKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }

    // MARK: - Loading and sending

    private func loadFacts() async {
        guard facts == nil else { return }
        guard let loaded = try? await PlanAPI.fetchInvestingFacts(account: account.apiValue) else {
            factsFailed = true
            facts = InvestingFacts()
            return
        }
        answers.prefill(from: loaded)
        facts = loaded
        // a linked emergency fund: the bank balance is what's saved
        if loaded.emergencySaved < 0, let plan = try? await PlanAPI.fetchPlan(), let id = plan.emergencyFund.linkedAccountId,
           let accounts = try? await PlanAPI.fetchAccounts() {
            linkedEmergency = accounts.compactMap(LinkedBalance.init).first { $0.id == id }?.balance
        }
    }

    func generatePortfolioFromLLM() async {
        let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/portfolio")!
        let payload = answers.payload(username: username, account: account, emergencySaved: linkedEmergency)
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let limit = AILimitError.from(data, response) {
                aiLimitMessage = limit.message
                return
            }
            // only a successful answer is a portfolio (an error body must not be saved as one)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                AppBanner.report("build your portfolio", URLError(.badServerResponse))
                quizCompleted = false
                return
            }
            if let recommendation = String(data: data, encoding: .utf8) {
                savePortfolioToBackend(recommendation)
            }
        } catch {
            AppBanner.report("build your portfolio", error)
            quizCompleted = false
        }
    }

    func savePortfolioToBackend(_ recommendation: String) {
        let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/save-original")!
        let payload: [String: String] = [
            "username": username,
            "portfolio": recommendation,
            "riskTolerance": answers.riskTolerance,
            "account": account.apiValue
        ]
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task {
                    calendarViewModel.addMonthlyInvestmentReminder(dayOfMonth: 1)
                    await NotificationPermission.ensure(for: "your monthly investing reminder")
                }
                onFinish?()  // Notifies StockView to refresh and pops view
                dismiss()    // Navigates back
            }
        }.resume()
    }
}

#Preview {
    NavigationStack { InvestmentQuizView(account: .rothIRA) }
        .environmentObject(CalendarViewModel())
}
