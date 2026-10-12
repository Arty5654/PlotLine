//
//  CalendarTests.swift
//  PlotLineTests
//
//  Calendar page: decoding events from the server, week math.
//

import Testing
import Foundation
import EventKit
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

// Apple Calendar import: which calendars are remembered, and which are ticked the first time
struct AppleCalendarTests {

    @Test("Chosen calendars are remembered per PlotLine account, so another account on the phone starts unlinked")
    func selectionPerAccount() {
        let a = "applecaltest\(UUID().uuidString.prefix(8))"
        let b = "applecaltest\(UUID().uuidString.prefix(8))"
        defer {
            AppleCalendar.setSelectedCalendarIDs([], for: a)
            AppleCalendar.setSelectedCalendarIDs([], for: b)
        }
        AppleCalendar.setSelectedCalendarIDs(["home", "work"], for: a)
        #expect(AppleCalendar.selectedCalendarIDs(for: a) == ["home", "work"])
        #expect(AppleCalendar.selectedCalendarIDs(for: a.uppercased()) == ["home", "work"]) // usernames ignore case
        #expect(AppleCalendar.selectedCalendarIDs(for: b).isEmpty)

        AppleCalendar.setSelectedCalendarIDs([], for: a) // disconnect
        #expect(AppleCalendar.selectedCalendarIDs(for: a).isEmpty)
    }

    @Test("The person's own calendars are ticked by default")
    func ownCalendarIsOnByDefault() {
        let calendar = EKCalendar(for: .event, eventStore: AppleCalendar.store) // a local calendar
        #expect(AppleCalendar.isOnByDefault(calendar, googleLinked: false))
        #expect(AppleCalendar.isOnByDefault(calendar, googleLinked: true)) // not a Google account
    }
}

/// Google Calendar import: shared calendars, untitled and declined events, locations.
struct GoogleCalendarImportTests {
    private func item(_ extra: [String: Any]) -> [String: Any] {
        ["id": "evt1", "start": ["dateTime": "2026-10-12T15:00:00Z"], "end": ["dateTime": "2026-10-12T16:00:00Z"]]
            .merging(extra) { $1 }
    }

    @Test("Calendars ticked in Google Calendar are read, including ones a friend shared; hidden or unticked ones aren't")
    func shownCalendars() {
        let ids = GoogleCalendarAPI.shownCalendarIds(in: [
            ["id": "me@gmail.com", "primary": true, "selected": true],
            ["id": "friend@gmail.com", "selected": true],                       // shared by a friend
            ["id": "team@group.calendar.google.com", "selected": false],
            ["id": "old@group.calendar.google.com", "selected": true, "hidden": true],
        ])
        #expect(ids == ["primary", "friend@gmail.com"])
    }

    @Test("Location comes through; an untitled (free/busy) event is kept as Busy; a declined invite is skipped")
    func parse() {
        let party = GoogleCalendarAPI.parseEvent(item(["summary": "Party", "location": " Joe's Pizza, 12 Main St "]))
        #expect(party?.title == "Party")
        #expect(party?.location == "Joe's Pizza, 12 Main St")

        let busy = GoogleCalendarAPI.parseEvent(item([:]))
        #expect(busy?.title == "Busy")
        #expect(busy?.location == nil)

        let declined = GoogleCalendarAPI.parseEvent(item(["summary": "Meeting",
            "attendees": [["email": "me@gmail.com", "self": true, "responseStatus": "declined"]]]))
        #expect(declined == nil)
    }

    @Test("Events keep their location through the server's JSON; older events without one still load")
    func eventLocationJSON() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let withPlace = try decoder.decode(Event.self, from: Data("""
            {"id":"1","title":"Lunch","startDate":"2026-10-12T15:00:00Z","endDate":"2026-10-12T16:00:00Z","location":"Cafe Rio"}
            """.utf8))
        #expect(withPlace.location == "Cafe Rio")
        let old = try decoder.decode(Event.self, from: Data("""
            {"id":"2","title":"Gym","startDate":"2026-10-12T15:00:00Z","endDate":"2026-10-12T16:00:00Z"}
            """.utf8))
        #expect(old.location == nil)
        #expect(EventLocationLink.mapsURL(for: "Cafe Rio, 5 Elm St")?.absoluteString == "https://maps.apple.com/?q=Cafe%20Rio,%205%20Elm%20St")
    }
}
