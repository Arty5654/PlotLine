//
//  BudgetCompareView.swift
//  PlotLine
//
//  Budget → Compare New Income/Location: your budget now next to one built for a new income and/or
//  place, each against its own take-home. Built like the quiz (your saved answers and spending) but
//  nothing is saved: it used to save every projection over your budget and quiz answers. "Use This
//  Budget" opens the quiz's review screen; saving there makes it your budget and your new answers.
//

import SwiftUI

struct BudgetCompareView: View {
    @StateObject private var model = BudgetQuizModel()
    @EnvironmentObject private var calendarVM: CalendarViewModel

    @State private var currentIncome: Double?
    @State private var currentCity = ""
    @State private var currentState = ""
    @State private var newIncome = ""
    @State private var newCity = ""
    @State private var newState = ""

    @State private var currentBudget: [String: Double] = [:]
    @State private var projection: BudgetQuizModel.Draft?
    @State private var projecting = false
    @State private var error: String?
    @State private var reviewing: Review?
    @State private var saved = false

    private struct Review: Identifiable {
        let id = UUID()
        let draft: BudgetQuizModel.Draft
    }

    private let excluded: Set<String> = ["401(k)", "401(k) Contribution", "401k", "401k Contribution"]
    private var currentTotal: Double { currentBudget.filter { !excluded.contains($0.key) }.values.reduce(0, +) }
    private var projectedTotal: Double { (projection?.budget ?? [:]).filter { !excluded.contains($0.key) }.values.reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Plan a Move or Raise").font(.title3).bold()
                    Text("See what your budget would look like with a new income or in a new place. Nothing changes unless you choose to use it.")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                inputs
                if projection != nil { comparison }
                if saved {
                    Label("Your budget was updated.", systemImage: "checkmark.circle.fill").foregroundColor(PLColor.success)
                }
            }
            .padding(PLSpacing.lg)
        }
        .navigationTitle("Compare Budgets")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $reviewing) { review in
            BudgetReviewView(model: model, draft: review.draft) {
                reviewing = nil
                saved = true
                Task { await load() } // the new budget is now the current one
            }
            .environmentObject(calendarVM)
        }
    }

    // MARK: - Pieces

    private var inputs: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current income").font(.caption).foregroundColor(PLColor.textSecondary)
                    Text(currentIncome.map { $0.dollars() } ?? "—").font(.headline)
                    Text("From your budget quiz").font(.caption2).foregroundColor(PLColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("New income").font(.caption).foregroundColor(PLColor.textSecondary)
                    TextField("e.g. 90000", text: $newIncome)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("New place (optional)").font(.caption).foregroundColor(PLColor.textSecondary)
                TextField("City", text: $newCity).textFieldStyle(.roundedBorder)
                Picker("State", selection: $newState) {
                    ForEach(USState.all) { Text($0.name).tag($0.code) }
                }
                .pickerStyle(.menu)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundColor(PLColor.danger)
            }
            Button {
                Task { await project() }
            } label: {
                Text(projecting ? "Building…" : "Show Projection").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(projecting || currentIncome == nil || (BudgetQuizModel.amount(newIncome) ?? 0) <= 0)
        }
        .plCard()
    }

    private func fitText(planned: Double, takeHome: Double?) -> (String, Color) {
        guard let takeHome, takeHome > 0 else { return ("", PLColor.textSecondary) }
        let left = takeHome - planned
        return left >= -0.5 ? ("Fits: \(left.dollars()) left a month", PLColor.success) : ("Over by \((-left).dollars()) a month", PLColor.danger)
    }

    private var comparison: some View {
        let current = fitText(planned: currentTotal, takeHome: model.savedMonthlyNet)
        let projected = fitText(planned: projectedTotal, takeHome: projection?.monthlyNet)
        return VStack(alignment: .leading, spacing: PLSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now").font(.caption).foregroundColor(PLColor.textSecondary)
                    Text("Take-home \(model.savedMonthlyNet.map { $0.dollars() } ?? "—")").font(.subheadline)
                    Text("Planned \(currentTotal.dollars())").font(.subheadline)
                    Text(current.0).font(.caption).foregroundColor(current.1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("New").font(.caption).foregroundColor(PLColor.textSecondary)
                    Text("Take-home \(projection.map { $0.monthlyNet.dollars() } ?? "—")").font(.subheadline)
                    Text("Planned \(projectedTotal.dollars())").font(.subheadline)
                    Text(projected.0).font(.caption).foregroundColor(projected.1)
                }
            }
            Divider()
            ForEach(lines, id: \.self) { line in
                let now = currentBudget[line] ?? 0, new = projection?.budget[line] ?? 0
                HStack {
                    Text(line)
                    Spacer()
                    Text(now.dollars()).font(.caption).foregroundColor(PLColor.textSecondary).monospacedDigit()
                    Image(systemName: "arrow.right").font(.caption2).foregroundColor(PLColor.textSecondary)
                    Text(new.dollars()).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundColor(new < now ? .orange : PLColor.textPrimary)
                }
            }
            Button {
                if let projection { reviewing = Review(draft: projection) }
            } label: {
                Text("Review and Use This Budget").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            Text("Using it also updates your quiz answers to the new income and place.")
                .font(.caption2).foregroundColor(PLColor.textSecondary)
        }
        .plCard()
    }

    private var lines: [String] {
        Set(currentBudget.keys).union(projection?.budget.keys ?? [String: Double]().keys)
            .subtracting(excluded).sorted()
    }

    // MARK: - Loading

    private func load() async {
        await model.loadSavedQuiz()
        guard model.hasSavedQuiz else {
            error = "Take the budget quiz first; the projection starts from its answers."
            return
        }
        currentIncome = BudgetQuizModel.amount(model.yearlyIncome)
        currentCity = model.finalCity
        currentState = model.finalState
        if newIncome.isEmpty { newIncome = model.yearlyIncome }
        if newCity.isEmpty { newCity = currentCity }
        if newState.isEmpty { newState = currentState }
        currentBudget = (try? await PlanAPI.fetchMonthlyBudget()) ?? [:]
        await model.checkBank()
        await model.loadSubscriptions()   // the Subscriptions page's list (its total is a line)
        await model.loadPlan()
        if model.hasCar && model.commute.fuelPrice <= 0 { await model.loadGasPrice() }
    }

    /// the same answers with the new income and place; built, never saved
    private func project() async {
        error = nil
        projecting = true
        defer { projecting = false }
        model.yearlyIncome = newIncome
        // "Ashburn, VA" typed as the city is Ashburn + VA
        let place = BudgetQuizModel.place(city: newCity, state: newState)
        if !place.city.isEmpty || !place.state.isEmpty {
            model.useDeviceLocation = false
            model.manualCity = place.city.isEmpty ? currentCity : place.city
            model.manualState = place.state.isEmpty ? currentState : place.state
        }
        do {
            projection = try await model.build()
        } catch {
            self.error = (error as? AILimitError)?.message ?? "Couldn't build the projection. Please try again."
        }
    }
}
