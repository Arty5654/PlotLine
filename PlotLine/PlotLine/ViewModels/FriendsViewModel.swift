// FriendsViewModel.swift
// PlotLine
//
// Created by Alex Younkers on 4/18/25.
//

import SwiftUI

@MainActor
class FriendsViewModel: ObservableObject {
    
    @Published var friends: [String] = []
    @Published var pendingRequests: [String] = []
    
    @Published var errorMessage: String?
    @Published var requestMessage: String?
    
    @Published var foundUser: String? = nil
    @Published var searchExecuted: Bool = false
    
    @Published var allUsers: [String] = []
    
    func loadFriends(for username: String) async {
        do {
            let friendList = try await FriendsAPI.fetchFriendList(username: username)
            friends = friendList.friends
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadPendingRequests(for username: String) async {
        do {
            let requestList = try await FriendsAPI.fetchFriendRequests(username: username)
            pendingRequests = requestList.pendingRequests
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func sendFriendRequest(sender: String, receiver: String) async -> String {
        var resp = "Successfully sent friend request!"
        do {
            resp = try await FriendsAPI.createOrUpdateFriendRequest(
                senderUsername: sender,
                receiverUsername: receiver,
                status: "PENDING"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        return resp
    }
    
    // accept a friend request
    func acceptFriendRequest(sender: String, receiver: String) async{
        do {
            var resp = try await FriendsAPI.createOrUpdateFriendRequest(
                senderUsername: sender,
                receiverUsername: receiver,
                status: "ACCEPTED"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        
    }
    
    // decline a friend request
    func declineFriendRequest(sender: String, receiver: String) async {
        do {
            try await FriendsAPI.createOrUpdateFriendRequest(
                senderUsername: sender,
                receiverUsername: receiver,
                status: "DECLINED"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func removeFriend(user: String, friend: String) async {
        do {
            try await FriendsAPI.removeFriend(username: user, friendUsername: friend)
            await loadFriends(for: user)
            await loadPendingRequests(for: user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func findUser(username: String) async {
        // reset before each new search
        searchExecuted = false
        foundUser = nil
        
        do {
            let exists = try await FriendsAPI.userExists(username: username)
            if exists {
                foundUser = username
            } else {
                foundUser = nil
            }
        } catch {
            foundUser = nil
            errorMessage = error.localizedDescription
        }
        
        searchExecuted = true
    }
    
    func fetchAllUsernames() async {
        do {
            let users = try await FriendsAPI.getAllUsers()
            allUsers = users
        } catch {
            print("❌ Failed to load all users:", error)
        }
    }
}
