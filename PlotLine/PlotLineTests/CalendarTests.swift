//
//  CalendarTests.swift
//  PlotLineTests
//
//  Calendar page: decoding events from the server, week math.
//

import Testing
import Foundation
@testable import PlotLine

struct CalendarTests {

    @Test("A full event from the server decodes")
    func fullEvent() throws {
        let event = try TestJSON.decode(Event.self, """
        {"id":"e1","title":"Party","description":"BYOB","startDate":"2026-10-10T18:00:00Z","endDate":"2026-10-10T21:00:00Z",
         "eventType":"user","recurrence":"none","invitedFriends":["sam"],"friendsCanSee":false,"addedBy":"alex",
         "status":"invite-pending","inviteStatuses":{"sam":"accepted"}}
        """)
        #expect(event.title == "Party")
        #expect(event.status == "invite-pending")
        #expect(event.addedBy == "alex")
        #expect(event.inviteStatuses["sam"] == "accepted")
        #expect(event.friendsCanSee == false)
        #expect(event.endDate.timeIntervalSince(event.startDate) == 3 * 3600)
    }

    @Test("Older events missing optional fields get sensible defaults")
    func minimalEvent() throws {
        let event = try TestJSON.decode(Event.self,
            #"{"id":"e2","title":"Old","startDate":"2026-01-01T00:00:00Z","endDate":"2026-01-01T01:00:00Z"}"#)
        #expect(event.description == "")
        #expect(event.eventType == "user")
        #expect(event.recurrence == "none")
        #expect(event.invitedFriends.isEmpty)
        #expect(event.friendsCanSee)
        #expect(event.status == "approved")
        #expect(event.inviteStatuses.isEmpty)
    }

    @Test("Calendar sharing data decodes")
    func accessData() throws {
        let data = try TestJSON.decode(CalendarAccessData.self, """
        {"granted":[{"friendUsername":"sam","level":"view","requireApproval":false,"grantedAt":"2026-10-01"}],
         "receivedAccess":[],"pendingOutgoing":[],
         "pendingIncoming":[{"id":"i1","fromUsername":"jo","toUsername":"alex","level":"add","requireApproval":true,"sentAt":"2026-10-02"}]}
        """, iso8601: false)
        #expect(data.granted.first?.friendUsername == "sam")
        #expect(data.pendingIncoming.first?.level == "add")
    }

    @Test("Weeks start on Sunday, matching the backend")
    func startOfWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let wednesday = TestJSON.day(2026, 10, 7, calendar: calendar)
        let sunday = TestJSON.day(2026, 10, 4, calendar: calendar)
        #expect(calendar.startOfWeek(for: wednesday) == sunday)
        #expect(calendar.startOfWeek(for: sunday) == sunday)
    }
}
