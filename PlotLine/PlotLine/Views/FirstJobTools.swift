//
//  FirstJobTools.swift
//  PlotLine
//
//  Budget → Plan → First-job tools:
//   • Paycheck → take-home: 2026 federal, Social Security/Medicare and state tax (the same math as
//     the budget quiz, worked out on the server).
//   • 401(k) match explained: what the employer adds and what's left on the table.
//   • Can I afford this rent?: rent against income, by the usual rules.
//  The budget quiz's answers (salary, state, 401(k) %) fill them in.
//

import SwiftUI

enum PayFrequency: Int, CaseIterable, Identifiable {
    case weekly = 52, biweekly = 26, twiceMonthly = 24, monthly = 12
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .twiceMonthly: return "Twice a month"
        case .monthly: return "Monthly"
        }
    }
}

// MARK: - Paycheck

struct PaycheckCalculatorView: View {
    let quiz: QuizAnswers?

    @State private var salary: Double?
    @State private var hourly = false
    @State private var hourlyRate: Double?
    @State private var hoursPerWeek: Double = 40
    @State private var state: String = ""
    @State private var frequency: PayFrequency = .biweekly
    @State private var k401Percent: Double = 0
    @State private var healthPerPaycheck: Double?
    @State private var states: [TaxState] = []
    @State private var result: TakeHome?
    @State private var calculating = false
    @State private var task: Task<Void, Never>?

    private var yearlySalary: Double? {
        hourly ? hourlyRate.map { $0 * hoursPerWeek * 52 } : salary
    }

    var body: some View {
        Form {
            Section("Your pay") {
                Picker("Paid", selection: $hourly) {
                    Text("Salary").tag(false)
                    Text("Hourly").tag(true)
                }
                .pickerStyle(.segmented)
                if hourly {
                    LabeledContent("Hourly rate") {
                        TextField("$0", value: $hourlyRate, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Stepper("\(Int(hoursPerWeek)) hours a week", value: $hoursPerWeek, in: 1...80)
                } else {
                    LabeledContent("Yearly salary") {
                        TextField("$0", value: $salary, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
                Picker("Paycheck", selection: $frequency) {
                    ForEach(PayFrequency.allCases) { Text($0.title).tag($0) }
                }
                Picker("State", selection: $state) {
                    Text("Choose").tag("")
                    ForEach(states) { Text($0.name).tag($0.code) }
                }
            }

            Section {
                LabeledContent("401(k): \(k401Percent.formatted(.number.precision(.fractionLength(0))))% of pay") {
                    Stepper("", value: $k401Percent, in: 0...50, step: 1).labelsHidden()
                }
                LabeledContent("Health insurance / paycheck") {
                    TextField("$0", value: $healthPerPaycheck, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Taken out before taxes")
            } footer: {
                Text("Both lower your income tax. Health insurance through work usually lowers Social Security and Medicare too.")
            }

            if let result {
                Section {
                    HStack {
                        Text("Take-home").font(.headline)
                        Spacer()
                        Text(result.perPaycheck.takeHome.dollars(cents: true)).font(.title2.bold()).foregroundColor(PLColor.success)
                    }
                    Text("per paycheck · \(result.yearly.takeHome.dollars()) a year · \((result.yearly.takeHome / 12).dollars()) a month")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                Section("Where each paycheck goes") {
                    line("Gross pay", result.perPaycheck.gross)
                    if result.perPaycheck.k401 > 0 { line("401(k)", -result.perPaycheck.k401) }
                    if result.perPaycheck.preTaxHealth > 0 { line("Health insurance", -result.perPaycheck.preTaxHealth) }
                    line("Federal income tax", -result.perPaycheck.federalTax)
                    line("Social Security (6.2%)", -result.perPaycheck.socialSecurity)
                    line("Medicare (1.45%)", -result.perPaycheck.medicare)
                    line("\(result.stateName ?? "State") income tax", -result.perPaycheck.stateTax)
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("An estimate for a single filer with \(String(result.year)) tax rules: the standard deduction and your state's own deductions are taken off first. City and county taxes, tax credits and other deductions aren't included\(result.stateNote.map { " (\($0))" } ?? ""). Your first paychecks can differ because of how your employer withholds.")
                }
            } else if calculating {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }
        }
        .navigationTitle("Paycheck")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task {
            if states.isEmpty { states = (try? await PlanAPI.states()) ?? [] }
            if salary == nil, let income = quiz?.yearlyIncome { salary = income }
            if state.isEmpty, let quizState = quiz?.state {
                state = states.first { $0.code.caseInsensitiveCompare(quizState) == .orderedSame
                                       || $0.name.caseInsensitiveCompare(quizState) == .orderedSame }?.code ?? ""
            }
            if let k = quiz?.k401Percent, k401Percent == 0 { k401Percent = k }
            recalculate()
        }
        .onChange(of: salary) { _, _ in recalculate() }
        .onChange(of: hourly) { _, _ in recalculate() }
        .onChange(of: hourlyRate) { _, _ in recalculate() }
        .onChange(of: hoursPerWeek) { _, _ in recalculate() }
        .onChange(of: state) { _, _ in recalculate() }
        .onChange(of: frequency) { _, _ in recalculate() }
        .onChange(of: k401Percent) { _, _ in recalculate() }
        .onChange(of: healthPerPaycheck) { _, _ in recalculate() }
    }

    private func line(_ name: String, _ amount: Double) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(amount.dollars(cents: true)).monospacedDigit()
                .foregroundColor(amount < 0 ? PLColor.textSecondary : PLColor.textPrimary)
        }
    }

    /// waits for typing to pause, then asks the server
    private func recalculate() {
        task?.cancel()
        guard let yearly = yearlySalary, yearly > 0 else { result = nil; return }
        calculating = true
        let health = (healthPerPaycheck ?? 0) * Double(frequency.rawValue)
        let request = (yearly, state.isEmpty ? nil : state, k401Percent, health, frequency.rawValue)
        task = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let r = try await PlanAPI.takeHome(salary: request.0, state: request.1, k401Percent: request.2,
                                                    preTaxHealthYearly: request.3, payPeriods: request.4)
                guard !Task.isCancelled else { return }
                result = r
            } catch {
                if !Task.isCancelled { AppBanner.report("work out your take-home pay", error, retry: { recalculate() }) }
            }
            calculating = false
        }
    }
}

// MARK: - 401(k) match

struct MatchExplainerView: View {
    let quiz: QuizAnswers?

    @State private var salary: Double?
    @State private var yourPercent: Double = 3
    @State private var presetIndex = 0
    @State private var custom = false
    @State private var customRate: Double = 100
    @State private var customUpTo: Double = 4

    private static let limit2026: Double = 24_500

    private var formula: MatchFormula {
        custom ? MatchFormula(tiers: [.init(matchRate: customRate, upToPercent: customUpTo)]) : MatchFormula.presets[presetIndex].formula
    }

    var body: some View {
        Form {
            Section {
                Text("Many employers add money to your 401(k) when you do. That's the match: if your plan matches 100% up to 4% and you put in 4% of your pay, they add another 4%. It's part of your pay, and you only get it if you contribute.")
                    .font(.subheadline)
            }

            Section("Your job") {
                LabeledContent("Yearly salary") {
                    TextField("$0", value: $salary, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                Picker("Employer match", selection: $presetIndex) {
                    ForEach(Array(MatchFormula.presets.enumerated()), id: \.offset) { i, preset in
                        Text(preset.name).tag(i)
                    }
                }
                .disabled(custom)
                Toggle("Different match", isOn: $custom)
                if custom {
                    Stepper("They add \(Int(customRate))% of what you put in", value: $customRate, in: 5...200, step: 5)
                    Stepper("…on up to \(customUpTo.formatted(.number.precision(.fractionLength(0...1))))% of your pay",
                            value: $customUpTo, in: 0.5...15, step: 0.5)
                }
                Stepper("You put in \(Int(yourPercent))% of your pay", value: $yourPercent, in: 0...50)
            }

            if let salary, salary > 0 {
                let you = min(salary * yourPercent / 100, Self.limit2026)
                let them = salary * formula.employerPercent(for: yourPercent) / 100
                let fullPercent = formula.fullMatchPercent
                let fullThem = salary * formula.employerPercent(for: fullPercent) / 100
                Section("Each year") {
                    row("You put in", you)
                    row("Your employer adds", them, highlight: true)
                    row("Total into your 401(k)", you + them)
                }
                Section {
                    if yourPercent < fullPercent {
                        Label("You're leaving \((fullThem - them).dollars()) a year on the table. Put in \(fullPercent.formatted(.number.precision(.fractionLength(0...1))))% to get the whole match.",
                              systemImage: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                    } else {
                        Label("You're getting the whole match.", systemImage: "checkmark.seal.fill")
                            .foregroundColor(PLColor.success)
                    }
                    if salary * yourPercent / 100 > Self.limit2026 {
                        Text("You can put in at most \(Self.limit2026.dollars()) in 2026 (more if you're 50 or older).")
                            .font(.caption)
                    }
                } footer: {
                    Text("Good to know: your contribution comes out before income tax, so it costs less than it looks. Match money may need you to stay a few years before it's fully yours (\"vesting\"); your plan's documents say how long.")
                }
            }
        }
        .navigationTitle("401(k) Match")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if salary == nil { salary = quiz?.yearlyIncome }
            if let k = quiz?.k401Percent, k > 0 { yourPercent = k }
        }
    }

    private func row(_ name: String, _ amount: Double, highlight: Bool = false) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(amount.dollars()).monospacedDigit()
                .fontWeight(highlight ? .semibold : .regular)
                .foregroundColor(highlight ? PLColor.success : PLColor.textPrimary)
        }
    }
}

// MARK: - Rent

struct RentCheckView: View {
    let quiz: QuizAnswers?

    @State private var salary: Double?
    @State private var rent: Double?
    @State private var takeHomeMonthly: Double?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Your numbers") {
                LabeledContent("Yearly salary") {
                    TextField("$0", value: $salary, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Monthly rent") {
                    TextField("$0", value: $rent, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }

            if let salary, salary > 0 {
                let gross = salary / 12
                Section("What fits") {
                    row("Comfortable (25% of pay)", gross * 0.25)
                    row("The usual rule (30%)", gross * 0.30)
                    Text("Many landlords ask for a yearly income of 40 times the rent, which is the same 30%.")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                if let rent, rent > 0 {
                    Section {
                        verdictView(RentCheck.verdict(rent: rent, grossMonthly: gross), share: rent / gross)
                        if let takeHomeMonthly {
                            row("Take-home a month", takeHomeMonthly)
                            row("Left after rent", takeHomeMonthly - rent)
                            Text("Rent is \(Int((rent / takeHomeMonthly * 100).rounded()))% of your take-home. Utilities, groceries, transport and saving come out of what's left.")
                                .font(.caption).foregroundColor(PLColor.textSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Rent Check")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if salary == nil { salary = quiz?.yearlyIncome }
            refreshTakeHome()
        }
        .onChange(of: salary) { _, _ in refreshTakeHome() }
    }

    private func verdictView(_ verdict: RentCheck.Verdict, share: Double) -> some View {
        let (title, color, icon): (String, Color, String) = switch verdict {
        case .comfortable: ("Comfortable", PLColor.success, "checkmark.seal.fill")
        case .standard: ("Doable: right at the 30% rule", PLColor.success, "checkmark.circle.fill")
        case .tight: ("Tight: more than 30% of your pay", .orange, "exclamationmark.circle.fill")
        case .tooMuch: ("Too much for this income", PLColor.danger, "xmark.octagon.fill")
        }
        return VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.headline).foregroundColor(color)
            Text("This rent is \(Int((share * 100).rounded()))% of your pay before taxes.")
                .font(.subheadline).foregroundColor(PLColor.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func row(_ name: String, _ amount: Double) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(amount.dollars()).monospacedDigit().foregroundColor(amount < 0 ? PLColor.danger : PLColor.textPrimary)
        }
    }

    /// take-home with the quiz's state and 401(k), so "left after rent" is real money
    private func refreshTakeHome() {
        task?.cancel()
        guard let salary, salary > 0 else { takeHomeMonthly = nil; return }
        let state = quiz?.state, k401 = quiz?.k401Percent ?? 0
        task = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled,
                  let r = try? await PlanAPI.takeHome(salary: salary, state: state, k401Percent: k401,
                                                      preTaxHealthYearly: 0, payPeriods: 12) else { return }
            takeHomeMonthly = r.perPaycheck.takeHome
        }
    }
}
