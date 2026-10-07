import SwiftUI

struct ArchivedGoalsView: View {
    @Binding var archivedGoals: [LongTermGoal]
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var unarchiveGoal: (LongTermGoal) -> Void
    var shareGoalToFriends: (LongTermGoal) -> Void

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }


    var body: some View {
        NavigationStack {
            Group {
                if archivedGoals.isEmpty {
                    VStack(spacing: PLSpacing.md) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 40))
                            .foregroundColor(PLColor.textSecondary)
                        Text("No archived goals")
                            .font(.headline)
                            .foregroundColor(PLColor.textSecondary)
                        Text("Goals you archive will appear here.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: PLSpacing.md) {
                            ForEach(archivedGoals) { goal in
                                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                                    HStack {
                                        Text(goal.title)
                                            .font(.headline)
                                            .foregroundColor(PLColor.textPrimary)
                                        Spacer()
                                        Menu {
                                            Button {
                                                unarchiveGoal(goal)
                                            } label: {
                                                Label("Unarchive", systemImage: "arrow.uturn.left")
                                            }
                                            Button {
                                                shareGoalToFriends(goal)
                                            } label: {
                                                Label("Share to Friends", systemImage: "person.3.fill")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.title2)
                                                .foregroundColor(PLColor.tint)
                                        }
                                    }

                                    if !goal.steps.isEmpty {
                                        Divider()
                                        ForEach(goal.steps) { step in
                                            HStack(spacing: 6) {
                                                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(step.isCompleted ? .green : PLColor.textSecondary)
                                                    .font(.caption)
                                                Text(step.name)
                                                    .font(.subheadline)
                                                    .foregroundColor(PLColor.textSecondary)
                                                    .strikethrough(step.isCompleted)
                                            }
                                        }
                                    }
                                }
                                .plCard()
                            }
                        }
                        .padding(.horizontal, PLSpacing.lg)
                        .padding(.vertical, PLSpacing.lg)
                    }
                }
            }
            .navigationTitle("Archived Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { fetchArchivedGoals() }
    }

    // MARK: - Logic (unchanged)

    private func fetchArchivedGoals() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term") else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard !AppBanner.reportIfFailed("load your archived goals", data, response, error, retry: { fetchArchivedGoals() }),
                  let data = data,
                  let decoded = try? JSONDecoder().decode(LongTermGoalsResponse.self, from: data) else { return }
            DispatchQueue.main.async {
                self.archivedGoals = decoded.archivedGoals ?? []
            }
        }.resume()
    }
}
