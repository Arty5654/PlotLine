//
//  BankTransactionsView.swift
//  PlotLine
//
//  From the budget quiz's "what you usually spend": the bank transactions behind a category (or all
//  of them), and how each one was sorted — your bank's label, a store PlotLine knows, sorted by AI
//  from the name, or a rule you set. Swipe one to remove it (not counted, and kept out of Monthly
//  Costs) or move it (just this one, or always for that place); the monthly amounts update right away.
//  Only spending is counted: money moved between accounts, card payments and pay aren't.
//

import SwiftUI

struct BankTransactionsView: View {
    @ObservedObject var model: BudgetQuizModel
    /// "" for all of them
    let category: String

    @Environment(\.dismiss) private var dismiss
    @State private var moving: BankTransaction?
    /// Move: all purchases from this place (a rule), or just this one
    @State private var wholePlace = false
    @State private var newCategory = ""
    @State private var saving = false

    private var shown: [BankTransaction] {
        let all = model.transactionsShown(for: category)
        return category.isEmpty ? all : all.filter { $0.category == category }
    }

    /// removed ones that would otherwise be in this list
    private var removed: [BankTransaction] {
        model.removedBankTransactions.filter { category.isEmpty || $0.category == category || $0.niches.contains(category) }
    }

    private var total: Double { shown.map(\.amount).reduce(0, +) }
    private var months: Double { max(1, model.bankMonths) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(total.dollars()) over the last \(Int(months.rounded())) month\(months.rounded() == 1 ? "" : "s")")
                            .font(.headline)
                        Text("Money moved between your accounts, card payments and pay aren't counted.")
                            .font(.caption).foregroundColor(PLColor.textSecondary)
                    }
                }
                Section {
                    ForEach(shown) { t in
                        Button { startMove(t) } label: { row(t) }
                            .buttonStyle(.plain)
                            .disabled(saving || t.txnId.isEmpty)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !t.txnId.isEmpty {
                                    Button(role: .destructive) { model.removeBankTransaction(t) } label: { Label("Remove", systemImage: "minus.circle") }
                                    Button { startMove(t) } label: { Label("Move", systemImage: "arrow.right.circle") }.tint(.blue)
                                    if moved(t) {
                                        Button { model.restoreBankTransaction(t) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.tint(.gray)
                                    }
                                }
                            }
                    }
                } footer: {
                    Text("Swipe a purchase to remove it (a one-off, or not yours) or move it to another category. Your budget uses the new amounts.")
                }
                if !removed.isEmpty {
                    Section {
                        ForEach(removed) { t in
                            row(t)
                                .opacity(0.5)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button { model.restoreBankTransaction(t) } label: { Label("Put Back", systemImage: "arrow.uturn.backward") }.tint(.blue)
                                }
                        }
                    } header: {
                        Text("Not counted")
                    } footer: {
                        Text("Left out of what you usually spend, and of Monthly Costs. Swipe to put one back.")
                    }
                }
            }
            .overlay { if saving { ProgressView() } }
            .navigationTitle(category.isEmpty ? "Your Transactions" : category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $moving) { t in categoryPicker(t) }
        }
    }

    private func moved(_ t: BankTransaction) -> Bool {
        if let edit = model.bankEdits[t.txnId], !edit.isEmpty { return true }
        return false
    }

    private func startMove(_ t: BankTransaction) {
        wholePlace = false
        newCategory = ""
        moving = t
    }

    /// Move: just this one or everything from the place, to a category they have or a new one
    private func categoryPicker(_ t: BankTransaction) -> some View {
        NavigationStack {
            List {
                Section {
                    Picker("Move", selection: $wholePlace) {
                        Text("Just this one").tag(false)
                        Text("All from this place").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(wholePlace
                         ? "Every purchase from \(t.name) goes there: in your budget, in Monthly Costs (the last 3 months) and from now on."
                         : "Only this purchase moves.")
                }
                Section("New category") {
                    HStack {
                        TextField("Name", text: $newCategory)
                            .submitLabel(.done)
                            .onSubmit { move(t, to: newCategory) }
                        Button("Move") { move(t, to: newCategory) }
                            .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section {
                    ForEach(model.placeChoices, id: \.self) { choice in
                        Button {
                            move(t, to: choice)
                        } label: {
                            HStack {
                                Text(choice).foregroundColor(PLColor.textPrimary)
                                Spacer()
                                if choice == t.category { Image(systemName: "checkmark").foregroundColor(PLColor.accent) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move \(t.name) to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { moving = nil } } }
        }
    }

    private func move(_ t: BankTransaction, to category: String) {
        let name = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        moving = nil
        if wholePlace {
            Task {
                saving = true
                _ = await model.alwaysPut(t.name, in: name)
                saving = false
            }
        } else if name != t.category || moved(t) {
            model.moveBankTransaction(t, to: name)
        }
    }

    private func row(_ t: BankTransaction) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(.subheadline.weight(.semibold))
                Text(subtitle(t))
                    .font(.caption).foregroundColor(t.how == "none" && !moved(t) ? .orange : PLColor.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(t.amount.dollars(cents: true)).font(.subheadline).monospacedDigit()
                    .foregroundColor(t.amount < 0 ? PLColor.success : .primary)
                Text(t.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ t: BankTransaction) -> String {
        let refund = t.amount < 0 ? "Refund · " : ""
        let how = moved(t) ? "Moved by you" : t.howText
        return refund + (category.isEmpty ? "\(t.category) · \(how)" : how)
    }
}
