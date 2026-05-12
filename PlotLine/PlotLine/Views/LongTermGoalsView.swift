import SwiftUI

// MARK: - Design tokens

private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.06)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let success       = Color.green
    static let danger        = Color.red
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius { static let md: CGFloat = 12 }

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

// MARK: - View

struct LongTermGoalsView: View {
    @Binding var longTermGoals: [LongTermGoal]
    @Binding var newLongTermTitle: String
    @Binding var newStep: String
    @Binding var newLongTermSteps: [String]
    let username: String

    @Environment(\.colorScheme) var colorScheme

    @State private var archivedGoals: [LongTermGoal] = []
    @State private var showArchiveSheet = false
    @State private var shareAlertMessage = ""
    @State private var showShareAlert = false

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {

                // ── Create new goal card ──
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Label("New Long-Term Goal", systemImage: "flag.fill")
                        .font(.headline)
                        .foregroundColor(adaptiveTextColor)

                    TextField("Goal title", text: $newLongTermTitle)
                        .textFieldStyle(.roundedBorder)
                        .tint(adaptiveTextColor)

                    HStack(spacing: PLSpacing.sm) {
                        TextField("Add a step", text: $newStep)
                            .textFieldStyle(.roundedBorder)
                            .tint(adaptiveTextColor)

                        Button {
                            guard !newStep.isEmpty else { return }
                            newLongTermSteps.append(newStep)
                            newStep = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(adaptiveTextColor)
                        }
                        .buttonStyle(.plain)
                    }

                    if !newLongTermSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Steps")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                            ForEach(newLongTermSteps, id: \.self) { step in
                                HStack(spacing: 6) {
                                    Circle().fill(adaptiveTextColor).frame(width: 6, height: 6)
                                    Text(step)
                                        .font(.subheadline)
                                        .foregroundColor(PLColor.textPrimary)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }

                    Button(action: addLongTermGoal) {
                        Text("Save Goal")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(PLColor.success)
                            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    }
                    .disabled(newLongTermTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newLongTermTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                }
                .plCard()

                // ── Active goals ──
                if longTermGoals.isEmpty {
                    VStack(spacing: PLSpacing.sm) {
                        Image(systemName: "flag")
                            .font(.system(size: 36))
                            .foregroundColor(PLColor.textSecondary)
                            .padding(.bottom, 4)
                        Text("No long-term goals yet")
                            .font(.headline)
                            .foregroundColor(PLColor.textSecondary)
                        Text("Create one above to get started.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .plCard()
                } else {
                    ForEach(longTermGoals) { goal in
                        goalCard(goal)
                    }
                }

                // ── Action buttons ──
                HStack(spacing: PLSpacing.sm) {
                    Button(action: { showArchiveSheet = true }) {
                        Label("Archived", systemImage: "archivebox")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    }

                    Button(action: resetLongTermGoals) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(PLColor.danger)
                            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    }
                }
                .plCard()
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
        }
        .sheet(isPresented: $showArchiveSheet) {
            ArchivedGoalsView(
                archivedGoals: $archivedGoals,
                unarchiveGoal: { unarchiveGoal($0) },
                shareGoalToFriends: { shareGoalToFriends(goal: $0) }
            )
        }
        .alert("Friends Feed", isPresented: $showShareAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareAlertMessage)
        }
    }

    // MARK: - Goal card

    private func goalCard(_ goal: LongTermGoal) -> some View {
        let completedSteps = goal.steps.filter { $0.isCompleted }.count
        let totalSteps = goal.steps.count
        let progress = totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : 0.0

        return VStack(alignment: .leading, spacing: PLSpacing.md) {
            // Header
            HStack {
                Text(goal.title)
                    .font(.title3).bold()
                    .foregroundColor(PLColor.textPrimary)
                Spacer()
                Button { archiveGoal(goal) } label: {
                    Image(systemName: "archivebox")
                        .foregroundColor(adaptiveTextColor)
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }

            // Progress
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(PLColor.success)
                Text("\(Int(progress * 100))% complete — \(completedSteps) of \(totalSteps) steps")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }

            // Steps
            if !goal.steps.isEmpty {
                Divider()
                VStack(spacing: PLSpacing.xs) {
                    ForEach(goal.steps) { step in
                        HStack(spacing: PLSpacing.md) {
                            Text(step.name)
                                .font(.subheadline)
                                .strikethrough(step.isCompleted)
                                .foregroundColor(step.isCompleted ? PLColor.textSecondary : PLColor.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button { toggleLongStepCompletion(goalId: goal.id, stepId: step.id) } label: {
                                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(step.isCompleted ? PLColor.success : PLColor.textSecondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .plCard()
    }

    // MARK: - Logic (unchanged)

    private func archiveGoal(_ goal: LongTermGoal) {
        longTermGoals.removeAll { $0.id == goal.id }
        archivedGoals.append(goal)

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/\(goal.id)/archive") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func unarchiveGoal(_ goal: LongTermGoal) {
        archivedGoals.removeAll { $0.id == goal.id }
        longTermGoals.append(goal)

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/\(goal.id)/unarchive") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func addLongTermGoal() {
        guard !newLongTermTitle.isEmpty else { return }

        let newGoal = LongTermGoal(
            id: UUID(),
            title: newLongTermTitle,
            steps: newLongTermSteps.map { LongTermStep(id: UUID(), name: $0, isCompleted: false) }
        )

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        guard let jsonData = try? JSONEncoder().encode(newGoal) else { return }
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.longTermGoals.append(newGoal)
                self.newLongTermTitle = ""
                self.newLongTermSteps = []
            }
        }.resume()
    }

    private func toggleLongStepCompletion(goalId: UUID, stepId: UUID) {
        guard let goalIndex = longTermGoals.firstIndex(where: { $0.id == goalId }),
              let stepIndex = longTermGoals[goalIndex].steps.firstIndex(where: { $0.id == stepId }) else { return }

        longTermGoals[goalIndex].steps[stepIndex].isCompleted.toggle()

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/\(goalId)/steps/\(stepId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        let payload = ["isCompleted": longTermGoals[goalIndex].steps[stepIndex].isCompleted]
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func resetLongTermGoals() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/reset") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async { self.longTermGoals.removeAll() }
        }.resume()
    }

    private func shareGoalToFriends(goal: LongTermGoal) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        let friendPost = FriendPost(id: UUID(), username: username, goal: goal, comment: nil)
        guard let jsonData = try? JSONEncoder().encode(friendPost) else { return }
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.shareAlertMessage = "Failed to share: \(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.shareAlertMessage = "Goal shared to your friends' feeds!"
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.shareAlertMessage = "Share failed (status \(code)). Try again."
                }
                self.showShareAlert = true
            }
        }.resume()
    }
}
