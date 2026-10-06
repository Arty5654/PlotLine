//
//  FriendsTests.swift
//  PlotLineTests
//
//  Friends page: friend lists, requests, goal feed posts, chat messages.
//

import Testing
import Foundation
@testable import PlotLine

struct FriendsTests {

    @Test("Friend list and pending requests decode")
    func lists() throws {
        let friends = try TestJSON.decode(FriendList.self, #"{"username":"alex","friends":["sam","jo"]}"#, iso8601: false)
        let requests = try TestJSON.decode(RequestList.self, #"{"username":"alex","pendingRequests":["kim"]}"#, iso8601: false)
        #expect(friends.friends == ["sam", "jo"])
        #expect(requests.pendingRequests == ["kim"])
    }

    @Test("Friend request is sent with sender, receiver and status")
    func request() throws {
        let body = try TestJSON.object(FriendRequest(senderUsername: "alex", receiverUsername: "sam", status: "PENDING"))
        #expect(body["senderUsername"] as? String == "alex")
        #expect(body["receiverUsername"] as? String == "sam")
        #expect(body["status"] as? String == "PENDING")
    }

    @Test("Chat message with reactions and replies decodes")
    func chatMessage() throws {
        let message = try TestJSON.decode(ChatMessage.self, """
        {"id":"m1","creator":"sam","timestamp":"2026-10-05T14:30:00Z","content":"Hi!",
         "reactions":{"🔥":2},"replies":{"alex":["Hey"]}}
        """)
        #expect(message.creator == "sam")
        #expect(message.reactions["🔥"] == 2)
        #expect(message.replies["alex"] == ["Hey"])
    }

    @Test("Goal feed post decodes, including posts with no likes or comments yet")
    func feedPost() throws {
        let post = try TestJSON.decode(FriendPost.self, """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","username":"sam","comment":"Ran a 5k",
         "goal":{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302","title":"Run","steps":[]}}
        """, iso8601: false)
        #expect(post.username == "sam")
        #expect(post.goal.title == "Run")
        #expect(post.likedBy == nil)
    }
}
