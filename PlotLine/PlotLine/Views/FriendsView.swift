import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var viewModel: FriendsViewModel
    @State private var showSearchSheet = false
    @State private var currentUsername = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "defaultUser"
    @State private var selectedUsername: String?

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                // requests first: they're waiting on you
                PendingRequestsSection(
                    pendingRequests: viewModel.pendingRequests,
                    currentUsername: currentUsername,
                    onSelect: { selectedUsername = $0 },
                    onAccept: { sender in
                        Task {
                            await viewModel.acceptFriendRequest(sender: sender, receiver: currentUsername)
                            await reloadData()
                        }
                    },
                    onDecline: { sender in
                        Task {
                            await viewModel.declineFriendRequest(sender: sender, receiver: currentUsername)
                            await reloadData()
                        }
                    }
                )

                FriendsListSection(friends: viewModel.friends) { friend in
                    selectedUsername = friend
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.md)
        }
        .navigationTitle("My Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if let inviteURL = URL(string: "\(BackendConfig.baseURLString)/invite?from=\(currentUsername)") {
                    ShareLink(
                        item: inviteURL,
                        message: Text("Add me as a friend on PlotLine!")
                    ) {
                        Image(systemName: "link.badge.plus")
                    }
                    .accessibilityLabel("Share invite link")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSearchSheet.toggle() } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add friends")
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            // Add-Friends sheet wrapped in its own NavigationStack
            NavigationStack {
                FriendSearchView(currentUsername: currentUsername)
                    .environmentObject(viewModel)
                    .navigationTitle("Add Friends")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $selectedUsername) { friend in
            NavigationStack {
                FriendProfileView(username: friend)
            }
            .environmentObject(viewModel)
        }
        .task { await reloadData() }
        .alert(isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Alert(title: Text(viewModel.errorMessage ?? ""), dismissButton: .cancel())
        }
    }

    private func reloadData() async {
        await viewModel.loadFriends(for: currentUsername)
        await viewModel.loadPendingRequests(for: currentUsername)
    }
}

struct FriendsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FriendsView()
                .environmentObject(FriendsViewModel())
        }
    }
}
