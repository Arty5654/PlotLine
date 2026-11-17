//
//  BudgetQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 4/16/25.
//
//  The budget quiz, one short step at a time with a progress bar: link a bank (optional, so the
//  quiz starts from real spending) → where you live → pay → home → getting around → subscriptions
//  → other regular costs → once-a-year costs → debt → goals and budgeting style → categories.
//  Each step says why it's asked, and questions that don't apply are skipped. The budget is then
//  checked on the review screen (BudgetReviewView) before it's saved. Someone who took it before
//  starts with their answers filled in and can jump to the part that changed; an unfinished quiz
//  can be picked up where it was left. With a linked bank, questions the bank already answers are
//  folded away. The answers and requests live in BudgetQuizModel.
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let budgetQuizCompleted = Notification.Name("budgetQuizCompleted")
}

private let quizCommonCategories = CategoryOptions.common

struct BudgetQuizView: View {
    @StateObject private var model: BudgetQuizModel
    @StateObject private var bankLinker = BankLinker()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject private var calendarVM: CalendarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var building = false
    @State private var review: Review?
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var newSubName = ""
    @State private var newSubCost: Double?
    @State private var newSubDate = Date()
    @State private var customCategory = ""
    @State private var showCustomCategory = false
    /// an unfinished quiz from before, until they pick it up or start over
    @State private var unfinished: [String: Any]?
    /// the bank transactions being looked at ("" = all of them)
    @State private var transactionsFor: String?
    /// what each question the bank answers was before Change (for Undo); the opened ones are model.bankOverrides
    @State private var beforeChange: [String: String] = [:]

    /// the built budget waiting on the review screen
    private struct Review: Identifiable {
        let id = UUID()
        let draft: BudgetQuizModel.Draft
    }

    /// previews and screenshots: answers already filled in, nothing loaded from the server
    private let isPreview: Bool
    /// after saving, once the quiz has closed (Home opens the Budget page)
    private let onFinished: (() -> Void)?

    init(onFinished: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: BudgetQuizModel())
        isPreview = false
        self.onFinished = onFinished
    }

    init(preview: BudgetQuizModel, unfinished: [String: Any]? = nil) {
        _model = StateObject(wrappedValue: preview)
        _unfinished = State(initialValue: unfinished)
        isPreview = true
        onFinished = nil
    }

    private var steps: [QuizStep] { QuizStep.allCases }
    private var index: Int { model.step.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            ScrollView {
                VStack(alignment: .leading, spacing: PLSpacing.md) {
                    if let unfinished { resumeCard(unfinished) }
                    else if model.hasSavedQuiz && model.step == .bank { shortcuts }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.step.title).font(.title2.bold())
                        Text("Why we ask: \(model.step.why)")
                            .font(.caption).foregroundColor(PLColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    stepContent
                }
                .padding(PLSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Text("Budget Quiz").font(.headline) } }
        .tint(PLColor.accent)
        .task {
            guard !isPreview else { return }
            await model.loadSavedQuiz()
            unfinished = model.savedDraft()
            if model.hasSavedQuiz && !model.manualCity.isEmpty {
                // check where the phone is now (the saved city isn't "detected")
                model.city = ""
                model.state = ""
                locationManager.requestLocation { city, state in model.phoneLocated(city: city, state: state) }
                Task {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if model.city.isEmpty { model.phoneLocationUnavailable() } // no answer: keep the saved place
                }
            } else if model.useDeviceLocation && model.city.isEmpty {
                getLocation()
            }
            await model.checkBank()
            await model.loadSubscriptions()
            await model.loadPlan()
            // today's gas price, even if they never open the car step (the commute and other driving use it)
            if model.hasCar && model.commute.fuelPrice <= 0 && !model.finalState.isEmpty { await model.loadGasPrice() }
        }
        .onDisappear {
            // leaving partway keeps the answers (not after saving, and not while the old ones are still offered)
            if !isPreview && !saved && unfinished == nil && (index > 0 || model.bankLinked) { model.saveDraft() }
        }
        .onChange(of: model.yearlyIncome) { _, _ in model.refreshTakeHome() }
        .onChange(of: model.retirement) { _, _ in model.refreshTakeHome() }
        .onChange(of: model.finalState) { _, _ in model.refreshTakeHome() }
        .onChange(of: model.payFrequency) { _, _ in model.refreshTakeHome() }
        .onChange(of: model.insurancePerCheck) { _, _ in model.refreshTakeHome() }
        .onChange(of: model.carOwnership) { _, value in
            // no car: no car questions, no car budget lines
            if value == "No Car" {
                model.selectedCategories.subtract(BudgetQuizModel.carCategories)
                if model.commute.mode.needsCar { model.commute.mode = .transit; model.commuteEstimated = false }
            }
        }
        .onChange(of: model.step) { _, step in
            unfinished = nil // moving on without picking up the old answers starts fresh
            if !isPreview { model.saveDraft() }
            // a bank that was still sending its history when it was linked
            if step == .subscriptions || step == .otherCosts, model.bankLinked, !model.bankReady {
                Task { await model.checkBank() }
            }
        }
        .alert(errorMessage == nil ? "Couldn't build your budget" : "Daily AI limit reached", isPresented: $showError) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again in a moment.")
        }
        .sheet(isPresented: Binding(get: { transactionsFor != nil }, set: { if !$0 { transactionsFor = nil } })) {
            BankTransactionsView(model: model, category: transactionsFor ?? "")
        }
        .sheet(item: $review, onDismiss: {
            guard saved else { return }
            dismiss()
            onFinished?()
        }) { review in
            BudgetReviewView(model: model, draft: review.draft) {
                saved = true
                self.review = nil
            }
            .environmentObject(calendarVM)
        }
        .overlay {
            if building {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Building your budget…").font(.headline)
                        Text("This takes a few seconds.").font(.caption).foregroundColor(PLColor.textSecondary)
                    }
                    .padding(PLSpacing.lg)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                }
            }
        }
    }

    // MARK: - Frame

    private var progressHeader: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(index + 1), total: Double(steps.count))
            HStack {
                Text("Step \(index + 1) of \(steps.count)").font(.caption).foregroundColor(PLColor.textSecondary)
                Spacer()
                if model.hasSavedQuiz {
                    Menu {
                        ForEach(steps) { step in
                            Button(step.title) { model.step = step }
                        }
                    } label: {
                        Label("Jump to", systemImage: "list.bullet").font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .padding(.horizontal, PLSpacing.lg)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if index > 0 {
                    Button("Back") { go(to: steps[index - 1]) }
                        .buttonStyle(OutlineButton(tint: PLColor.accent))
                }
                if index < steps.count - 1 {
                    Button(model.step == .bank && !model.bankLinked ? "Skip for Now" : "Next") { go(to: steps[index + 1]) }
                        .buttonStyle(PrimaryButton())
                        .disabled(!model.canLeave(model.step))
                } else {
                    Button(buildTitle) { Task { await build() } }
                        .buttonStyle(PrimaryButton())
                        .disabled(building || !model.canBuild)
                }
            }
            // someone updating one part doesn't have to page through the rest
            if model.hasSavedQuiz && index < steps.count - 1 {
                Button(buildTitle) { Task { await build() } }
                    .font(.subheadline.weight(.semibold))
                    .disabled(building || !model.canBuild)
            }
        }
        .padding(.horizontal, PLSpacing.lg)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var buildTitle: String { model.hasSavedQuiz ? "Update My Budget" : "Build My Budget" }

    private func go(to step: QuizStep) {
        hideKeyboard()
        withAnimation { model.step = step }
    }

    private func resumeCard(_ draft: [String: Any]) -> some View {
        let saved = (draft["draftStepName"] as? String).flatMap(QuizStep.named)
            ?? QuizStep(rawValue: min((draft["draftStep"] as? NSNumber)?.intValue ?? 0, QuizStep.allCases.count - 1))
        let stepNumber = saved?.rawValue ?? 0
        let title = saved?.title ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text("Pick up where you left off?").font(.headline)
            Text("You stopped at step \(stepNumber + 1) of \(steps.count)\(title.isEmpty ? "" : " (\(title))"). Your answers are saved on this phone.")
                .font(.caption).foregroundColor(PLColor.textSecondary)
            HStack {
                Button("Continue") {
                    model.resume(draft)
                    unfinished = nil
                    if model.hasCar && model.commute.fuelPrice <= 0 { Task { await model.loadGasPrice() } }
                }
                .buttonStyle(.borderedProminent)
                Button("Start Over") {
                    model.clearDraft()
                    unfinished = nil
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    /// a bill's due day: it goes on the calendar with a reminder the day before
    private func dueDay(_ bill: String) -> some View {
        LabeledContent("\(bill) due") {
            Picker("\(bill) due", selection: Binding(get: { model.billDueDays[bill] ?? 0 },
                                                     set: { model.billDueDays[bill] = $0 == 0 ? nil : $0 })) {
                Text("Not set").tag(0)
                ForEach(1...31, id: \.self) { Text("On the \($0.ordinal)").tag($0) }
            }
        }
        .font(.subheadline)
    }

    /// one price for all driving (the commute and other driving), editable
    @ViewBuilder private var fuelPriceRow: some View {
        let electric = model.commute.car == .electric
        numberRow(electric ? "Electricity ($ per kWh)" : "Gas price ($ per gallon)", value: $model.commute.fuelPrice)
            .task(id: model.finalState) {
                guard model.commute.fuelPrice <= 0, !model.finalState.isEmpty else { return }
                await model.loadGasPrice()
            }
        Group {
            switch model.fuelPriceSource {
            case .eia:
                Text(electric ? "The latest average for your state from the U.S. Energy Information Administration. Change it if you pay more or less."
                              : "This week's average for your area from the U.S. Energy Information Administration. Change it if you pay more or less.")
            case .estimate: Text("An estimate. Change it if you know what you pay.")
            case .yours: Text("Your price.")
            case .none: Text("Looking up the price for your area…")
            }
        }
        .font(.caption2).foregroundColor(PLColor.textSecondary)
    }

    @ViewBuilder private var carInsuranceFields: some View {
        moneyField(model.carInsuranceMonths == 1 ? "Car insurance ($/month)" : "Car insurance ($ each payment)", $model.carInsurance)
        if model.carInsurance.isEmpty {
            Text("Leave blank and we'll estimate it; 0 if it's not on you.").font(.caption2).foregroundColor(PLColor.textSecondary)
        }
        LabeledContent("Car insurance paid") {
            Picker("Car insurance paid", selection: $model.carInsuranceMonths) {
                Text("Monthly").tag(1)
                Text("Every 6 months").tag(6)
                Text("Once a year").tag(12)
            }
        }
        .font(.subheadline)
        if model.carInsuranceMonths == 1 {
            dueDay("Car Insurance")
        } else {
            DatePicker("Next payment", selection: $model.carInsuranceNextDue, in: Date()..., displayedComponents: .date)
                .font(.subheadline)
            if let monthly = model.carInsuranceMonthly {
                Text("Set aside \(monthly.dollars()) a month for it.").font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    private var blankEstimates: some View {
        Text("Leave blank and we'll estimate it for your city.")
            .font(.caption2).foregroundColor(PLColor.textSecondary)
    }

    private var dueDayNote: some View {
        Text("Due dates go on your calendar, with a reminder the day before.")
            .font(.caption2).foregroundColor(PLColor.textSecondary)
    }

    /// a question the bank already answers: folded into one line until they tap Change, and Undo
    /// goes back to the bank's amount. `alwaysFold`: a choice, not an amount (eating out)
    @ViewBuilder
    private func fromBank<Content: View>(_ category: String, _ label: String, value: Binding<String>, alwaysFold: Bool = false,
                                         @ViewBuilder content: () -> Content) -> some View {
        let usual = model.bankAverage(category)
        let opened = model.bankOverrides.contains(category)
        if let usual, !opened, alwaysFold || value.wrappedValue.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline)
                    Text("\(usual.dollars())/month from your transactions\(category == "Gas" ? ", including driving to work" : "")")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                Spacer()
                Button("Change") {
                    beforeChange[category] = value.wrappedValue
                    withAnimation { _ = model.bankOverrides.insert(category) }
                }
                .font(.subheadline)
            }
        } else {
            content()
            if let usual, opened {
                HStack {
                    Text("Your transactions show \(usual.dollars())/month").font(.caption).foregroundColor(PLColor.textSecondary)
                    Spacer()
                    Button {
                        value.wrappedValue = beforeChange[category] ?? ""
                        withAnimation { _ = model.bankOverrides.remove(category) }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Update part of your budget").font(.headline)
            Text("Your last answers are filled in. Jump to what changed, then tap Update My Budget.")
                .font(.caption).foregroundColor(PLColor.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(steps.filter { $0.shortcut != nil }) { step in
                        Button(step.shortcut ?? "") { go(to: step) }
                            .buttonStyle(.bordered)
                            .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .bank: bankStep
        case .location: locationStep
        case .pay: payStep
        case .home: homeStep
        case .gettingAround: gettingAroundStep
        case .otherCosts: otherCostsStep
        case .subscriptions:
            VStack(alignment: .leading, spacing: PLSpacing.md) {
                subscriptionsStep
                yearlyStep
            }
        case .debt: debtStep
        case .goals: goalsStep
        case .categories: categoriesStep
        }
    }

    // MARK: - Fields

    /// the title shows above the field once it's filled in, so "310" still says what it is
    private func moneyField(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !text.wrappedValue.isEmpty {
                Text(title).font(.caption).foregroundColor(PLColor.textSecondary)
            }
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, v in
                    let filtered = v.filter { "0123456789.".contains($0) }
                    if filtered != v { text.wrappedValue = filtered }
                }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 110)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .plCard()
    }

    /// a menu picker with its label showing (menus outside a Form hide their label)
    private func optionPicker(_ title: String, selection: Binding<String>, _ options: [(tag: String, label: String)]) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                ForEach(options, id: \.tag) { Text($0.label).tag($0.tag) }
            }
        }
    }

    /// the label on its own line, for options too long to sit beside it
    private func stackedPicker(_ title: String, selection: Binding<String>, _ options: [(tag: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title, selection: selection) {
                ForEach(options, id: \.tag) { Text($0.label).tag($0.tag) }
            }
            .labelsHidden()
            .padding(.leading, -12) // a menu picker's own inset: line it up with the label
        }
    }

    /// tap a category to see its transactions and how each was sorted
    @ViewBuilder
    private func averagesList(limit: Int) -> some View {
        let niches = model.bankNiches
        // broad categories (with the narrower ones switched on taken out); the narrower ones sit under them
        let rows = model.sortedBankAverages.filter { !niches.contains($0.key) }.sorted { $0.value > $1.value }.prefix(limit)
        ForEach(Array(rows), id: \.key) { category, amount in
            Button {
                transactionsFor = category
            } label: {
                HStack {
                    Text(category).foregroundColor(PLColor.textPrimary)
                    Spacer()
                    Text("\(amount.dollars())/month").monospacedDigit().foregroundColor(PLColor.textPrimary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(PLColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .disabled(model.bankTransactions.isEmpty)
            ForEach(model.nichesInside(category), id: \.name) { niche in
                nicheRow(niche.name, niche.monthly)
            }
        }
        if !model.bankTransactions.isEmpty {
            Button("See all \(model.bankTransactions.count) transactions") { transactionsFor = "" }
                .font(.subheadline)
        }
    }

    /// a narrower part of the category above it (Alcohol & Bars in Eating Out): its own line, or not
    private func nicheRow(_ niche: String, _ monthly: Double) -> some View {
        Toggle(isOn: Binding(get: { model.selectedCategories.contains(niche) }, set: { model.trackSeparately(niche, $0) })) {
            HStack {
                Button {
                    transactionsFor = niche
                } label: {
                    Text(niche).foregroundColor(PLColor.textPrimary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(monthly.dollars())").monospacedDigit().foregroundColor(PLColor.textSecondary)
            }
        }
        .font(.subheadline)
        .padding(.leading, 16)
        .accessibilityHint("Track separately: its own budget line, taken out of the category above")
    }

    // MARK: - Steps

    private var bankStep: some View {
        card {
            if model.bankLinked {
                Label("Connected", systemImage: "checkmark.seal.fill").foregroundColor(PLColor.success)
                if model.checkingBank {
                    ProgressView("Reading your last few months…")
                } else if model.bankReady && !model.bankAverages.isEmpty {
                    let months = max(1, Int(model.bankMonths.rounded()))
                    Text("What you spend in a typical month (from the last \(months) month\(months == 1 ? "" : "s")). Your budget starts from these:")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                    averagesList(limit: 8)
                    if !model.bankNiches.isEmpty {
                        Text("Switch on a part (like Alcohol & Bars) to give it its own budget line; it comes out of the category above it.")
                            .font(.caption).foregroundColor(PLColor.textSecondary)
                    }
                } else if model.bankReady {
                    Text("No spending found yet in this account. You can keep going; the quiz will estimate instead.")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                } else {
                    Text("Your transactions are still coming in. Keep going; we'll check again in a few steps.")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                    Button("Check Again") { Task { await model.checkBank() } }.font(.subheadline)
                }
                Text("Nothing is added to your spending until your budget is saved.")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            } else {
                Text("Link the bank account or credit card you spend from, and the quiz starts from what you really spend (groceries, eating out, gas…) and finds your subscriptions. You can skip this.")
                    .font(.subheadline)
                Button {
                    Task { await bankLinker.link { Task { await model.checkBank() } } }
                } label: {
                    Label(bankLinker.isLinking ? "Opening…" : "Link a Bank or Card", systemImage: "building.columns")
                }
                .buttonStyle(PrimaryButton())
                .disabled(bankLinker.isLinking)
                Text("Through Plaid. PlotLine can read transactions and balances; it can't move money.")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    private var locationStep: some View {
        card {
            Toggle("Use My Location", isOn: $model.useDeviceLocation)
                .onChange(of: model.useDeviceLocation) { _, enabled in if enabled { getLocation() } }
            if model.useDeviceLocation {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                    if model.city == "Permission" {
                        Text("Location is off for PlotLine. Turn off Use My Location and type your city.")
                    } else {
                        Text(model.city.isEmpty && model.state.isEmpty ? "Detecting…" : "Detected: \(model.city), \(model.state)")
                    }
                }
                .font(.subheadline)
                .foregroundColor(PLColor.textSecondary)
            } else {
                if model.phoneElsewhere {
                    Text("Your phone is in \(model.city), \(model.state). Turn on Use My Location to use it instead.")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                TextField("City", text: $model.manualCity).textFieldStyle(.roundedBorder)
                LabeledContent("State") {
                    Picker("State", selection: $model.manualState) {
                        Text("Select").tag("")
                        ForEach(USState.all) { st in Text(st.name).tag(st.code) }
                    }
                }
            }
        }
    }

    private var payStep: some View {
        card {
            moneyField("Yearly income before taxes ($)", $model.yearlyIncome)
            if let takeHome = model.liveTakeHome {
                Label("About \(takeHome.dollars()) a month after taxes, 401(k) and insurance (2026 rules)", systemImage: "banknote")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(PLColor.success)
            }
            moneyField("401(k) contribution (% of pay, optional)", $model.retirement)
            dependentsFields
            LabeledContent("Paid") {
                Picker("Paid", selection: $model.payFrequency) {
                    ForEach(PayFrequency.allCases) { Text($0.title).tag($0) }
                }
            }
            Text("Health, dental and vision insurance per paycheck (through work)")
                .font(.subheadline.weight(.semibold)).padding(.top, 4)
            HStack(spacing: PLSpacing.sm) {
                moneyField("Health", $model.healthPerCheck)
                moneyField("Dental", $model.dentalPerCheck)
                moneyField("Vision", $model.visionPerCheck)
            }
            Text("It comes out before taxes, so it lowers your taxes a little too. Leave blank if you don't have it.")
                .font(.caption2).foregroundColor(PLColor.textSecondary)
        }
    }

    @ViewBuilder private var dependentsFields: some View {
        Text("Dependents (people you support)").font(.subheadline.weight(.semibold)).padding(.top, 4)
        if model.legacyDependents > 0 {
            Text("Last time you said \(model.legacyDependents). Add their ages below.")
                .font(.caption).foregroundColor(.orange)
        }
        Stepper("Under 5: \(model.under5)", value: $model.under5, in: 0...10)
        Stepper("Ages 5–12: \(model.age5to12)", value: $model.age5to12, in: 0...10)
        Stepper("Ages 13–17: \(model.age13to17)", value: $model.age13to17, in: 0...10)
        Stepper("18 or older: \(model.adultDependents)", value: $model.adultDependents, in: 0...10)
        if model.kidsUnder13 > 0 {
            moneyField("Childcare or daycare ($/month)", $model.childcare)
            Text("0 if you don't pay for it; leave blank to estimate.").font(.caption2).foregroundColor(PLColor.textSecondary)
        }
    }

    private var homeStep: some View {
        card {
            stackedPicker("Where you live", selection: $model.housingSituation, [
                ("Renting", "Renting"), ("Own with Mortgage", "Own with mortgage"), ("Own Free and Clear", "Own free and clear"),
                ("Live with Others", "Parents or roommates"), ("Other", "Other")])
            if model.rents {
                Toggle("I know my share of the rent", isOn: $model.knowsShare)
                if model.knowsShare {
                    moneyField("Your share of the rent ($/month)", $model.yourShare)
                    blankEstimates
                    dueDay("Rent")
                } else {
                    moneyField("Total rent for the place ($/month)", $model.totalRent)
                    if model.totalRent.isEmpty { blankEstimates }
                    Stepper("\(model.rentPeople) \(model.rentPeople == 1 ? "person" : "people") splitting it (including you)",
                            value: $model.rentPeople, in: 1...10)
                    if let total = BudgetQuizModel.amount(model.totalRent), model.rentPeople > 1 {
                        Text("Your share: \((total / Double(model.rentPeople)).dollars())")
                            .font(.caption).foregroundColor(PLColor.textSecondary)
                    }
                    dueDay("Rent")
                }
            } else if model.housingSituation == "Own with Mortgage" {
                moneyField("Mortgage payment ($/month)", $model.mortgage)
                if model.mortgage.isEmpty { blankEstimates }
                dueDay("Mortgage")
            }
            if model.housingSituation != "Other" {
                Toggle("Utilities are included", isOn: $model.utilitiesIncluded)
                if !model.utilitiesIncluded {
                    moneyField("Utilities & internet ($/month)", $model.utilities)
                    Text("Electric, water, gas and internet together. Leave blank and we'll estimate it.")
                        .font(.caption2).foregroundColor(PLColor.textSecondary)
                    dueDay("Utilities")
                } else {
                    moneyField("Internet, if separate ($/month)", $model.internet)
                    if !model.internet.isEmpty { dueDay("Internet") }
                }
                if model.rents { moneyField("Renter's insurance ($/month)", $model.rentersInsurance) }
            }
            dueDayNote
        }
    }

    private var gettingAroundStep: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            card {
                optionPicker("Car", selection: $model.carOwnership,
                             [("No Car", "No car"), ("One Car", "One car"), ("Multiple Cars", "Multiple cars")])
                if model.hasCar {
                    // one choice for all driving: the commute and other driving use its miles per gallon
                    LabeledContent("What you drive") {
                        Picker("What you drive", selection: $model.commute.car) {
                            ForEach(CarType.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    .onChange(of: model.commute.car) { old, new in
                        // gas ↔ electricity: a different price to look up
                        guard (old == .electric) != (new == .electric) else { return }
                        model.commute.fuelPrice = 0
                        model.commuteEstimated = false
                        Task { await model.loadGasPrice() }
                    }
                    fuelPriceRow
                    moneyField("Car payment ($/month, blank if none)", $model.carPayment)
                    dueDay("Car Payment")
                    carInsuranceFields
                    fromBank("Gas", "Gas (all your driving)", value: $model.otherMilesPerWeek) {
                        moneyField("Other driving, not to work (miles/week)", $model.otherMilesPerWeek)
                            .onChange(of: model.otherMilesPerWeek) { _, miles in
                                if !miles.isEmpty { Task { await model.loadGasPrice() } }
                            }
                        Text(model.commutes
                             ? "Your Gas budget is the gas for getting to work (from the commute below) plus gas for these miles."
                             : "Your Gas budget is the gas for these miles.")
                            .font(.caption2).foregroundColor(PLColor.textSecondary)
                        if let gas = model.gasFromAnswers {
                            Text(gas.commute > 0 && gas.other > 0
                                 ? "Gas: about \(gas.total.dollars()) a month (\(gas.commute.dollars()) to work + \(gas.other.dollars()) other driving)"
                                 : "Gas: about \(gas.total.dollars()) a month")
                                .font(.caption.weight(.semibold)).foregroundColor(PLColor.success)
                        }
                    }
                    dueDayNote
                }
            }
            card {
                Text("Work").font(.headline)
                Picker("Work", selection: $model.workArrangement) {
                    Text("In office").tag("office")
                    Text("Hybrid").tag("hybrid")
                    Text("Remote").tag("remote")
                    Text("Not working").tag("none")
                }
                .pickerStyle(.segmented)
                .onChange(of: model.workArrangement) { _, value in
                    if value == "hybrid", model.commute.officeDaysPerWeek > 4 { model.commute.officeDaysPerWeek = 3 }
                    if value == "office" { model.commute.officeDaysPerWeek = 5 }
                }
                if model.commutes { commuteFields }
            }
        }
    }

    @ViewBuilder private var commuteFields: some View {
        TextField("Work city or zip", text: $model.workPlace)
            .textFieldStyle(.roundedBorder)
            .onChange(of: model.workPlace) { _, _ in model.commuteEstimated = false; model.route = nil }
        if model.workPlace.isEmpty {
            Text("e.g. Glen Allen, VA or 23060").font(.caption2).foregroundColor(PLColor.textSecondary)
        }
        if model.workArrangement == "hybrid" {
            Stepper("\(Int(model.commute.officeDaysPerWeek)) office day\(model.commute.officeDaysPerWeek == 1 ? "" : "s") a week",
                    value: $model.commute.officeDaysPerWeek, in: 1...4)
        }
        LabeledContent("Getting there") {
            Picker("Getting there", selection: $model.commute.mode) {
                ForEach(CommuteMode.allCases.filter { model.hasCar || !$0.needsCar }) { Text($0.title).tag($0) }
            }
        }
        .onChange(of: model.commute.mode) { _, _ in model.commuteEstimated = false }
        if model.commute.mode.needsCar {
            numberRow("Parking at work ($/month)", value: $model.commute.parkingMonthly)
        }
        if model.commute.mode == .carpoolDriver {
            Stepper("\(Int(model.commute.carpoolPeople)) people in the carpool", value: $model.commute.carpoolPeople, in: 2...8)
        }
        if model.commute.mode == .carpoolPassenger {
            numberRow("What you chip in ($/week)", value: $model.commute.passengerWeekly)
        }
        if model.commute.mode != .bikeWalk && model.commute.mode != .carpoolPassenger {
            Button {
                Task { await model.estimateCommute() }
            } label: {
                Label(model.estimatingCommute ? "Estimating…" : model.commuteEstimated ? "Estimate Again" : "Estimate My Commute",
                      systemImage: "map")
            }
            .buttonStyle(.bordered)
            .disabled(model.estimatingCommute || model.workPlace.trimmingCharacters(in: .whitespaces).isEmpty || model.finalCity.isEmpty)
        }
        if let message = model.commuteMessage {
            Text(message).font(.caption).foregroundColor(.orange)
        }
        if model.commuteEstimated {
            if let route = model.route {
                Text("\(Int(route.roundTripMiles.rounded())) miles round trip, about \(Int(route.oneWayMinutes.rounded())) minutes each way by car.")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            }
            switch model.commute.mode {
            case .drive, .carpoolDriver:
                // the gas price is in the car section above (one price for all driving)
                if model.route?.hasTolls == true {
                    Text("Your route uses toll roads. About how much a day, both ways? (estimated; change it if you know)")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                    numberRow("Tolls ($/day)", value: $model.commute.tollsPerDay)
                }
            case .transit:
                numberRow("Monthly pass ($, 0 if none)", value: $model.commute.transitMonthlyPass)
                numberRow("One ride ($)", value: $model.commute.transitSingleFare)
                Text("If your job pays for part of transit, lower the pass price to what you pay.")
                    .font(.caption2).foregroundColor(PLColor.textSecondary)
            case .rideshare:
                Text("Uber and Lyft prices change with demand; this uses typical rates for your city.")
                    .font(.caption2).foregroundColor(PLColor.textSecondary)
            default:
                EmptyView()
            }
        }
        if let monthly = model.commuteMonthly {
            Label("Commute: about \(monthly.total.dollars()) a month (\(monthly.summary))", systemImage: "car")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(PLColor.success)
        }
    }

    private var subscriptionsStep: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            if !model.detectedToOffer.isEmpty {
                card {
                    HStack {
                        Text("Found in your transactions").font(.headline)
                        Spacer()
                        if model.detectedToOffer.count > 1 {
                            Button("Add All") { model.detectedToOffer.forEach(model.add) }.font(.subheadline)
                        }
                    }
                    Text("Charged every month for the last 3 months or more.").font(.caption).foregroundColor(PLColor.textSecondary)
                    ForEach(model.detectedToOffer) { found in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(found.name).font(.subheadline.weight(.semibold))
                                Text("\(found.averageAmount.dollars(cents: true)) a month, around the \(found.dayOfMonth.ordinal)")
                                    .font(.caption).foregroundColor(PLColor.textSecondary)
                            }
                            Spacer()
                            Button("Add") { model.add(found) }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            if !model.alsoMarkedToOffer.isEmpty { alsoMarkedCard }
            card {
                HStack {
                    Text("Your subscriptions").font(.headline)
                    Spacer()
                    Text("\(model.subscriptionsMonthly.dollars(cents: true))/month")
                        .font(.subheadline.monospacedDigit()).foregroundColor(PLColor.textSecondary)
                }
                if model.subscriptions.isEmpty {
                    Text(model.bankReady && model.detectedToOffer.isEmpty && model.alsoMarkedToOffer.isEmpty
                         ? "No subscriptions found in your transactions. Add any you pay for below."
                         : model.bankReady ? "Add the ones above you still pay for, and any we missed below."
                         : "Add the ones you pay for: streaming, music, apps, memberships.")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                }
                ForEach($model.subscriptions) { $sub in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name).font(.subheadline)
                            Text("Due around the \(Calendar.current.component(.day, from: sub.dueDate).ordinal)")
                                .font(.caption).foregroundColor(PLColor.textSecondary)
                        }
                        Spacer()
                        TextField("$0", value: $sub.cost, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Button { model.subscriptions.removeAll { $0.id == sub.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(PLColor.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(sub.name)")
                    }
                }
                Divider()
                Text("Add your own").font(.subheadline.weight(.semibold))
                TextField("Name (e.g. Netflix)", text: $newSubName).textFieldStyle(.roundedBorder)
                TextField("Cost a month", value: $newSubCost, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                DatePicker("Next due", selection: $newSubDate, displayedComponents: .date)
                Button {
                    model.subscriptions.append(QuizSubscription(name: newSubName.trimmingCharacters(in: .whitespaces),
                                                                cost: newSubCost ?? 0, dueDate: newSubDate))
                    newSubName = ""
                    newSubCost = nil
                    newSubDate = Date()
                } label: {
                    Label("Add Subscription", systemImage: "plus.circle.fill")
                }
                .disabled(!canAddSubscription)
                Text("Saved to your Subscriptions page with your budget, with a reminder the day before each is due.")
                    .font(.caption2).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    /// what the bank counts as subscriptions that didn't repeat enough to be sure (what the average is made of)
    private var alsoMarkedCard: some View {
        card {
            HStack {
                Text("Also marked as subscriptions").font(.headline)
                Spacer()
                if model.alsoMarkedToOffer.count > 1 {
                    Button("Add All") { model.alsoMarkedToOffer.forEach(model.add) }.font(.subheadline)
                }
            }
            Text("These are marked as subscriptions in your transactions, but they haven't charged every month lately. Add the ones you still pay for.")
                .font(.caption).foregroundColor(PLColor.textSecondary)
            ForEach(model.alsoMarkedToOffer) { charge in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(charge.name).font(.subheadline.weight(.semibold))
                        Text("\(charge.amount.dollars(cents: true)), last on \(charge.lastDate.formatted(.dateTime.month(.abbreviated).day()))"
                             + (charge.times > 1 ? " (\(charge.times) times)" : ""))
                            .font(.caption).foregroundColor(PLColor.textSecondary)
                    }
                    Spacer()
                    Button("Add") { model.add(charge) }.buttonStyle(.bordered)
                }
            }
        }
    }

    private var canAddSubscription: Bool {
        let name = newSubName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && (newSubCost ?? 0) > 0
            && !model.subscriptions.contains { $0.name.lowercased() == name.lowercased() }
    }

    private var otherCostsStep: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            if model.bankReady && !model.bankAverages.isEmpty {
                card {
                    Text("What you usually spend (from your transactions)").font(.headline)
                    averagesList(limit: 20)
                    Text("Your budget starts from these and may trim flexible ones (like eating out) to fit your goals.")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
            }
            card {
                fromBank("Eating Out", "Eating out", value: $model.eatingOutFrequency, alwaysFold: true) {
                    optionPicker("Eating out", selection: $model.eatingOutFrequency,
                                 [("Rarely", "Rarely"), ("Sometimes", "Sometimes"), ("Often", "Often")])
                }
                moneyField("Phone, your share ($/month)", $model.phone)
                Text("Leave blank and we'll estimate it; 0 if you don't pay for one.")
                    .font(.caption2).foregroundColor(PLColor.textSecondary)
                dueDay("Phone")
                fromBank("Gym", "Gym", value: $model.gym) {
                    moneyField("Gym ($/month, blank if none)", $model.gym)
                }
                fromBank("Medical", "Prescriptions, therapy, copays", value: $model.medical) {
                    moneyField("Prescriptions, therapy, copays ($/month)", $model.medical)
                    if model.medical.isEmpty {
                        Text("Leave blank if none.").font(.caption2).foregroundColor(PLColor.textSecondary)
                    }
                }
            }
            card {
                Text("Pets").font(.headline)
                Stepper("Dogs: \(model.dogs)", value: $model.dogs, in: 0...10)
                Stepper("Cats: \(model.cats)", value: $model.cats, in: 0...10)
                Stepper("Other pets: \(model.otherPets)", value: $model.otherPets, in: 0...10)
                if model.dogs + model.cats + model.otherPets > 0 {
                    moneyField("Pet costs ($/month, blank to estimate)", $model.petsMonthly)
                }
            }
        }
    }

    private var yearlyStep: some View {
        card {
            Text("Once-a-year costs").font(.headline)
            Text("Things you pay once or a few times a year. Each becomes a small amount to set aside every month. Leave an amount blank and we'll estimate it.")
                .font(.subheadline).foregroundColor(PLColor.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(YearlyCost.suggestions.filter { name in !model.yearlyCosts.contains { $0.name == name } }, id: \.self) { name in
                        Button(name) { model.yearlyCosts.append(YearlyCost(name: name)) }
                            .buttonStyle(.bordered).font(.caption)
                    }
                    Button("Something else") { model.yearlyCosts.append(YearlyCost(name: "")) }
                        .buttonStyle(.bordered).font(.caption)
                }
            }
            ForEach($model.yearlyCosts) { $cost in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("What it is", text: $cost.name).textFieldStyle(.roundedBorder)
                        Button { model.yearlyCosts.removeAll { $0.id == cost.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(PLColor.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(cost.name)")
                    }
                    HStack {
                        TextField("$ each time", value: $cost.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 110)
                        Stepper("\(cost.timesPerYear)× a year", value: $cost.timesPerYear, in: 1...12)
                            .lineLimit(1)
                    }
                    if let amount = cost.amount, amount > 0 {
                        Text("Set aside \(cost.monthly.dollars()) a month").font(.caption).foregroundColor(PLColor.textSecondary)
                    } else if !cost.name.isEmpty {
                        Text("We'll estimate it").font(.caption).foregroundColor(PLColor.textSecondary)
                    }
                }
                Divider()
            }
            if model.yearlyMonthly > 0 {
                let estimating = model.yearlyCosts.contains { !$0.name.isEmpty && ($0.amount ?? 0) <= 0 }
                Text("Total: \(model.yearlyMonthly.dollars()) a month\(estimating ? ", plus what we estimate" : "")")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var debtStep: some View {
        card {
            Toggle("I have debt to pay off", isOn: $model.hasDebt)
                .onChange(of: model.hasDebt) { _, on in if !on { model.debts.removeAll() } }
            if model.hasDebt {
                ForEach($model.debts) { $debt in
                    DebtRow(debt: $debt).plCard()
                }
                Button {
                    model.debts.append(DebtItem())
                } label: {
                    Label("Add Debt", systemImage: "plus.circle.fill")
                }
                .tint(.green)
                if !model.debtEntriesValid {
                    Text("Each debt needs a name and a balance.").font(.caption).foregroundColor(.orange)
                }
            }
        }
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            card {
                Text("How do you like to budget?").font(.headline)
                ForEach(BudgetingStyleChoice.allCases) { style in
                    Button {
                        model.budgetingStyle = style
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.budgetingStyle == style ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(model.budgetingStyle == style ? PLColor.accent : PLColor.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).font(.subheadline.weight(.semibold)).foregroundColor(PLColor.textPrimary)
                                Text(style.detail).font(.caption).foregroundColor(PLColor.textSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.budgetingStyle == style ? .isSelected : [])
                }
                if model.budgetingStyle == .payYourselfFirst {
                    Stepper("Save \(Int(model.savePercent))% of take-home first", value: $model.savePercent, in: 5...50, step: 5)
                }
            }
            savingsCard
            card {
                optionPicker("Main goal", selection: $model.primaryGoal, [
                    ("Emergency Fund", "Emergency fund"), ("Pay Down Debt", "Pay down debt"),
                    ("Big Purchase", "A big purchase"), ("Maximize Investing", "Invest more"),
                    ("Balanced", "Balanced")])
                Text("Savings priority").font(.subheadline.weight(.semibold)).padding(.top, 4)
                Picker("Savings priority", selection: $model.savingsPriority) {
                    Text("Low").tag("Low")
                    Text("Medium").tag("Medium")
                    Text("High").tag("High")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    /// what they have saved: from the Plan tab, or asked here when the Plan has nothing yet
    @ViewBuilder private var savingsCard: some View {
        card {
            Text("What you have saved").font(.headline)
            if let plan = model.plan, model.planHasSavings {
                HStack {
                    Text("Emergency fund")
                    Spacer()
                    Text(model.emergencySaved.dollars()).monospacedDigit()
                }
                .font(.subheadline)
                Text("Goal: \(plan.emergencyFund.months) months of expenses").font(.caption).foregroundColor(PLColor.textSecondary)
                ForEach(plan.savingsGoals) { goal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name)
                            if let date = goal.targetDate.flatMap(Plan.day) {
                                Text("by \(date.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.caption).foregroundColor(PLColor.textSecondary)
                            }
                        }
                        Spacer()
                        Text("\(model.goalSaved(goal).dollars()) of \(goal.target.dollars())").monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Text("From your Plan tab (Budget → Plan). Change them there.")
                    .font(.caption2).foregroundColor(PLColor.textSecondary)
            } else {
                moneyField("How much do you have saved now? ($)", $model.savedNow)
                Text(model.plan == nil
                     ? "Savings, emergency fund and cash you could use if something came up."
                     : "Saved to your Plan tab as your emergency fund, so you can track it there.")
                    .font(.caption2).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    /// "From your transactions: $80/month", and for a narrower one where it comes out of
    private func bankLine(_ category: String, _ usual: Double) -> String {
        let line = "From your transactions: \(usual.dollars())/month"
        guard model.bankNiches.contains(category), let parent = model.nicheParent(category) else { return line }
        return line + (model.selectedCategories.contains(category) ? ", taken out of \(parent)" : ", would come out of \(parent)")
    }

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            card {
                Text("Budget categories").font(.headline)
                Text("Home, bills, getting around, subscriptions and the other costs you answered earlier are already in your budget. Pick anything else to plan for.")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
                ForEach(model.allCategories.filter { !BudgetQuizModel.trackerExclusions.contains($0)
                    && !model.answeredElsewhere.contains($0) }.sorted(), id: \.self) { category in
                    Toggle(isOn: Binding(get: { model.selectedCategories.contains(category) },
                                         set: { model.setCategory(category, on: $0) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category)
                            if let usual = model.bankAverage(category) {
                                Text(bankLine(category, usual)).font(.caption).foregroundColor(PLColor.textSecondary)
                            }
                        }
                    }
                }
                Menu {
                    ForEach(availableCategories, id: \.self) { c in
                        Button(c) { model.allCategories.append(c); model.selectedCategories.insert(c) }
                    }
                    Divider()
                    Button("Custom…") { showCustomCategory = true }
                } label: {
                    Label("Add Category", systemImage: "plus.circle.fill").font(.subheadline)
                }
                .alert("Custom Category", isPresented: $showCustomCategory) {
                    TextField("Category name", text: $customCategory)
                    Button("Add") {
                        let trimmed = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !model.allCategories.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                            model.allCategories.append(trimmed)
                            model.selectedCategories.insert(trimmed)
                        }
                        customCategory = ""
                    }
                    Button("Cancel", role: .cancel) { customCategory = "" }
                }
            }
            let knowable = model.selectedCategories.subtracting(BudgetQuizModel.trackerExclusions)
                .subtracting(model.answeredElsewhere).sorted()
            if !knowable.isEmpty {
                card {
                    Text("Other costs you already know (optional)").font(.headline)
                    Text("Amounts you enter stay exactly as they are.").font(.caption).foregroundColor(PLColor.textSecondary)
                    ForEach(knowable, id: \.self) { category in
                        moneyField("\(category) ($/month)", Binding(
                            get: { model.knownCosts[category] ?? "" },
                            set: { model.knownCosts[category] = $0 }))
                    }
                }
            }
        }
    }

    private var availableCategories: [String] {
        let current = Set(model.allCategories.map { $0.lowercased() })
        return quizCommonCategories.filter { !current.contains($0.lowercased()) && !BudgetQuizModel.trackerExclusions.contains($0)
            && !model.answeredElsewhere.contains($0) }.sorted()
    }

    // MARK: - Actions

    private func build() async {
        hideKeyboard()
        building = true
        defer { building = false }
        do {
            review = Review(draft: try await model.build())
        } catch {
            errorMessage = (error as? AILimitError)?.message
            showError = true
        }
    }

    private func getLocation() {
        locationManager.requestLocation { cityName, stateName in
            model.city = cityName
            model.state = stateName
        }
    }
}

extension Int {
    /// 1 → "1st", 22 → "22nd", 11 → "11th"
    var ordinal: String {
        let suffix: String
        switch (self % 10, self % 100) {
        case (1, let t) where t != 11: suffix = "st"
        case (2, let t) where t != 12: suffix = "nd"
        case (3, let t) where t != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(self)\(suffix)"
    }
}

// ---------- Rows & helpers ----------
private struct DebtRow: View {
    @Binding var debt: DebtItem
    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            TextField("Name (e.g., Chase Credit Card)", text: $debt.name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: PLSpacing.sm) {
                TextField("Remaining Balance ($)", text: $debt.principal)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: debt.principal) { _, v in debt.principal = v.filter { "0123456789.".contains($0) } }
                TextField("APR (%)", text: $debt.apr)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: debt.apr) { _, v in debt.apr = v.filter { "0123456789.".contains($0) } }
            }
            TextField("Minimum Monthly Payment ($)", text: $debt.minPayment)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: debt.minPayment) { _, v in debt.minPayment = v.filter { "0123456789.".contains($0) } }
            DatePicker("Next Payment Due", selection: $debt.dueDate, displayedComponents: .date)
        }
    }
}

// ---------- Location plumbing ----------
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((String, String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestLocation(completion: @escaping (String, String) -> Void) {
        self.completion = completion
        manager.delegate = self

        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            print("Location access denied")
            self.completion?("Permission", "Denied")
            return
        }
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let place = placemarks?.first {
                let city = place.locality ?? ""
                let state = place.administrativeArea ?? ""
                DispatchQueue.main.async { self.completion?(city, state) }
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error)
    }
}

#if canImport(UIKit)
private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

#Preview { NavigationStack { BudgetQuizView().environmentObject(CalendarViewModel()) } }
