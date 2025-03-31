import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var viewModel: FriendsViewModel
    
    @State private var showSearchSheet = false
    @State private var currentUsername: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "defaultUser"
    
    // We'll use these two states to show the profile sheet
    @State private var showProfileSheet = false
    @State private var selectedUsername: String? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // When user taps a friend, set selectedUsername and showProfileSheet
                    FriendsListSection(friends: viewModel.friends) { friend in
                        selectedUsername = friend
                        showProfileSheet = true
                    }
                    
                    Spacer()
                    
                    PendingRequestsSection(
                        pendingRequests: viewModel.pendingRequests,
                        currentUsername: currentUsername,
                        onSelect: { username in
                            selectedUsername = username
                            showProfileSheet = true
                        },
                        onAccept: { senderUsername in
                            await viewModel.acceptFriendRequest(sender: senderUsername, receiver: currentUsername)
                            await reloadData()
                        },
                        onDecline: { senderUsername in
                            await viewModel.declineFriendRequest(sender: senderUsername, receiver: currentUsername)
                            await reloadData()
                        }
                    )
                    
                    Spacer().frame(height: 30)
                }
                .padding(.top, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("My Friends")
                        .font(.custom("AvenirNext-Bold", size: 24))
                        .foregroundColor(.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSearchSheet.toggle()
                    } label: {
                        Text("Add More")
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            FriendSearchView(currentUsername: currentUsername)
                .environmentObject(viewModel)
        }
        .sheet(item: $selectedUsername) { friend in
            FriendProfileView(friendUsername: friend)
        }
        .task {
            await reloadData()
        }
        .alert(viewModel.errorMessage ?? "", isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        }
    }
    
    func reloadData() async {
        await viewModel.loadFriends(for: currentUsername)
        await viewModel.loadPendingRequests(for: currentUsername)
    }
}
