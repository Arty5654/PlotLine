//
//  DebtPlannerView.swift
//  PlotLine
//
//  Budget → Plan → Debt payoff planner: your debts, an extra monthly payment, and when you'll be
//  debt-free with the avalanche (highest rate first) or snowball (smallest balance first) method.
//

import SwiftUI

struct DebtPlannerView: View {
    @ObservedObject var model: PlanViewModel
    @State private var editingDebt: Debt?
    @State private var extra: Double = 0

    private var debts: [Debt] { model.debtsNow }

    var body: some View {
        List {
            if !model.quizDebtsToOffer.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use the \(model.quizDebtsToOffer.count) debt\(model.quizDebtsToOffer.count == 1 ? "" : "s") from your budget quiz?")
                            .font(.subheadline.weight(.semibold))
                        Text(model.quizDebtsToOffer.map(\.name).joined(separator: ", "))
                            .font(.caption).foregroundColor(PLColor.textSecondary)
                        HStack {
                            Button("Add Them") {
                                let quizDebts = model.quizDebtsToOffer
                                model.update { plan in
                                    plan.debts += quizDebts
                                    plan.importedQuizDebts = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("No Thanks") { model.update { $0.importedQuizDebts = true } }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(debts) { debt in
                    Button { editingDebt = model.plan.debts.first { $0.id == debt.id } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(debt.name).font(.subheadline.weight(.semibold)).foregroundColor(PLColor.textPrimary)
                                Spacer()
                                Text(debt.balance.dollars()).font(.subheadline.monospacedDigit()).foregroundColor(PLColor.textPrimary)
                            }
                            Text("\(debt.apr.formatted(.number.precision(.fractionLength(0...2))))% APR · \(debt.minPayment.dollars()) minimum\(debt.linkedAccountId != nil ? " · linked" : "")")
                                .font(.caption).foregroundColor(PLColor.textSecondary)
                            if DebtPayoff.minimumTooLow(debt) {
                                Label("The minimum doesn't cover the interest, so this never shrinks.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundColor(PLColor.danger)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { debts[$0].id }
                    model.update { $0.debts.removeAll { ids.contains($0.id) } }
                }
                Button {
                    editingDebt = Debt(name: "", balance: 0, apr: 0, minPayment: 0)
                } label: {
                    Label("Add a Debt", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Your debts")
            } footer: {
                if debts.isEmpty { Text("Student loans, credit cards, a car loan…") }
            }

            if !debts.isEmpty {
                Section {
                    HStack {
                        Text("Extra each month")
                        Spacer()
                        TextField("$0", value: $extra, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .onChange(of: extra) { _, value in
                                if max(0, value) != model.plan.extraDebtPayment { model.update { $0.extraDebtPayment = max(0, value) } }
                            }
                    }
                } footer: {
                    Text("On top of the minimums (\(debts.map(\.minPayment).reduce(0, +).dollars()) a month). When a debt is paid off, its minimum goes to the next one.")
                }

                Section("When you'll be debt-free") {
                    ForEach(DebtStrategy.allCases) { strategy in
                        strategyRow(strategy)
                    }
                    minimumsOnlyRow
                }
            }
        }
        .navigationTitle("Debt Payoff")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { extra = model.plan.extraDebtPayment }
        .sheet(item: $editingDebt) { debt in
            DebtEditor(debt: debt, accounts: model.owedAccounts,
                       isNew: !model.plan.debts.contains { $0.id == debt.id },
                       onSave: { saved in
                           model.update { plan in
                               if let i = plan.debts.firstIndex(where: { $0.id == saved.id }) {
                                   plan.debts[i] = saved
                               } else {
                                   plan.debts.append(saved)
                               }
                           }
                       },
                       onDelete: { id in model.update { $0.debts.removeAll { $0.id == id } } })
        }
    }

    private func strategyRow(_ strategy: DebtStrategy) -> some View {
        let result = DebtPayoff.simulate(debts, extra: model.plan.extraDebtPayment, strategy: strategy)
        let other = DebtPayoff.simulate(debts, extra: model.plan.extraDebtPayment,
                                        strategy: strategy == .avalanche ? .snowball : .avalanche)
        let names = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, $0.name) })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strategy.title).font(.headline)
                if strategy == .avalanche, result.totalInterest < other.totalInterest - 0.5 {
                    Text("Saves the most").font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(PLColor.success.opacity(0.15)).foregroundColor(PLColor.success)
                        .clipShape(Capsule())
                }
                Spacer()
                if let date = result.payoffDate() {
                    Text(date.formatted(.dateTime.month(.abbreviated).year())).font(.subheadline.weight(.semibold))
                } else {
                    Text("Never").font(.subheadline.weight(.semibold)).foregroundColor(PLColor.danger)
                }
            }
            Text(strategy.explanation).font(.caption).foregroundColor(PLColor.textSecondary)
            if result.months != nil {
                Text("\(result.months ?? 0) months · \(result.totalInterest.dollars()) interest")
                    .font(.caption.monospacedDigit())
                Text("Order: " + result.order.compactMap { names[$0.id] }.joined(separator: " → "))
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var minimumsOnlyRow: some View {
        let result = DebtPayoff.simulate(debts, extra: 0, strategy: .avalanche, rollover: false)
        let best = DebtPayoff.simulate(debts, extra: model.plan.extraDebtPayment, strategy: .avalanche)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Minimums only").font(.subheadline)
                Spacer()
                if let date = result.payoffDate() {
                    Text(date.formatted(.dateTime.month(.abbreviated).year())).font(.subheadline)
                } else {
                    Text("Never").font(.subheadline).foregroundColor(PLColor.danger)
                }
            }
            if result.months != nil, best.months != nil, result.totalInterest - best.totalInterest >= 1 {
                Text("A plan saves you \((result.totalInterest - best.totalInterest).dollars()) in interest.")
                    .font(.caption).foregroundColor(PLColor.success)
            }
        }
        .foregroundColor(PLColor.textSecondary)
    }
}

struct DebtEditor: View {
    @State var debt: Debt
    let accounts: [LinkedBalance]
    let isNew: Bool
    let onSave: (Debt) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Student loan)", text: $debt.name)
                    if debt.linkedAccountId == nil {
                        LabeledContent("Balance") {
                            TextField("$0", value: $debt.balance, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent("Interest rate (APR %)") {
                        TextField("0", value: $debt.apr, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Minimum payment / month") {
                        TextField("$0", value: $debt.minPayment, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                if !accounts.isEmpty {
                    Section {
                        Picker("Balance from", selection: $debt.linkedAccountId) {
                            Text("Typed in").tag(String?.none)
                            ForEach(accounts) { account in
                                Text("\(account.name) (\(account.balance.dollars()))").tag(String?.some(account.id))
                            }
                        }
                    } footer: {
                        Text("Tie it to a linked card or loan and its balance stays current.")
                    }
                }
                if !isNew {
                    Section { Button("Delete Debt", role: .destructive) { onDelete(debt.id); dismiss() } }
                }
            }
            .navigationTitle(isNew ? "Add a Debt" : "Edit Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        debt.name = debt.name.trimmingCharacters(in: .whitespaces)
                        onSave(debt)
                        dismiss()
                    }
                    .disabled(debt.name.trimmingCharacters(in: .whitespaces).isEmpty || debt.minPayment <= 0
                              || (debt.linkedAccountId == nil && debt.balance <= 0))
                }
            }
        }
    }
}
