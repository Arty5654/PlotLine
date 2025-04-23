import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var viewModel: FriendsViewModel
    @State private var showSearchSheet = false
    @State private var currentUsername = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "defaultUser"
    @State private var selectedUsername: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                FriendsListSection(friends: viewModel.friends) { friend in
                    selectedUsername = friend
                }

                Spacer()

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

                Spacer().frame(height: 30)
            }
            .padding(.top, 20)
        }
        .navigationTitle("My Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSearchSheet.toggle() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
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
            FriendProfileView(username: friend)
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
