//
//  Friends.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/27/25.
//

import Foundation

struct FriendRequest: Codable {
    let senderUsername: String
    let receiverUsername: String
    let status: String
}

struct FriendList: Codable {    
    let username: String
    let friends: [String]
}

struct RequestList: Codable {
    let username: String
    let pendingRequests: [String]
}
