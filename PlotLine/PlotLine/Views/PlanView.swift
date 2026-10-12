//
//  PlanView.swift
//  PlotLine
//
//  Budget → Plan: net worth, the emergency fund, savings goals, the debt payoff planner, and
//  first-job tools (paycheck, 401(k) match, rent).
//

import SwiftUI

struct PlanView: View {
    @StateObject private var model: PlanViewModel

    init() {
        _model = StateObject(wrappedValue: PlanViewModel())
    }

    /// with a model that's already loaded (previews and screenshots)
    init(model: PlanViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    @State private var editingGoal: SavingsGoal?
    @State private var depositGoal: SavingsGoal?
    @State private var editingHolding: Holding?
    @State private var showEmergencySettings = false
    @State private var emergencyDeposit = false
    @State private var showNetWorthDetail = false

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                if !model.loaded {
                    ProgressView("Loading your plan…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    netWorthCard
                    emergencyFundCard
                    savingsGoalsCard
                    debtCard
                    toolsCard
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
        }
        .task { if !model.loaded { await model.load() } }
        .refreshable { await model.load() }
        .sheet(item: $editingGoal) { goal in
            SavingsGoalEditor(goal: goal, accounts: model.savingsAccounts,
                              isNew: !model.plan.savingsGoals.contains { $0.id == goal.id },
                              onSave: { saved in
                                  model.update { plan in
                                      if let i = plan.savingsGoals.firstIndex(where: { $0.id == saved.id }) {
                                          plan.savingsGoals[i] = saved
                                      } else {
                                          plan.savingsGoals.append(saved)
                                      }
                                  }
                              },
                              onDelete: { id in model.update { $0.savingsGoals.removeAll { $0.id == id } } })
        }
        .sheet(item: $depositGoal) { goal in
            MoneyAmountSheet(title: goal.name, current: goal.saved) { amount in
                model.update { plan in
                    if let i = plan.savingsGoals.firstIndex(where: { $0.id == goal.id }) {
                        plan.savingsGoals[i].saved = max(0, plan.savingsGoals[i].saved + amount)
                    }
                }
            }
        }
        .sheet(isPresented: $emergencyDeposit) {
            MoneyAmountSheet(title: "Emergency fund", current: model.plan.emergencyFund.saved) { amount in
                model.update { $0.emergencyFund.saved = max(0, $0.emergencyFund.saved + amount) }
            }
        }
        .sheet(isPresented: $showEmergencySettings) {
            EmergencyFundSettings(fund: model.plan.emergencyFund, monthlySpending: model.monthlySpending,
                                  accounts: model.savingsAccounts) { fund in
                model.update { $0.emergencyFund = fund }
            }
        }
        .sheet(item: $editingHolding) { holding in
            HoldingEditor(holding: holding, isNew: !model.plan.assets.contains { $0.id == holding.id },
                          onSave: { saved in
                              model.update { plan in
                                  if let i = plan.assets.firstIndex(where: { $0.id == saved.id }) {
                                      plan.assets[i] = saved
                                  } else {
                                      plan.assets.append(saved)
                                  }
                              }
                          },
                          onDelete: { id in model.update { $0.assets.removeAll { $0.id == id } } })
        }
    }

    // MARK: - Net worth

    private var netWorthCard: some View {
        let worth = model.netWorth
        return VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Label("Net worth", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Button(showNetWorthDetail ? "Hide" : "Details") {
                    withAnimation { showNetWorthDetail.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
            Text(worth.total.dollars())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(worth.total < 0 ? PLColor.danger : PLColor.textPrimary)
            Text("What you own minus what you owe.")
                .font(.caption)
                .foregroundColor(PLColor.textSecondary)

            if showNetWorthDetail {
                Divider()
                Text("You own").font(.subheadline.weight(.semibold))
                if worth.owned.isEmpty {
                    Text("Link a bank in Budgeting, or add what you own below.")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                ForEach(model.linked.filter { $0.kind != .owed }) { account in
                    amountRow(account.name, account.balance)
                }
                ForEach(model.plan.assets) { holding in
                    Button { editingHolding = holding } label: {
                        HStack {
                            amountRow(holding.name, holding.value)
                            Image(systemName: "pencil").font(.caption).foregroundColor(PLColor.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit")
                }
                Button {
                    editingHolding = Holding(name: "", value: 0)
                } label: {
                    Label("Add something you own", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                Text("You owe").font(.subheadline.weight(.semibold)).padding(.top, 4)
                if worth.owed.isEmpty {
                    Text("No debts. Add them in the payoff planner below.")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                ForEach(Array(worth.owed.enumerated()), id: \.offset) { _, line in
                    amountRow(line.name, -line.amount)
                }
                Text("Linked accounts update when your bank syncs. Savings goals aren't added again: that money is already in an account.")
                    .font(.caption2)
                    .foregroundColor(PLColor.textSecondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    private func amountRow(_ name: String, _ amount: Double) -> some View {
        HStack {
            Text(name).font(.subheadline)
            Spacer()
            Text(amount.dollars())
                .font(.subheadline.monospacedDigit())
                .foregroundColor(amount < 0 ? PLColor.danger : PLColor.textPrimary)
        }
    }

    // MARK: - Emergency fund

    private var emergencyFundCard: some View {
        let saved = model.emergencySaved
        let target = model.emergencyTarget
        return VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Label("Emergency fund", systemImage: "lifepreserver")
                    .font(.headline)
                Spacer()
                Button { showEmergencySettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Emergency fund settings")
            }
            if let target {
                Text("\(saved.dollars()) of \(target.dollars())")
                    .font(.title3.weight(.semibold))
                ProgressView(value: min(saved, target), total: max(target, 1))
                    .tint(saved >= target ? PLColor.success : PLColor.tint)
                Text(saved >= target
                     ? "Fully funded: \(model.plan.emergencyFund.months) months of spending set aside."
                     : "\(model.plan.emergencyFund.months) months of your budgeted spending (\((model.monthlySpending ?? 0).dollars()) a month). \((target - saved).dollars()) to go.")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            } else {
                Text(saved.dollars()).font(.title3.weight(.semibold))
                Text("Take the budget quiz and the goal is worked out from your monthly spending.")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }
            if model.plan.emergencyFund.linkedAccountId == nil {
                Button { emergencyDeposit = true } label: {
                    Label("Add or take out money", systemImage: "plus.forwardslash.minus")
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("Following your linked account's balance.")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    // MARK: - Savings goals

    private var savingsGoalsCard: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Label("Savings goals", systemImage: "banknote")
                    .font(.headline)
                Spacer()
                Button {
                    editingGoal = SavingsGoal(name: "", target: 0)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add a savings goal")
            }
            if model.plan.savingsGoals.isEmpty {
                Text("Saving for a trip, a car or a move? Add a goal and see how much to put away each month.")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
            }
            ForEach(model.plan.savingsGoals) { goal in
                goalRow(goal)
                if goal.id != model.plan.savingsGoals.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    private func goalRow(_ goal: SavingsGoal) -> some View {
        let saved = model.saved(goal)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { editingGoal = goal } label: {
                    Text(goal.name).font(.subheadline.weight(.semibold)).foregroundColor(PLColor.textPrimary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(saved.dollars()) / \(goal.target.dollars())")
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: min(saved, goal.target), total: max(goal.target, 1))
                .tint(saved >= goal.target ? PLColor.success : PLColor.tint)
            HStack {
                if saved >= goal.target {
                    Text("Reached!").font(.caption.weight(.semibold)).foregroundColor(PLColor.success)
                } else if let monthly = goal.monthlyNeeded(saved: saved), let date = goal.targetDate.flatMap(Plan.day) {
                    Text("\(monthly.dollars()) a month to reach it by \(date.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                Spacer()
                if goal.linkedAccountId == nil {
                    Button("Add money") { depositGoal = goal }
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    // MARK: - Debts

    private var debtCard: some View {
        let debts = model.debtsNow
        let total = debts.map(\.balance).reduce(0, +)
        let best = debts.isEmpty ? nil : DebtPayoff.simulate(debts, extra: model.plan.extraDebtPayment, strategy: .avalanche)
        return NavigationLink {
            DebtPlannerView(model: model)
        } label: {
            VStack(alignment: .leading, spacing: PLSpacing.sm) {
                HStack {
                    Label("Debt payoff planner", systemImage: "creditcard.and.123")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundColor(PLColor.textSecondary)
                }
                if debts.isEmpty {
                    Text("Student loans, cards, a car loan: see when you'll be debt-free and which to pay first (avalanche vs. snowball).")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("\(total.dollars()) across \(debts.count) debt\(debts.count == 1 ? "" : "s")")
                        .font(.title3.weight(.semibold))
                    if let date = best?.payoffDate() {
                        Text("Debt-free by \(date.formatted(.dateTime.month(.wide).year()))")
                            .font(.subheadline)
                            .foregroundColor(PLColor.success)
                    } else {
                        Text("At these payments some debts never get paid off. Open the planner to fix it.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.danger)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .plCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tools

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Label("First-job tools", systemImage: "briefcase")
                .font(.headline)
            VStack(spacing: 6) {
                NavigationLink { PaycheckCalculatorView(quiz: model.quiz) } label: {
                    PLRow(icon: "dollarsign.circle.fill", tint: .green, title: "Paycheck → take-home")
                }
                Divider().padding(.leading, 42)
                NavigationLink { MatchExplainerView(quiz: model.quiz) } label: {
                    PLRow(icon: "gift.fill", tint: .orange, title: "401(k) match explained")
                }
                Divider().padding(.leading, 42)
                NavigationLink { RentCheckView(quiz: model.quiz) } label: {
                    PLRow(icon: "house.fill", tint: .blue, title: "Can I afford this rent?")
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }
}

// MARK: - Editors

/// "+ $50" or "− $20" to a goal or the emergency fund
struct MoneyAmountSheet: View {
    let title: String
    let current: Double
    let onDone: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var takingOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $takingOut) {
                        Text("Add money").tag(false)
                        Text("Take out").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Saved so far: \(current.dollars(cents: true))")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onDone((takingOut ? -1 : 1) * (amount ?? 0))
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct SavingsGoalEditor: View {
    @State var goal: SavingsGoal
    let accounts: [LinkedBalance]
    let isNew: Bool
    let onSave: (SavingsGoal) -> Void
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasDate: Bool
    @State private var date: Date

    init(goal: SavingsGoal, accounts: [LinkedBalance], isNew: Bool,
         onSave: @escaping (SavingsGoal) -> Void, onDelete: @escaping (String) -> Void) {
        _goal = State(initialValue: goal)
        self.accounts = accounts
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _hasDate = State(initialValue: goal.targetDate != nil)
        _date = State(initialValue: goal.targetDate.flatMap(Plan.day)
                      ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name (e.g. Japan trip)", text: $goal.name)
                    TextField("Target", value: $goal.target, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    Toggle("Reach it by a date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: $date, in: Date()..., displayedComponents: .date)
                    }
                }
                Section {
                    Picker("Saved amount", selection: $goal.linkedAccountId) {
                        Text("I'll add money myself").tag(String?.none)
                        ForEach(accounts) { account in
                            Text("\(account.name) (\(account.balance.dollars()))").tag(String?.some(account.id))
                        }
                    }
                    if goal.linkedAccountId == nil {
                        TextField("Saved so far", value: $goal.saved, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text(accounts.isEmpty
                         ? "Link a bank in Budgeting to have a savings account's balance count automatically."
                         : "A linked account's balance counts as saved for this goal.")
                }
                if !isNew {
                    Section {
                        Button("Delete Goal", role: .destructive) {
                            onDelete(goal.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Savings Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        goal.name = goal.name.trimmingCharacters(in: .whitespaces)
                        goal.targetDate = hasDate ? Plan.dayKey(date) : nil
                        onSave(goal)
                        dismiss()
                    }
                    .disabled(goal.name.trimmingCharacters(in: .whitespaces).isEmpty || goal.target <= 0)
                }
            }
        }
    }
}

struct EmergencyFundSettings: View {
    @State var fund: EmergencyFund
    let monthlySpending: Double?
    let accounts: [LinkedBalance]
    let onSave: (EmergencyFund) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(fund.months) months of spending", value: $fund.months, in: 1...12)
                    if let monthlySpending {
                        Text("Goal: \((monthlySpending * Double(fund.months)).dollars())")
                            .foregroundColor(PLColor.textSecondary)
                    }
                } footer: {
                    Text("3 to 6 months is the usual advice; more if your income changes a lot.")
                }
                Section {
                    Picker("Saved amount", selection: $fund.linkedAccountId) {
                        Text("I'll add money myself").tag(String?.none)
                        ForEach(accounts) { account in
                            Text("\(account.name) (\(account.balance.dollars()))").tag(String?.some(account.id))
                        }
                    }
                }
            }
            .navigationTitle("Emergency Fund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(fund); dismiss() }
                }
            }
        }
    }
}

struct HoldingEditor: View {
    @State var holding: Holding
    let isNew: Bool
    let onSave: (Holding) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What it is (e.g. Car, Cash)", text: $holding.name)
                    TextField("What it's worth", value: $holding.value, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("For things not in a linked account. Linked accounts are counted automatically.")
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) { onDelete(holding.id); dismiss() }
                    }
                }
            }
            .navigationTitle(isNew ? "Something You Own" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(holding); dismiss() }
                        .disabled(holding.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
