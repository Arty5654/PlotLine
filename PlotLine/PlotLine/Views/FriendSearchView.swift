import SwiftUI

struct FriendSearchView: View {
    @EnvironmentObject var viewModel: FriendsViewModel
    let currentUsername: String
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var suggestions: [String] = []

    var body: some View {
        VStack(spacing: PLSpacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(PLColor.textSecondary)
                TextField("Search usernames", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // the server searches; wait for a short pause in typing first
                    .task(id: searchText) {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await updateSuggestions(for: searchText)
                    }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Color(.tertiaryLabel))
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(12)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))

            ScrollView {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Type part of a username to find people.")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, PLSpacing.lg)
                } else if suggestions.isEmpty {
                    Text("No usernames match \"\(searchText)\".")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, PLSpacing.lg)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.element) { index, username in
                            if index > 0 { Divider().padding(.leading, 48) }
                            NavigationLink(destination: FriendProfileView(username: username)) {
                                HStack(spacing: 12) {
                                    FriendProfilePicture(username: username)
                                        .frame(width: 36, height: 36)
                                    Text(username)
                                        .foregroundColor(PLColor.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(Color(.tertiaryLabel))
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .plCard()
                }
            }
        }
        .padding(.horizontal, PLSpacing.lg)
        .padding(.top, PLSpacing.md)
        .navigationTitle("Add Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func updateSuggestions(for text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        let results = await viewModel.searchUsernames(query)
        guard query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return } // typed more since
        suggestions = results.filter { $0.lowercased() != currentUsername.lowercased() }
    }
}


struct FriendProfilePicture: View {
    let username: String

    @State private var profilePicURL: URL?

    var body: some View {
        Group {
            if let url = profilePicURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        Circle().fill(Color.red.opacity(0.3))
                    } else {
                        ProgressView()
                    }
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .clipShape(Circle())
        .onAppear {
            fetchProfilePic(for: username)
        }
    }

    private func fetchProfilePic(for username: String) {
        Task {
            do {
                let profilePicStr = try await ProfileAPI.getProfilePic(username: username)
                await MainActor.run {
                    if let url = URL(string: profilePicStr ?? "") {
                        self.profilePicURL = url
                    }
                }
            } catch {
                print("Error fetching friend profile pic: \(error)")
            }
        }
    }
}
