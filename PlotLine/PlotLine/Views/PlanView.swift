//
//  PlanView.swift
//  PlotLine
//
//  Budget → Plan: the emergency fund, savings goals, the debt payoff planner, and
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
    @State private var showEmergencySettings = false
    @State private var emergencyDeposit = false
    @State private var budgetLineEdit: BudgetLineEdit?
    @State private var editingCheckIn = false
    @State private var buyingGoal: SavingsGoal?
    @State private var deletingGoal: SavingsGoal?
    @State private var boughtMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                if !model.loaded {
                    ProgressView("Loading your plan…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if model.needsCheckIn() { checkInCard }
                    emergencyFundCard
                    savingsGoalsCard
                    if !model.plan.wishlist.isEmpty { wishlistCard }
                    debtCard
                    affordCard
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
        .confirmationDialog(buyingGoal.map { "Bought \($0.name)?" } ?? "", isPresented: Binding(
            get: { buyingGoal != nil }, set: { if !$0 { buyingGoal = nil } }), titleVisibility: .visible) {
            if let goal = buyingGoal {
                Button("Log \(goal.target.dollars()) and Close the Goal") { Task { await markBought(goal) } }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("It's added to today's spending, and the goal closes. Any budget cuts that paid for it end.")
        }
        .confirmationDialog(deletingGoal.map { "Delete \($0.name)?" } ?? "", isPresented: Binding(
            get: { deletingGoal != nil }, set: { if !$0 { deletingGoal = nil } }), titleVisibility: .visible) {
            if let goal = deletingGoal {
                Button("Delete Goal", role: .destructive) {
                    model.update { $0.savingsGoals.removeAll { $0.id == goal.id } }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("What your budget puts toward it goes back to Savings, and anything paused for it resumes.")
        }
        .alert(boughtMessage ?? "", isPresented: Binding(get: { boughtMessage != nil }, set: { if !$0 { boughtMessage = nil } })) {
            Button("OK", role: .cancel) {}
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
        .sheet(item: $budgetLineEdit) { edit in
            BudgetAmountSheet(edit: edit, model: model)
        }
        .sheet(isPresented: $editingCheckIn) {
            SavingsCheckInSheet(lines: model.checkInLines) { amounts in model.confirmCheckIn(amounts) }
        }
    }

    // MARK: - This month's savings (no linked account tracks them)

    private var checkInCard: some View {
        let lines = model.checkInLines
        return VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Label("\(Date().formatted(.dateTime.month(.wide))) savings", systemImage: "checkmark.circle")
                .font(.headline)
            Text("Your budget sets these aside. Did you move them to savings this month?")
                .font(.subheadline).foregroundColor(PLColor.textSecondary)
            ForEach(lines) { line in
                HStack {
                    Text(line.name).font(.subheadline)
                    Spacer()
                    Text(line.amount.dollars()).font(.subheadline.monospacedDigit())
                }
            }
            HStack {
                Button("I Moved It") {
                    model.confirmCheckIn(Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.amount) }))
                }
                .buttonStyle(.borderedProminent)
                Button("Different Amounts") { editingCheckIn = true }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Skip") { model.skipCheckIn() }
                    .font(.subheadline)
            }
            Text("It's added to what you've saved, since no linked account tracks it.")
                .font(.caption2).foregroundColor(PLColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    // MARK: - What the budget puts toward it

    /// "In your budget: $150 a month · On track", or "Not in your budget yet" with a button to add it
    @ViewBuilder
    private func budgetRow(line: String, title: String, budgeted: Double, needed: Double?, status: String?, warn: Bool = false) -> some View {
        if model.hasBudget {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if budgeted > 0 {
                        Text("In your budget: \(budgeted.dollars()) a month").font(.caption.weight(.semibold))
                    } else {
                        Text("Not in your budget yet").font(.caption.weight(.semibold)).foregroundColor(PLColor.textSecondary)
                    }
                    Spacer()
                    Button(budgeted > 0 ? "Change" : "Add to Budget") {
                        budgetLineEdit = BudgetLineEdit(line: line, title: title, current: budgeted,
                                                        suggested: budgeted > 0 ? budgeted : (needed ?? 50).rounded(.up))
                    }
                    .font(.caption.weight(.semibold))
                }
                if let status {
                    Text(status).font(.caption).foregroundColor(warn ? .orange : PLColor.textSecondary)
                }
            }
            .padding(.top, 2)
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
            if let target, saved < target || model.emergencyBudget > 0 {
                let gap = max(0, target - saved)
                budgetRow(line: BudgetLine.emergencyFund, title: "Emergency fund", budgeted: model.emergencyBudget,
                          needed: (gap / 12).rounded(.up),
                          status: saved >= target ? "Full, so this can go to your goals now: tap Change."
                                : model.emergencyMonthsToFull.map { "Full in about \($0) month\($0 == 1 ? "" : "s") at this pace." }
                                  ?? "About \((gap / 12).rounded(.up).dollars()) a month fills it in a year.")
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
                Menu {
                    Button { editingGoal = goal } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { deletingGoal = goal } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(PLColor.tint)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(goal.name)")
            }
            ProgressView(value: min(saved, goal.target), total: max(goal.target, 1))
                .tint(saved >= goal.target ? PLColor.success : PLColor.tint)
            HStack {
                if saved >= goal.target {
                    Text("Reached!").font(.caption.weight(.semibold)).foregroundColor(PLColor.success)
                    Button("I Bought It") { buyingGoal = goal }
                        .font(.caption.weight(.semibold))
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
            if saved < goal.target || model.budget(for: goal) > 0 {
                let budgeted = model.budget(for: goal)
                let needed = goal.monthlyNeeded(saved: saved)
                let short = needed.map { budgeted > 0 && budgeted + 0.5 < $0 } ?? false
                let pausedFor = model.plan.savingsGoals.first { other in
                    other.id != goal.id && (other.cuts ?? []).contains { $0.line.caseInsensitiveCompare(BudgetLine.goal(goal.name)) == .orderedSame }
                }
                budgetRow(line: BudgetLine.goal(goal.name), title: goal.name, budgeted: budgeted, needed: needed,
                          status: saved >= goal.target ? "Not needed now: tap Change to move it to another goal."
                                : pausedFor.map { "Paused while you save for \($0.name). It starts again once you have it." }
                                ?? (budgeted == 0 ? (needed == nil ? "No date: give it what you can." : nil)
                                : short ? "\((needed! - budgeted).dollars()) a month short of reaching it on time."
                                : needed != nil ? "On track." : nil),
                          warn: short && pausedFor == nil)
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

    // MARK: - Wishlist

    private var wishlistCard: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Label("Wishlist", systemImage: "heart").font(.headline)
            ForEach(model.plan.wishlist) { wish in
                wishRow(wish)
                if wish.id != model.plan.wishlist.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    private func wishRow(_ wish: WishItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(wish.item).font(.subheadline.weight(.semibold))
                Spacer()
                Text(wish.price.dollars()).font(.subheadline.monospacedDigit())
            }
            if let goal = model.goal(for: wish) {
                let saved = model.saved(goal)
                ProgressView(value: min(saved, goal.target), total: max(goal.target, 1))
                    .tint(saved >= goal.target ? PLColor.success : PLColor.tint)
                Text(saved >= goal.target ? "Saved up: it's yours when you're ready." : "Saving for it: \(saved.dollars()) so far.")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            } else if wish.readyToDecide() {
                Text("Cooling-off is over. Still want it?").font(.caption.weight(.semibold)).foregroundColor(PLColor.tint)
            } else if let day = Plan.day(wish.remindOn) {
                Text("Thinking it over until \(day.formatted(.dateTime.month(.abbreviated).day())).")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            }
            HStack {
                NavigationLink("Check It") { AffordView(model: model, wish: wish) }
                Spacer()
                Button("Remove", role: .destructive) { model.removeFromWishlist(wish.id) }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
    }

    private func markBought(_ goal: SavingsGoal) async {
        let wish = model.plan.wishlist.first { $0.goalId == goal.id }
        do {
            let r = try await model.bought(goalId: goal.id, wishlistId: wish?.id)
            boughtMessage = "Logged \(r.logged.dollars()) to \(r.category). Enjoy your \(r.item)!"
        } catch {
            boughtMessage = (error as? AffordError)?.message ?? "Couldn't log it right now. Try again in a moment."
        }
    }

    // MARK: - Tools

    private var affordCard: some View {
        NavigationLink {
            AffordView(model: model)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cart.badge.questionmark")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(PLColor.success)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Can I afford it?").font(.headline).foregroundColor(.primary)
                    Text("Check a purchase against your budget and plan.")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundColor(PLColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plCard()
    }

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
                    HStack {
                        Text("Never go below")
                        Spacer()
                        TextField("$0", value: $fund.floor, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                } footer: {
                    Text("“Can I afford it?” never counts money below this, even as a last resort.")
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

// MARK: - Budget amount and check-in sheets

/// which budget line is being set, and from what
struct BudgetLineEdit: Identifiable {
    let line: String          // "Emergency Fund", "Savings - Trip"
    let title: String
    let current: Double
    let suggested: Double
    var id: String { line }
}

/// how much the budget puts toward the emergency fund or a goal each month
struct BudgetAmountSheet: View {
    let edit: BudgetLineEdit
    @ObservedObject var model: PlanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var saving = false
    @State private var problem: String?
    /// where more comes from: nil = Savings, then unassigned money; or another Plan line
    @State private var from: String?

    private var sources: [(line: String, title: String, amount: Double)] { model.otherSources(for: edit.line) }
    private var defaultRoom: Double { model.budgetSavings + (model.unassigned ?? 0) }
    private var most: Double {
        edit.current + (from.flatMap { f in sources.first { $0.line == f }?.amount } ?? defaultRoom)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("$0 a month", value: $amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Each month, for \(edit.title)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sourceText)
                        if let problem { Text(problem).foregroundColor(PLColor.danger) }
                    }
                }
                if !sources.isEmpty {
                    Section {
                        Picker("Comes out of", selection: $from) {
                            Text("Savings (\(defaultRoom.dollars()) free)").tag(String?.none)
                            ForEach(sources, id: \.line) { source in
                                Text("\(source.title) (\(source.amount.dollars()))").tag(String?.some(source.line))
                            }
                        }
                    } footer: {
                        Text("Taking from another goal or the emergency fund lowers what goes to it.")
                    }
                }
                if edit.current > 0 {
                    Section {
                        Button("Take It Out of My Budget", role: .destructive) { Task { await save(0) } }
                    } footer: {
                        Text("Its \(edit.current.dollars()) goes back to Savings.")
                    }
                }
            }
            .navigationTitle(edit.current > 0 ? "Change Budget" : "Add to Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save(amount ?? 0) } }
                        .disabled(saving || amount == nil)
                }
            }
            .onAppear {
                amount = edit.suggested
                // nothing free in Savings: start from the line with the most in it
                if defaultRoom < edit.suggested - edit.current { from = sources.max { $0.amount < $1.amount }?.line }
            }
        }
        .presentationDetents([.medium])
    }

    private var sourceText: String {
        if let from, let source = sources.first(where: { $0.line == from }) {
            return "More comes out of \(source.title) (\(source.amount.dollars()) a month); less goes back to Savings. Up to \(most.dollars()) a month."
        }
        var parts = ["More comes out of Savings (\(model.budgetSavings.dollars()) a month)"]
        if let free = model.unassigned, free > 0 { parts.append("then money your budget doesn't assign (\(free.dollars()))") }
        return parts.joined(separator: ", ") + "; less goes back to Savings. Up to \(most.dollars()) a month."
    }

    private func save(_ value: Double) async {
        saving = true
        defer { saving = false }
        do {
            try await model.setBudgetLine(edit.line, amount: value, from: value > edit.current ? from : nil)
            dismiss()
        } catch let short as NotEnoughInBudget {
            problem = "There's room for up to \(short.available.dollars()) a month from there."
                + (sources.isEmpty ? " Lower another category in Monthly Budget to make room." : " Pick where it comes out of below, or lower another category in Monthly Budget.")
        } catch {
            AppBanner.report("change your budget", error)
        }
    }
}

/// this month's savings, when they moved different amounts than budgeted
struct SavingsCheckInSheet: View {
    let lines: [PlanViewModel.CheckInLine]
    let onSave: ([String: Double]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amounts: [String: Double] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(lines) { line in
                        LabeledContent(line.name) {
                            TextField("$0", value: Binding(get: { amounts[line.id] ?? line.amount },
                                                           set: { amounts[line.id] = max(0, $0) }),
                                      format: .currency(code: "USD"))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                } footer: {
                    Text("What you moved this month. $0 for one you didn't.")
                }
            }
            .navigationTitle("This Month's Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Dictionary(uniqueKeysWithValues: lines.map { ($0.id, amounts[$0.id] ?? $0.amount) }))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
