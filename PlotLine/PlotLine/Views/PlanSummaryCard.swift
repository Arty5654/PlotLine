//
//  PlanSummaryCard.swift
//  PlotLine
//
//  Budgeting page: the Plan tab at a glance (emergency fund, the next goal, the debt-free date,
//  this month's savings to confirm), and "Put your savings to work" (PlanSuggestions).
//

import SwiftUI

struct PlanSummaryCard: View {
    @ObservedObject var model: PlanViewModel
    let openPlan: () -> Void

    private var isEmpty: Bool {
        model.plan.savingsGoals.isEmpty && model.plan.debts.isEmpty && model.emergencySaved == 0 && model.emergencyBudget == 0
    }

    /// the goal with the nearest date that isn't reached (else the first one not reached)
    private var nextGoal: SavingsGoal? {
        let open = model.plan.savingsGoals.filter { model.saved($0) < $0.target }
        return open.filter { $0.targetDate != nil }.min { ($0.targetDate ?? "") < ($1.targetDate ?? "") } ?? open.first
    }

    var body: some View {
        if model.loaded {
            Button(action: openPlan) {
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    HStack {
                        Label("Your plan", systemImage: "target").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundColor(PLColor.textSecondary)
                    }
                    if model.needsCheckIn() {
                        Label("\(Date().formatted(.dateTime.month(.wide))) savings to confirm", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold)).foregroundColor(.orange)
                    }
                    if isEmpty {
                        Text("Set up an emergency fund, savings goals and a debt payoff plan. Your budget puts money toward each.")
                            .font(.subheadline).foregroundColor(PLColor.textSecondary)
                            .multilineTextAlignment(.leading)
                    } else {
                        if let target = model.emergencyTarget {
                            progressRow("Emergency fund", saved: model.emergencySaved, target: target, budgeted: model.emergencyBudget)
                        }
                        if let goal = nextGoal {
                            progressRow(goal.name, saved: model.saved(goal), target: goal.target, budgeted: model.budget(for: goal))
                        }
                        if !model.plan.debts.isEmpty {
                            let result = DebtPayoff.simulate(model.debtsNow, extra: model.plan.extraDebtPayment, strategy: .avalanche)
                            HStack {
                                Text("Debt").font(.subheadline)
                                Spacer()
                                if let date = result.payoffDate() {
                                    Text("Debt-free by \(date.formatted(.dateTime.month(.abbreviated).year()))")
                                        .font(.subheadline.weight(.semibold)).foregroundColor(PLColor.success)
                                } else {
                                    Text("Some debts never get paid off").font(.subheadline).foregroundColor(PLColor.danger)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .plCard()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Plan")
        }
    }

    private func progressRow(_ name: String, saved: Double, target: Double, budgeted: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text("\(saved.dollars()) of \(target.dollars())").font(.subheadline.monospacedDigit())
            }
            ProgressView(value: min(saved, target), total: max(target, 1))
                .tint(saved >= target ? PLColor.success : PLColor.tint)
            if budgeted > 0 && saved < target {
                Text("\(budgeted.dollars()) a month in your budget").font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
    }
}

/// Budgeting → "Put your savings to work": where the budget's saving money should go
struct PlanSuggestionsCard: View {
    @ObservedObject var model: PlanViewModel
    @State private var applying: String?
    @State private var dismissed: [String: String] = PlanSuggestionsCard.loadDismissed()

    private static var key: String {
        "planSuggestionsDismissed.\((UserDefaults.standard.string(forKey: "loggedInUsername") ?? "").lowercased())"
    }

    /// suggestion id → the month it was put off ("Not Now" hides it for the rest of that month)
    private static func loadDismissed() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private var shown: [PlanSuggestion] {
        model.suggestions.filter { dismissed[$0.id] != Plan.monthKey() }
    }

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: PLSpacing.sm) {
                Label("Put your savings to work", systemImage: "arrow.triangle.branch").font(.headline)
                ForEach(shown) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.title).font(.subheadline.weight(.semibold))
                        Text(suggestion.message).font(.caption).foregroundColor(PLColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button {
                                Task { await apply(suggestion) }
                            } label: {
                                if applying == suggestion.id { ProgressView() } else { Text(suggestion.button) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(applying != nil)
                            Button("Not Now") {
                                dismissed[suggestion.id] = Plan.monthKey()
                                UserDefaults.standard.set(dismissed, forKey: Self.key)
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    }
                    if suggestion.id != shown.last?.id { Divider() }
                }
                Text("Changes your budget's savings lines only after you tap. Each one stays in your Plan tab.")
                    .font(.caption2).foregroundColor(PLColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .plCard()
        }
    }

    private func apply(_ suggestion: PlanSuggestion) async {
        applying = suggestion.id
        defer { applying = nil }
        do {
            try await model.apply(suggestion)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            AppBanner.report("change your budget", error)
        }
    }
}
