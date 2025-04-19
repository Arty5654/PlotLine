//
//  FriendsView.swift
//  PlotLine
//
//  Created by Alex Younkers on 4/18/25.
//

import SwiftUI


struct FriendsView: View {
    @EnvironmentObject var viewModel: FriendsViewModel

    @State private var showSearchSheet = false
    @State private var currentUsername: String = UserDefaults
        .standard.string(forKey: "loggedInUsername") ?? "defaultUser"
    @State private var selectedUsername: String? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Tapping a friend sets `selectedUsername` and opens the profile sheet
                    FriendsListSection(friends: viewModel.friends) { friend in
                        selectedUsername = friend
                    }

                    Spacer()

                    PendingRequestsSection(
                        pendingRequests: viewModel.pendingRequests,
                        currentUsername: currentUsername,
                        onSelect: { username in
                            selectedUsername = username
                        },
                        onAccept: { sender in
                            Task {
                                await viewModel.acceptFriendRequest(
                                    sender: sender,
                                    receiver: currentUsername
                                )
                                await reloadData()
                            }
                        },
                        onDecline: { sender in
                            Task {
                                await viewModel.declineFriendRequest(
                                    sender: sender,
                                    receiver: currentUsername
                                )
                                await reloadData()
                            }
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
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        // MARK: — Add‑Friend Search Sheet
        .sheet(isPresented: $showSearchSheet) {
            FriendSearchView(currentUsername: currentUsername)
                .environmentObject(viewModel)
        }
        // MARK: — Profile Sheet driven by selectedUsername
        .sheet(item: $selectedUsername) { friend in
            FriendProfileView(username: friend)
        }
        .task {
            await reloadData()
        }
        .alert(isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Alert(
                title: Text(viewModel.errorMessage ?? ""),
                dismissButton: .cancel()
            )
        }
    }

    func reloadData() async {
        await viewModel.loadFriends(for: currentUsername)
        await viewModel.loadPendingRequests(for: currentUsername)
    }
}

struct FriendsView_Previews: PreviewProvider {
    static var previews: some View {
        FriendsView()
            .environmentObject(FriendsViewModel())
    }
}
