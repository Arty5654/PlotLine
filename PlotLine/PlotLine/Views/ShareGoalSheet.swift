//
//  ShareGoalSheet.swift
//  PlotLine
//
//  Shares a weekly or long-term goal to the Feed (Friends → Feed), with an optional note, to all
//  friends or to the ones you pick. Shows "Shared!" and closes itself.
//

import SwiftUI

struct ShareGoalSheet: View {
    enum Shared {
        case weekly(TaskItem)
        case longTerm(LongTermGoal)
    }

    let goal: Shared
    let username: String

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var friends: [String]?    // nil while loading
    @State private var friendsFailed = false
    @State private var toAllFriends = true
    @State private var chosen: Set<String> = []
    @State private var isSharing = false
    @State private var shared = false

    static let noteLimit = 200

    /// `previewFriends` skips loading the friends list (Xcode previews)
    init(goal: Shared, username: String, previewFriends: [String]? = nil) {
        self.goal = goal
        self.username = username
        _friends = State(initialValue: previewFriends)
    }

    private var hasNoFriends: Bool { friends?.isEmpty == true }
    private var canShare: Bool {
        !isSharing && !shared && !hasNoFriends && (toAllFriends || !chosen.isEmpty) && (friends != nil || friendsFailed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") { preview }

                Section {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: note) { _, text in
                            if text.count > Self.noteLimit { note = String(text.prefix(Self.noteLimit)) }
                        }
                }

                audienceSection
            }
            .navigationTitle("Share to Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(shared)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSharing {
                        ProgressView()
                    } else if !hasNoFriends {
                        Button("Share", action: share)
                            .disabled(!canShare)
                    }
                }
            }
            .overlay {
                if shared { sharedBadge }
            }
            .task { if friends == nil { await loadFriends() } }
        }
        .tint(PLColor.accent)
    }

    // MARK: - Who sees it

    @ViewBuilder
    private var audienceSection: some View {
        if let friends {
            if friends.isEmpty {
                Section("Share with") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You haven't added any friends yet")
                            .font(.headline)
                        Text("Add friends to share your goals with them. They'll see them in their Feed and can like and comment.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .padding(.vertical, 4)
                    Button {
                        dismiss()
                        // the Friends page opens from the home screen once this sheet has closed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            NotificationCenter.default.post(name: .plotlineDeepLink, object: nil, userInfo: ["destination": "friends"])
                        }
                    } label: {
                        Label("Find Friends", systemImage: "person.badge.plus")
                    }
                }
            } else {
                Section {
                    Toggle("All friends", isOn: $toAllFriends.animation())
                    if !toAllFriends {
                        ForEach(friends, id: \.self) { friend in
                            friendRow(friend)
                        }
                    }
                } header: {
                    HStack {
                        Text("Share with")
                        Spacer()
                        if !toAllFriends {
                            Button(chosen.count == friends.count ? "Clear" : "Select all") {
                                chosen = chosen.count == friends.count ? [] : Set(friends)
                            }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                } footer: {
                    Text(toAllFriends
                         ? "Everyone you're friends with, including friends you add later. It shows in your Feed too, where you can unshare it."
                         : chosen.isEmpty ? "Pick at least one friend." : "Only \(chosen.count == 1 ? "this friend" : "these \(chosen.count) friends") will see it.")
                }
            }
        } else if friendsFailed {
            Section("Share with") {
                Text("Couldn't load your friends, so this will go to all of them.")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
                Button("Try again") { Task { await loadFriends() } }
            }
        } else {
            Section("Share with") {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading your friends…").foregroundColor(PLColor.textSecondary)
                }
            }
        }
    }

    private func friendRow(_ friend: String) -> some View {
        let isOn = chosen.contains(friend)
        return Button {
            if isOn { chosen.remove(friend) } else { chosen.insert(friend) }
        } label: {
            HStack(spacing: 12) {
                FriendProfilePicture(username: friend)
                    .frame(width: 28, height: 28)
                Text(friend).foregroundColor(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? PLColor.tint : Color.secondary)
                    .font(.title3)
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var sharedBadge: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(PLColor.success)
            Text("Shared!")
                .font(.title3.bold())
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .transition(.scale.combined(with: .opacity))
    }

    private func loadFriends() async {
        friendsFailed = false
        do {
            friends = try await FriendsAPI.fetchFriendList(username: username).friends.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        } catch {
            friendsFailed = true
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch goal {
        case .weekly(let task):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.isCompleted ? PLColor.success : PLColor.textSecondary)
                    Text(task.name).font(.headline)
                }
                Text(["Weekly goal", task.priority.rawValue + " priority",
                      task.dueDate.map { "Due \(WeeklyGoalsView.shortDate($0))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }
        case .longTerm(let longTerm):
            VStack(alignment: .leading, spacing: 4) {
                Text(longTerm.title).font(.headline)
                let done = longTerm.steps.filter(\.isCompleted).count
                Text("Long-term goal · \(done) of \(longTerm.steps.count) steps done")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }
        }
    }

    private func share() {
        isSharing = true
        let audience = toAllFriends ? nil : Array(chosen).sorted()
        Task {
            do {
                try await Self.post(goal, note: note, audience: audience, username: username)
                isSharing = false
                withAnimation(.spring(duration: 0.3)) { shared = true }
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                isSharing = false
                AppBanner.report("share your goal", error, retry: { share() })
            }
        }
    }

    static func post(_ goal: Shared, note: String, audience: [String]? = nil, username: String) async throws {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post") else {
            throw URLError(.badURL)
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var post: FriendPost
        switch goal {
        case .weekly(let task):
            post = FriendPost(id: UUID(), username: username,
                              goal: LongTermGoal(id: UUID(), title: task.name, steps: []),
                              weeklyGoal: WeeklyGoalShare(name: task.name, priority: task.priority.rawValue,
                                                          dueDate: task.dueDate.map { GoalReminder.dayFormatter.string(from: $0) },
                                                          completed: task.isCompleted),
                              comment: trimmed.isEmpty ? nil : trimmed, audience: audience)
        case .longTerm(let longTerm):
            post = FriendPost(id: UUID(), username: username, goal: longTerm,
                              comment: trimmed.isEmpty ? nil : trimmed, audience: audience)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        request.httpBody = try JSONEncoder().encode(post)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
