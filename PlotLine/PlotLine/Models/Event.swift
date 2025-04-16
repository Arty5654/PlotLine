//
//  Event.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import Foundation

struct Event: Identifiable, Codable {
    
    let id: String
    var title: String
    var description: String
    var startDate: Date
    var endDate: Date
    var eventType: String
    var recurrence: String
    var invitedFriends: [String]
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
