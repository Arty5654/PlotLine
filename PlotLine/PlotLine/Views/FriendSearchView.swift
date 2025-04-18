// FriendSearchView.swift
// PlotLine
//
// Created by Alex Younkers on 4/18/25.
//

import SwiftUI

struct FriendSearchView: View {
    @EnvironmentObject var viewModel: FriendsViewModel
    let currentUsername: String
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var suggestions: [String] = []
    @State private var showProfileSheet = false
    @State private var showSuccessAlert = false
    @State private var successMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Search by Username")
                    .font(.custom("AvenirNext-Bold", size: 16))
                    .foregroundColor(.blue)

                // MARK: — Input + Search button
                HStack {
                    TextField("Username", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: searchText) { newValue in
                            updateSuggestions(for: newValue)
                        }

                    Button("Search") {
                        Task {
                            await viewModel.findUser(username: searchText)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                // MARK: — Live dropdown of substring matches
                if !suggestions.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(suggestions, id: \.self) { user in
                                Text(user)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemBackground))
                                    .onTapGesture {
                                        searchText = user
                                        suggestions = []
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)
                }

                Spacer()

                // MARK: — Show results after search
                if let found = viewModel.foundUser {
                    Button("View Profile") {
                        showProfileSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .sheet(isPresented: $showProfileSheet) {
                        FriendProfileView(username: found)
                    }

                    Button("Send Friend Request") {
                        Task {
                            successMessage = await viewModel
                                .sendFriendRequest(
                                    sender: currentUsername,
                                    receiver: found
                                )
                            showSuccessAlert = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)

                } else if viewModel.searchExecuted {
                    Text("No user found.")
                        .italic()
                        .foregroundColor(.gray)
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
            .alert("Friend Requested",
                   isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) {
                    viewModel.foundUser = nil
                    viewModel.searchExecuted = false
                    dismiss()
                }
            } message: {
                Text(successMessage)
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
            $0.lowercased().contains(query.lowercased())
        }
    }
}
