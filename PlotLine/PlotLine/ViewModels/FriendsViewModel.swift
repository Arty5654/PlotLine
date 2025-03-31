import SwiftUI

@MainActor
class FriendsViewModel: ObservableObject {
    
    @Published var friends: [String] = []
    @Published var pendingRequests: [String] = []
    @Published var errorMessage: String?
    @Published var requestMessage: String?
    
    @Published var foundUser: String? = nil
    

    func loadFriends(for username: String) async {
        do {
            let friendList = try await FriendsAPI.fetchFriendList(username: username)
            self.friends = friendList.friends
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // Load pending friend requests for the current user
    func loadPendingRequests(for username: String) async {
        do {
            let requestList = try await FriendsAPI.fetchFriendRequests(username: username)
            self.pendingRequests = requestList.pendingRequests
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // Send a new friend request (status "PENDING")
    func sendFriendRequest(sender: String, receiver: String) async -> String {
        var resp = "Succesfully sent friend request!"
        do {
            resp = try await FriendsAPI.createOrUpdateFriendRequest(
                senderUsername: sender,
                receiverUsername: receiver,
                status: "PENDING"
            )
            return resp
        } catch {
            self.errorMessage = error.localizedDescription
        }        
        return resp
    }
    
    // Accept a friend request (status "ACCEPTED")
    func acceptFriendRequest(sender: String, receiver: String) async {
        do {
            try await FriendsAPI.createOrUpdateFriendRequest(
                senderUsername: sender,
                receiverUsername: receiver,
                status: "ACCEPTED"
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // Decline a friend request (status "DECLINED")
    func declineFriendRequest(sender: String, receiver: String) async {
        do {
            try await FriendsAPI.createOrUpdateFriendRequest(
                senderUsername: sender,
                receiverUsername: receiver,
                status: "DECLINED"
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // search for a user by username
    func findUser(username: String) async {
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
    }
}
