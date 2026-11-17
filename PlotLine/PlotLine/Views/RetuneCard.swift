//
//  RetuneCard.swift
//  PlotLine
//
//  Budgeting → "Tune your budget": once a linked bank has a full month of spending, the budget is
//  compared with what was really spent. Each suggestion says where the money comes from (a category
//  you spend less on, money the budget doesn't assign yet) or, when nothing can pay for it, suggests
//  slowing down. Nothing changes until you tap Apply.
//

import SwiftUI

struct RetuneCard: View {
    @State private var retune = Retune()
    @State private var applying: String?
    @State private var dismissed: Set<String> = []
    @State private var applied: String?

    private let preview: Retune?

    init() { preview = nil }

    /// with suggestions already loaded (previews and screenshots)
    init(preview: Retune) {
        self.preview = preview
        _retune = State(initialValue: preview)
    }

    private var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }
    /// dismissals last until a new month of spending is in
    private var dismissKey: String { "retuneDismissed.\(username.lowercased()).\(retune.monthsUsed.first ?? "")" }

    private var visible: [Retune.Suggestion] { retune.suggestions.filter { !dismissed.contains($0.id) } }

    var body: some View {
        Group {
            if retune.ready && (!retune.warnings.isEmpty || !visible.isEmpty || applied != nil) {
                VStack(alignment: .leading, spacing: PLSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Tune your budget", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Text("From what you actually spent in \(monthsText). Nothing changes unless you tap Apply.")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    ForEach(retune.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    if let applied {
                        Label(applied, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(PLColor.success)
                    }
                    ForEach(visible) { suggestion in
                        suggestionView(suggestion)
                        if suggestion.id != visible.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .plCard()
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .budgetQuizCompleted)) { _ in Task { await load() } }
    }

    private var monthsText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let names = retune.monthsUsed.compactMap { f.date(from: $0) }.sorted()
            .map { $0.formatted(.dateTime.month(.wide)) }
        return names.isEmpty ? "recent months" : ListFormatter.localizedString(byJoining: names)
    }

    private func suggestionView(_ s: Retune.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.title).font(.subheadline.weight(.semibold))
            Text(s.message).font(.subheadline).foregroundColor(PLColor.textSecondary)
            if !s.changes.isEmpty {
                Text(changeText(s.changes)).font(.caption).foregroundColor(PLColor.textSecondary)
            }
            HStack(spacing: 8) {
                if !s.changes.isEmpty {
                    Button(applying == s.id ? "Applying…" : "Apply") { apply(s, changes: s.changes, label: s.title) }
                        .buttonStyle(.borderedProminent)
                        .tint(PLColor.accent)
                }
                if let alternative = s.alternative {
                    Button(alternative.label) { apply(s, changes: alternative.changes, label: alternative.label) }
                        .buttonStyle(.bordered)
                }
                Button("Not now") { dismiss(s) }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .font(.subheadline)
            .disabled(applying != nil)
            if let alternative = s.alternative {
                Text(alternative.message).font(.caption2).foregroundColor(PLColor.textSecondary)
            }
        }
    }

    private func changeText(_ changes: [String: Double]) -> String {
        changes.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.dollars())" }.joined(separator: " · ")
    }

    private func load() async {
        guard preview == nil else { return }
        dismissed = []
        guard let fresh = try? await PlanAPI.retune() else { return } // a background check: no banner
        retune = fresh
        dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissKey) ?? [])
    }

    private func dismiss(_ s: Retune.Suggestion) {
        dismissed.insert(s.id)
        UserDefaults.standard.set(Array(dismissed), forKey: dismissKey)
    }

    private func apply(_ s: Retune.Suggestion, changes: [String: Double], label: String) {
        applying = s.id
        Task {
            defer { applying = nil }
            do {
                try await PlanAPI.applyRetune(changes)
                applied = "Done: \(label)."
                dismiss(s)
                NotificationCenter.default.post(name: .budgetQuizCompleted, object: nil) // budget screens reload
            } catch {
                AppBanner.report("update your budget", error, retry: { apply(s, changes: changes, label: label) })
            }
        }
    }
}
