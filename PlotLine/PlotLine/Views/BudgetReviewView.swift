//
//  BudgetReviewView.swift
//  PlotLine
//
//  After the quiz builds a budget: check it before it's saved. Shows what you bring home, how much
//  goes to needs / wants / savings, housing and savings as a share, warnings, and every line with
//  why it got that amount and (with a linked bank) what you usually spend. Any line can be changed;
//  Rebalance then fits the rest to take-home on the phone, and Rebuild with AI redoes the rest
//  around the changes. Nothing is saved until Save.
//

import SwiftUI

struct BudgetReviewView: View {
    @ObservedObject var model: BudgetQuizModel
    /// Regenerate on the budget page: the categories just added (kept as estimated when making room) and
    /// the lines that were already there (fixed for the AI, but they can be lowered to make room)
    var newCategories: [String] = []
    var adjustable: Set<String> = []
    let onSaved: () -> Void

    @EnvironmentObject private var calendarVM: CalendarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: BudgetQuizModel.Draft
    @State private var amounts: [String: Double]
    @State private var expanded: Set<String> = []
    @State private var saving = false
    /// lines they changed here: Rebalance and Rebuild keep them as typed
    @State private var edited: Set<String> = []
    /// what lines were before the last Rebalance or Rebuild ("was $300")
    @State private var before: [String: Double] = [:]
    @State private var adjustMessage: String?
    @State private var rebuilding = false
    @State private var rebuildError: String?
    /// the line whose transactions are open
    @State private var transactionsFor: String?

    init(model: BudgetQuizModel, draft: BudgetQuizModel.Draft, newCategories: [String] = [], adjustable: Set<String> = [],
         onSaved: @escaping () -> Void) {
        self.model = model
        self.newCategories = newCategories
        self.adjustable = adjustable
        self.onSaved = onSaved
        _draft = State(initialValue: draft)
        _amounts = State(initialValue: draft.budget)
    }

    private var style: BudgetingStyleChoice { BudgetingStyleChoice(rawValue: draft.budgetingStyle ?? "") ?? model.budgetingStyle }
    private var summary: BudgetReview.Summary { BudgetReview.summary(amounts, takeHome: draft.monthlyNet) }
    private var warnings: [BudgetReview.Warning] { BudgetReview.warnings(summary, style: style, savePercent: draft.savePercent ?? model.savePercent) }

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                if hasHeadsUp { Section { headsUp } }
                if fit != nil { Section { fitCard } }
                if !warnings.isEmpty {
                    Section {
                        ForEach(warnings) { w in
                            Label(w.text, systemImage: w.severe ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(w.severe ? PLColor.danger : .orange)
                                .font(.subheadline)
                        }
                    }
                }
                Section { adjustButtons }
                ForEach(BudgetLineKind.allCases, id: \.self) { kind in
                    let lines = amounts.keys.filter { BudgetReview.kind(of: $0) == kind }.sorted()
                    if !lines.isEmpty {
                        Section {
                            ForEach(lines, id: \.self) { line($0) }
                        } header: {
                            HStack {
                                Text(kind.rawValue)
                                Spacer()
                                Text("\((summary.byKind[kind] ?? 0).dollars()) · \(BudgetReview.percent(summary.share(summary.byKind[kind] ?? 0)))")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Your Budget")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    Group {
                        if saving { ProgressView().tint(.white) }
                        else { Text(summary.unassigned < -0.5 ? "Save Anyway" : "Save Budget") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton(color: summary.unassigned < -0.5 ? PLColor.danger : PLColor.accent))
                .disabled(saving)
                .padding(PLSpacing.lg)
                .background(.bar)
            }
        }
        .sheet(isPresented: Binding(get: { transactionsFor != nil }, set: { if !$0 { transactionsFor = nil } })) {
            BankTransactionsView(model: model, category: transactionsFor ?? "")
        }
        .alert("Couldn't rebuild your budget", isPresented: Binding(get: { rebuildError != nil }, set: { if !$0 { rebuildError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(rebuildError ?? "")
        }
    }

    /// their real spending is higher than this plan (from the server: categories well above the plan)
    private var hasHeadsUp: Bool {
        !(draft.overspending ?? []).isEmpty || (draft.usualTotal ?? 0) > draft.monthlyNet + 0.5
    }

    private var headsUp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Heads up: you usually spend more", systemImage: "exclamationmark.bubble.fill")
                .font(.headline).foregroundColor(.orange)
            if let usual = draft.usualTotal, usual > draft.monthlyNet + 0.5 {
                Text("Lately you've spent about \(usual.dollars()) a month, more than you bring home (\(draft.monthlyNet.dollars())). Sticking to this plan means spending less.")
                    .font(.subheadline).foregroundColor(PLColor.textSecondary)
            }
            ForEach(draft.overspending ?? [], id: \.category) { o in
                HStack {
                    Text(o.category)
                    Spacer()
                    Text("usually \(o.usual.dollars()), plan \(o.planned.dollars())").monospacedDigit().foregroundColor(PLColor.textSecondary)
                }
                .font(.subheadline)
            }
            if !(draft.overspending ?? []).isEmpty {
                Text("These are where to cut back to stay on budget.").font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// never changed to make room: lines they changed here, bills and debt minimums, and new categories
    private var lockedLines: Set<String> {
        edited.union(Set(draft.fixed ?? []).subtracting(adjustable)).union(newCategories)
    }

    private var savingsFloor: Double {
        BudgetReview.savingsFloor(style: style, savePercent: draft.savePercent ?? model.savePercent, takeHome: draft.monthlyNet)
    }

    /// over take-home: what to lower to make it fit (wants first, then savings down to the plan)
    private var fit: BudgetReview.Rebalanced? {
        guard summary.unassigned < -0.5 else { return nil }
        return BudgetReview.rebalance(amounts, takeHome: draft.monthlyNet, locked: lockedLines, savingsFloor: savingsFloor)
    }

    /// the lines a rebalance lowers, biggest cut first
    private func loweredLines(_ after: [String: Double]) -> [String] {
        let cut: (String) -> Double = { line in (amounts[line] ?? 0) - (after[line] ?? 0) }
        return amounts.keys.filter { cut($0) > 0 }.sorted { cut($0) > cut($1) }
    }

    @ViewBuilder private var fitCard: some View {
        if let fit {
            let changes = loweredLines(fit.budget)
            VStack(alignment: .leading, spacing: 8) {
                Text("Doesn't fit by \((-summary.unassigned).dollars())").font(.headline)
                if changes.isEmpty {
                    Text("There's nothing flexible left to lower: your bills and the lines you set are more than you bring home. Lower one of them, or Save Anyway.")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                } else {
                    Text(newCategories.isEmpty ? "To make room, lower:" : "To make room for \(ListFormatter.localizedString(byJoining: newCategories)), lower:")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                    ForEach(changes, id: \.self) { line in
                        HStack {
                            Text(line)
                            Spacer()
                            Text("\((amounts[line] ?? 0).dollars()) → \((fit.budget[line] ?? 0).dollars())").monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    if fit.stillOver > 0 {
                        Text("Even then it's \(fit.stillOver.dollars()) over; lower a bill or another line too.")
                            .font(.caption).foregroundColor(.orange)
                    }
                    Button("Apply These") {
                        before = amounts.filter { fit.budget[$0.key] != $0.value }
                        withAnimation { amounts = fit.budget }
                        adjustMessage = "Lowered to make room. Lines that changed show what they were."
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var adjustButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    rebalance()
                } label: {
                    Label("Rebalance", systemImage: "scalemass")
                }
                .buttonStyle(.bordered)
                .disabled(abs(summary.unassigned) < 1 || rebuilding)
                Button {
                    Task { await rebuild() }
                } label: {
                    Label(rebuilding ? "Rebuilding…" : "Rebuild with AI", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(rebuilding || saving)
            }
            .font(.subheadline)
            if let adjustMessage {
                Text(adjustMessage).font(.caption).foregroundColor(PLColor.textSecondary)
            } else {
                Text(edited.isEmpty
                     ? "Change any line, then Rebalance to fit the rest to your take-home, or Rebuild with AI to redo the rest around it."
                     : "Lines you changed and your fixed bills stay as they are. Rebalance trims wants first, then savings (never below your plan), and puts anything left in Savings. Rebuild with AI redoes the rest (uses your daily AI limit).")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func rebalance() {
        let result = BudgetReview.rebalance(amounts, takeHome: draft.monthlyNet, locked: lockedLines, savingsFloor: savingsFloor)
        before = amounts.filter { result.budget[$0.key] != $0.value }
        withAnimation { amounts = result.budget }
        adjustMessage = result.stillOver > 0
            ? "Still \(result.stillOver.dollars()) over: your bills and the lines you changed add up to more than you bring home. Lower one of them, or Save Anyway."
            : before.isEmpty ? "Nothing to change." : "Rebalanced. Lines that changed show what they were."
    }

    private func rebuild() async {
        rebuilding = true
        defer { rebuilding = false }
        do {
            let fresh = try await model.build(overrides: amounts.filter { edited.contains($0.key) })
            before = amounts.filter { fresh.budget[$0.key] != $0.value }
            draft = fresh
            withAnimation { amounts = fresh.budget }
            adjustMessage = "Rebuilt around your changes. Lines that changed show what they were."
        } catch {
            rebuildError = (error as? AILimitError)?.message ?? "Please try again in a moment."
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("You bring home").font(.caption).foregroundColor(PLColor.textSecondary)
                    Text(draft.monthlyNet.dollars()).font(.title3.weight(.bold))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Planned").font(.caption).foregroundColor(PLColor.textSecondary)
                    Text(summary.total.dollars()).font(.title3.weight(.bold))
                        .foregroundColor(summary.unassigned < -0.5 ? PLColor.danger : PLColor.textPrimary)
                }
            }
            if summary.unassigned >= 0.5 {
                Text("\(summary.unassigned.dollars()) a month left unassigned").font(.caption).foregroundColor(PLColor.textSecondary)
            }
            shareBar
            // what the colors are
            HStack(spacing: 12) {
                ForEach(BudgetLineKind.allCases, id: \.self) { kind in
                    HStack(spacing: 4) {
                        Circle().fill(color(kind)).frame(width: 8, height: 8)
                        Text("\(kind == .saving ? "Savings" : kind.rawValue) \((summary.byKind[kind] ?? 0).dollars())")
                            .font(.caption2).foregroundColor(PLColor.textSecondary)
                    }
                }
            }
            HStack(spacing: 16) {
                stat("Housing", BudgetReview.percent(summary.housingShare), target: "aim ≤35%")
                stat("Saving", BudgetReview.percent(summary.savingsShare),
                     target: style == .payYourselfFirst ? "plan \(Int(draft.savePercent ?? model.savePercent))%" : style == .fiftyThirtyTwenty ? "plan 20%" : "10–20%")
            }
            Text("Tap a line to see why it got that amount. Change any amount before saving.")
                .font(.caption2).foregroundColor(PLColor.textSecondary)
        }
        .padding(.vertical, 4)
    }

    /// needs / wants / savings as parts of take-home
    private var shareBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(BudgetLineKind.allCases, id: \.self) { kind in
                    let share = min(1, summary.share(summary.byKind[kind] ?? 0))
                    Rectangle()
                        .fill(color(kind))
                        .frame(width: max(0, geo.size.width * share - 2))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func color(_ kind: BudgetLineKind) -> Color {
        switch kind {
        case .need: return PLColor.accent
        case .want: return .orange
        case .saving: return PLColor.success
        }
    }

    private func stat(_ name: String, _ value: String, target: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.caption).foregroundColor(PLColor.textSecondary)
            Text(value).font(.headline)
            Text(target).font(.caption2).foregroundColor(PLColor.textSecondary)
        }
    }

    private func line(_ category: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    if expanded.contains(category) { expanded.remove(category) } else { expanded.insert(category) }
                } label: {
                    HStack(spacing: 4) {
                        Text(category).foregroundColor(PLColor.textPrimary)
                        if draft.why[category] != nil {
                            Image(systemName: "info.circle").font(.caption).foregroundColor(PLColor.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                TextField("$0", value: Binding(get: { amounts[category] ?? 0 },
                                               set: { amounts[category] = max(0, $0); edited.insert(category); before[category] = nil }),
                          format: .currency(code: "USD").precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
            if let was = before[category] {
                Text("Was \(was.dollars())").font(.caption).foregroundColor(.orange)
            }
            if let usual = model.bankAverages[category], usual > 0 {
                // see the transactions behind it
                Button {
                    transactionsFor = category
                } label: {
                    HStack(spacing: 4) {
                        Text("You usually spend \(usual.dollars()) (from your transactions)")
                        if model.sortedBankTransactions.contains(where: { $0.category == category }) {
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                    }
                    .font(.caption).foregroundColor(PLColor.textSecondary)
                }
                .buttonStyle(.borderless)
                .disabled(!model.sortedBankTransactions.contains { $0.category == category })
            }
            if expanded.contains(category), let why = draft.why[category] {
                Text(why).font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await model.save(budget: amounts.mapValues { $0.rounded() }, draft: draft, calendarVM: calendarVM)
                onSaved()
            } catch {
                AppBanner.report("save your budget", error, retry: { save() })
            }
        }
    }
}
