//
//  GetStartedCard.swift
//  PlotLine
//
//  The "Get Started" card at the top of Home: budget quiz → link a bank → first goal → add a
//  friend → turn on notifications. Each step checks itself off when it's actually done (so people
//  who already did some see them ticked), the card can be skipped anytime, and finishing it earns
//  the Getting Started trophy.
//

import SwiftUI

@MainActor
final class GetStartedModel: ObservableObject {

    enum Step: String, CaseIterable, Identifiable {
        case quiz, bank, goal, friends, notifications
        var id: String { rawValue }

        var title: String {
            switch self {
            case .quiz: return "Take the budget quiz"
            case .bank: return "Link your bank"
            case .goal: return "Set your first goal"
            case .friends: return "Add a friend"
            case .notifications: return "Turn on notifications"
            }
        }

        var detail: String {
            switch self {
            case .quiz: return "A budget built around your income and city."
            case .bank: return "Optional: spending fills itself in."
            case .goal: return "Weekly or long-term."
            case .friends: return "Share goals, lists and calendars."
            case .notifications: return "Reminders, invites and your Sunday recap."
            }
        }

        var icon: String {
            switch self {
            case .quiz: return "sparkles"
            case .bank: return "building.columns"
            case .goal: return "target"
            case .friends: return "person.2"
            case .notifications: return "bell.badge"
            }
        }
    }

    @Published private(set) var done: Set<Step> = []
    @Published private(set) var loaded = false

    init() { }

    /// already checked, for previews and screenshots
    init(preview done: Set<Step>) {
        self.done = done
        self.loaded = true
    }
    @Published private(set) var hidden = false
    @Published private(set) var justFinished = false

    private var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }
    private var hiddenKey: String { "getStartedHidden.\(username.lowercased())" }
    private var finishedKey: String { "getStartedFinished.\(username.lowercased())" }

    var showsCard: Bool {
        !hidden && loaded && (!UserDefaults.standard.bool(forKey: finishedKey) || justFinished)
    }

    var nextStep: Step? { Step.allCases.first { !done.contains($0) } }

    /// Checks each step against the account (friends come from the friends list already loaded).
    func refresh(friendCount: Int) async {
        hidden = UserDefaults.standard.bool(forKey: hiddenKey)
        guard !hidden, !UserDefaults.standard.bool(forKey: finishedKey), !username.isEmpty else {
            loaded = true
            return
        }
        async let quiz = Self.hasContent("/api/llm/budget/last/\(username)")
        async let bank = Self.hasContent("/api/plaid/accounts?username=\(username)")
        async let weekly = Self.hasContent("/api/goals/\(username)", listsOnly: true)
        async let longTerm = Self.hasContent("/api/goals/\(username)/long-term", listsOnly: true)
        async let notifications = NotificationPermission.status()

        var now = done // a step that failed to check keeps its last answer
        if let v = await quiz { set(.quiz, v, in: &now) }
        if let v = await bank { set(.bank, v, in: &now) }
        let weeklyGoals = await weekly, longTermGoals = await longTerm
        if weeklyGoals != nil || longTermGoals != nil { set(.goal, weeklyGoals == true || longTermGoals == true, in: &now) }
        set(.friends, friendCount > 0, in: &now)
        set(.notifications, NotificationPermission.isAllowed(await notifications), in: &now)
        done = now
        loaded = true
        finishIfDone()
    }

    private func set(_ step: Step, _ isDone: Bool, in steps: inout Set<Step>) {
        if isDone { steps.insert(step) } else { steps.remove(step) }
    }

    /// the last step, here on the card
    func turnOnNotifications() async {
        if await NotificationPermission.ensure(for: "reminders, invites and your Sunday budget recap") {
            done.insert(.notifications)
            finishIfDone()
        }
    }

    func hide() {
        UserDefaults.standard.set(true, forKey: hiddenKey)
        withAnimation { hidden = true }
    }

    /// all five: the trophy, then the card says "You're all set" until it's closed
    private func finishIfDone() {
        guard done.count == Step.allCases.count, !UserDefaults.standard.bool(forKey: finishedKey) else { return }
        UserDefaults.standard.set(true, forKey: finishedKey)
        justFinished = true
        let user = username
        Task { await ProfileAPI.incrementTrophy(username: user, trophyId: "getting-started") }
    }

    /// true when the server has something there: a saved quiz, a linked account, a goal
    static func hasContent(_ path: String, listsOnly: Bool = false) async -> Bool? {
        guard let url = URL(string: "\(BackendConfig.baseURLString)\(path)") else { return nil }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 204 || http.statusCode == 404 { return false }
        guard (200...299).contains(http.statusCode) else { return nil }
        return hasContent(data, listsOnly: listsOnly)
    }

    /// Something there: a saved quiz (any object), linked accounts (a list). With `listsOnly`, an
    /// object counts only if one of its lists has something ({"weeklyGoals": [...]}).
    static func hasContent(_ data: Data, listsOnly: Bool = false) -> Bool {
        guard !data.isEmpty, let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        if let array = json as? [Any] { return !array.isEmpty }
        if let object = json as? [String: Any] {
            guard listsOnly else { return !object.isEmpty }
            return object.values.contains { ($0 as? [Any])?.isEmpty == false }
        }
        return false
    }
}

struct GetStartedCard: View {
    @ObservedObject var model: GetStartedModel
    let openQuiz: () -> Void
    let openBudget: () -> Void
    let openGoals: () -> Void
    let openFriends: () -> Void

    @State private var confirmSkip = false
    @State private var showQuizFirst = false

    private var total: Int { GetStartedModel.Step.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.justFinished ? "You're all set!" : "Get Started")
                        .font(.headline)
                    Text(model.justFinished ? "You earned the Getting Started trophy."
                                            : "\(model.done.count) of \(total) done")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                }
                Spacer()
                Button {
                    if model.justFinished { model.hide() } else { confirmSkip = true }
                } label: {
                    Text(model.justFinished ? "Close" : "Skip")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityHint("Hides the Get Started checklist")
            }

            ProgressView(value: Double(model.done.count), total: Double(total))
                .tint(PLColor.success)

            if !model.justFinished {
                VStack(spacing: 0) {
                    ForEach(GetStartedModel.Step.allCases) { step in
                        if step != .quiz { Divider().padding(.leading, 40) }
                        row(step)
                    }
                }
            }
        }
        .plCard()
        .alert("Take the Budget Quiz First", isPresented: $showQuizFirst) {
            Button("Take the Quiz") { openQuiz() }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Linking your bank adds your spending to your budget, so you'll need a budget first. The quiz builds one in a couple of minutes.")
        }
        .confirmationDialog("Skip the Get Started checklist?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Skip Checklist") { model.hide() }
            Button("Keep It", role: .cancel) { }
        } message: {
            Text("Everything stays in the app; the card just goes away.")
        }
    }

    private func row(_ step: GetStartedModel.Step) -> some View {
        let isDone = model.done.contains(step)
        let isNext = model.nextStep == step
        // the bank adds spending to a budget: there has to be one first
        let waitsForQuiz = step == .bank && !isDone && !model.done.contains(.quiz)
        return Button {
            switch step {
            case .quiz: openQuiz()
            case .bank: if waitsForQuiz { showQuizFirst = true } else { openBudget() }
            case .goal: openGoals()
            case .friends: openFriends()
            case .notifications: Task { await model.turnOnNotifications() }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : waitsForQuiz ? "lock.fill" : step.icon)
                    .font(.title3)
                    .foregroundColor(isDone ? PLColor.success : isNext && !waitsForQuiz ? PLColor.tint : PLColor.textSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.title)
                        .font(.subheadline.weight(isNext ? .semibold : .regular))
                        .foregroundColor(isDone ? PLColor.textSecondary : PLColor.textPrimary)
                        .strikethrough(isDone, color: PLColor.textSecondary)
                    if waitsForQuiz {
                        Text("Take the budget quiz first.")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    } else if !isDone {
                        Text(step.detail)
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                }
                Spacer()
                if !isDone {
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(PLColor.textSecondary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDone)
        .accessibilityLabel("\(step.title)\(isDone ? ", done" : waitsForQuiz ? ", take the budget quiz first" : "")")
    }
}
