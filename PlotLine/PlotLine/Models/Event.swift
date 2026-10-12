//
//  Event.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import Foundation

struct Event: Identifiable, Codable {

    var id: String
    var title: String
    var description: String
    var startDate: Date
    var endDate: Date
    var eventType: String
    var recurrence: String
    var invitedFriends: [String]
    var friendsCanSee: Bool
    var addedBy: String?
    var status: String
    var inviteStatuses: [String: String]  // friend -> "pending"/"accepted"/"declined"
    var location: String?                 // "Starbucks, 123 Main St"
    // repeating (see Recurrence.swift): an imported rule, the last day, and dates taken out of the series
    var recurrenceRule: String?           // "FREQ=WEEKLY;BYDAY=MO,WE" (imported events)
    var recurrenceEnd: String?            // "2026-12-31": repeats until this day
    var excludedDates: [String]           // "2026-10-12": this date was changed or removed

    // one date of a repeating event, as shown in the app (not saved)
    var seriesId: String? = nil
    var occurrenceStart: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, description, startDate, endDate, eventType, recurrence,
             invitedFriends, friendsCanSee, addedBy, status, inviteStatuses, location,
             recurrenceRule, recurrenceEnd, excludedDates
    }

    init(id: String, title: String, description: String, startDate: Date, endDate: Date,
         eventType: String, recurrence: String, invitedFriends: [String],
         friendsCanSee: Bool = true, addedBy: String? = nil, status: String = "approved",
         inviteStatuses: [String: String] = [:], location: String? = nil,
         recurrenceRule: String? = nil, recurrenceEnd: String? = nil, excludedDates: [String] = []) {
        self.id = id; self.title = title; self.description = description
        self.startDate = startDate; self.endDate = endDate
        self.eventType = eventType; self.recurrence = recurrence
        self.invitedFriends = invitedFriends
        self.friendsCanSee = friendsCanSee; self.addedBy = addedBy; self.status = status
        self.inviteStatuses = inviteStatuses
        self.location = location
        self.recurrenceRule = recurrenceRule
        self.recurrenceEnd = recurrenceEnd
        self.excludedDates = excludedDates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        title           = try c.decode(String.self, forKey: .title)
        description     = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        startDate       = try c.decode(Date.self, forKey: .startDate)
        endDate         = try c.decode(Date.self, forKey: .endDate)
        eventType       = try c.decodeIfPresent(String.self, forKey: .eventType) ?? "user"
        recurrence      = try c.decodeIfPresent(String.self, forKey: .recurrence) ?? "none"
        invitedFriends  = try c.decodeIfPresent([String].self, forKey: .invitedFriends) ?? []
        friendsCanSee   = try c.decodeIfPresent(Bool.self, forKey: .friendsCanSee) ?? true
        addedBy         = try c.decodeIfPresent(String.self, forKey: .addedBy)
        status          = try c.decodeIfPresent(String.self, forKey: .status) ?? "approved"
        inviteStatuses  = try c.decodeIfPresent([String: String].self, forKey: .inviteStatuses) ?? [:]
        location        = try c.decodeIfPresent(String.self, forKey: .location)
        recurrenceRule  = try c.decodeIfPresent(String.self, forKey: .recurrenceRule)
        recurrenceEnd   = try c.decodeIfPresent(String.self, forKey: .recurrenceEnd)
        excludedDates   = try c.decodeIfPresent([String].self, forKey: .excludedDates) ?? []
    }
}


struct CreateEventRequest: Codable {
    let username: String
    let id: String
    let title: String
    let description: String
    let startDate: Date
    let endDate: Date
    let eventType: String
    var recurrence: String
    let invitedFriends: [String]
    let friendsCanSee: Bool
    let addedBy: String?
    let status: String
    var location: String? = nil
    var recurrenceRule: String? = nil
    var recurrenceEnd: String? = nil
    var excludedDates: [String] = []
}

struct UpdateEventRequest: Codable {
    let username: String
    let id: String
    let title: String
    let description: String
    let startDate: Date
    let endDate: Date
    let eventType: String
    var recurrence: String
    let invitedFriends: [String]
    let friendsCanSee: Bool
    let addedBy: String?
    let status: String
    var location: String? = nil
    var recurrenceRule: String? = nil
    var recurrenceEnd: String? = nil
    var excludedDates: [String] = []
}


// single event response
struct EventResponse: Codable {
    let success: Bool
    let error: String?
    let event: Event?
}

// multiple events eg. fetchEvents
struct EventsResponse: Codable {
    let success: Bool
    let error: String?
    let events: [Event]?
}

struct DeleteEventRequest: Codable {
    let username: String
    let eventId: String
}

struct DeleteEventResponse: Codable {
    let success: Bool
    let error: String?
}
