//
//  ShareGroceryListView.swift
//  PlotLine
//

import SwiftUI

struct ShareGroceryListView: View {
    let groceryList: GroceryList
    var onDismiss: () -> Void

    @State private var friends: [String] = []
    @State private var members: [String] = []
    @State private var searchText: String = ""
    @State private var isLoading = true
    @State private var sendingTo: String? = nil
    @State private var sentTo: Set<String> = []
    @State private var removingMember: String? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
    }

    private var isOwner: Bool {
        let owner = (groceryList.ownerUsername ?? groceryList.username).lowercased()
        return owner == username.lowercased()
    }

    // Friends who aren't already on the list, filtered by the search text
    private var shareableFriends: [String] {
        let base = friends.filter { f in !members.contains { $0.lowercased() == f.lowercased() } }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading friends…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friends.isEmpty && members.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No friends yet")
                            .font(.headline)
                        Text("Add friends first to share grocery lists.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Current members — owner can remove (unshare) any of them
                        if isOwner && !members.isEmpty {
                            Section("Shared with") {
                                ForEach(members, id: \.self) { member in
                                    HStack {
                                        Text(member).font(.body)
                                        Spacer()
                                        if removingMember == member {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Button("Remove") {
                                                unshare(member)
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(.red)
                                            .controlSize(.small)
                                            .disabled(removingMember != nil)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        Section(members.isEmpty ? "Friends" : "Add more friends") {
                            if shareableFriends.isEmpty {
                                Text(friends.isEmpty
                                     ? "No friends yet. Add friends first to share grocery lists."
                                     : "All your friends are already on this list.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(shareableFriends, id: \.self) { friend in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(friend)
                                                .font(.body)
                                            if sentTo.contains(friend) {
                                                Text("Invite sent")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        Spacer()
                                        if sentTo.contains(friend) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        } else if sendingTo == friend {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Button("Share") {
                                                sendShare(to: friend)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.blue)
                                            .controlSize(.small)
                                            .disabled(sendingTo != nil)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "Search friends")
                }
            }
            .navigationTitle("Share \"\(groceryList.name)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .onAppear {
                members = groceryList.members ?? []   // instant seed from the snapshot
                fetchFriends()
            }
            .task {
                // Keep the member list live so a friend accepting shows up as "Remove"
                // within a couple seconds, without leaving and reopening the screen.
                while !Task.isCancelled {
                    await refreshMembers()
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                }
            }
        }
    }

    // Pull the current members from the backend (canonical list) and apply them,
    // unless the user is mid-removal (to avoid clobbering the optimistic update).
    private func refreshMembers() async {
        guard let fresh = try? await GroceryListAPI.getGroceryList(listId: groceryList.id.uuidString) else { return }
        await MainActor.run {
            if removingMember == nil {
                members = fresh.members ?? []
            }
        }
    }

    private func unshare(_ member: String) {
        removingMember = member
        Task {
            do {
                try await GroceryListAPI.unshareList(
                    ownerUsername: username,
                    memberUsername: member,
                    listId: groceryList.id.uuidString
                )
                await MainActor.run {
                    members.removeAll { $0.lowercased() == member.lowercased() }
                    removingMember = nil
                }
            } catch {
                await MainActor.run {
                    removingMember = nil
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func fetchFriends() {
        isLoading = true
        Task {
            do {
                let list = try await FriendsAPI.fetchFriendList(username: username)
                await MainActor.run {
                    friends = list.friends
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    friends = []
                    isLoading = false
                }
            }
        }
    }

    private func sendShare(to friend: String) {
        sendingTo = friend
        Task {
            do {
                try await GroceryListAPI.shareList(
                    fromUsername: username,
                    toUsername: friend,
                    listId: groceryList.id.uuidString
                )
                await MainActor.run {
                    sentTo.insert(friend)
                    sendingTo = nil
                }
            } catch {
                await MainActor.run {
                    sendingTo = nil
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
