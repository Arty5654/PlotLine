import SwiftUI

struct FriendSearchView: View {
    
    @EnvironmentObject var viewModel: FriendsViewModel
    let currentUsername: String
    
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var searchExecuted = false
    @State private var showProfileSheet = false
    
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Search by Username")
                    .font(.custom("AvenirNext-Bold", size: 16))
                    .foregroundColor(.blue)
                
                HStack {
                    TextField("Username", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Search") {
                        searchExecuted = true
                        Task {
                            await viewModel.findUser(username: searchText)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
                if searchExecuted {
                    if let found = viewModel.foundUser {
                        
                        Button("View Profile") {
                            showProfileSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(UIColor.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        Button("Send Friend Request") {
                            Task {
                                successMessage = await viewModel.sendFriendRequest(sender: currentUsername, receiver: found)
                                showSuccessAlert = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(UIColor.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        .sheet(isPresented: $showProfileSheet) {
                            FriendProfileView(friendUsername: found)
                        }
                    } else {
                        Text("No user found.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .italic()
                            .padding(.top, 6)
                    }
                }
                
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Friend Requested", isPresented: $showSuccessAlert, actions: {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            }, message: {
                Text(successMessage)
            })
        }
    }
}
