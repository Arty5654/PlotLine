import SwiftUI

struct FriendSearchView: View {
    @EnvironmentObject var viewModel: FriendsViewModel
    let currentUsername: String
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var suggestions: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {

                Text("Search by Username")
                    .font(.custom("AvenirNext-Bold", size: 16))
                    .foregroundColor(.blue)

                VStack(spacing: 4) {
                    TextField("Username", text: $searchText)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .onChange(of: searchText) {
                            updateSuggestions(for: searchText)
                        }
                        .padding(.horizontal)

                    if !suggestions.isEmpty {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(suggestions, id: \.self) { username in
                                    NavigationLink(destination: FriendProfileView(username: username)) {
                                        HStack(spacing: 12) {
                                            FriendProfilePicture(username: username)
                                                .frame(width: 36, height: 36)

                                            Text(username)
                                                .font(.body)
                                                .foregroundColor(.primary)

                                            Spacer()
                                        }
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(12)
                                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 2)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 200)
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                Task { await viewModel.fetchAllUsernames() }
            }
        }
    }

    private func updateSuggestions(for text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        suggestions = viewModel.allUsers.filter {
            $0.lowercased().contains(query.lowercased()) &&
            $0.lowercased() != currentUsername.lowercased()
        }
    }
}


// MARK: — Mini Circle Profile View
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
