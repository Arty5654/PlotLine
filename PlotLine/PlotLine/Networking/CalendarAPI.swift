//
//  CalendarAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import Foundation

struct CalendarAPI {
    
    static let baseURL = "\(BackendConfig.baseURLString)"
    
    static func createEvent(_ event: Event, username: String) async throws -> Event {
        guard let url = URL(string: "\(baseURL)/calendar/create-event") else {
            throw CalendarError.invalidURL
        }

        let requestBody = CreateEventRequest(
            username: username,
            id: event.id,
            title: event.title,
            description: event.description,
            startDate: event.startDate,
            endDate: event.endDate,
            eventType: event.eventType,
            recurrence: event.recurrence,
            invitedFriends: event.invitedFriends,
            friendsCanSee: event.friendsCanSee,
            addedBy: event.addedBy,
            status: event.status
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(requestBody)
        
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CalendarError.serverError
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let eventResponse = try decoder.decode(EventResponse.self, from: data)
        if !eventResponse.success {
            throw CalendarError.custom(eventResponse.error ?? "Unknown error")
        }
        
        // Return the newly created or confirmed Event from the server
        guard let returnedEvent = eventResponse.event else {
            throw CalendarError.custom("No event returned from server.")
        }
        
        return returnedEvent
    }
    
    static func getEvents(username: String) async throws -> [Event] {
        guard let url = URL(string: "\(baseURL)/calendar/get-events?username=\(username)") else {
            throw CalendarError.invalidURL
        }
        
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CalendarError.serverError
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let eventsResponse = try decoder.decode(EventsResponse.self, from: data)
        if !eventsResponse.success {
            throw CalendarError.custom(eventsResponse.error ?? "Unknown error")
        }
        
        return eventsResponse.events ?? []
    }

    
    static func updateEvent(_ event: Event, username: String) async throws -> Event {
        guard let url = URL(string: "\(baseURL)/calendar/update-event") else {
            throw CalendarError.invalidURL
        }
        
        let requestBody = UpdateEventRequest(
            username: username,
            id: event.id,
            title: event.title,
            description: event.description,
            startDate: event.startDate,
            endDate: event.endDate,
            eventType: event.eventType,
            recurrence: event.recurrence,
            invitedFriends: event.invitedFriends,
            friendsCanSee: event.friendsCanSee,
            addedBy: event.addedBy,
            status: event.status
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(requestBody)
        
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CalendarError.serverError
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let eventResponse = try decoder.decode(EventResponse.self, from: data)
        if !eventResponse.success {
            throw CalendarError.custom(eventResponse.error ?? "Unknown error")
        }
        
        guard let updatedEvent = eventResponse.event else {
            throw CalendarError.custom("No event returned from server.")
        }
        
        return updatedEvent
    }
    
    static func deleteEvent(_ eventID: String, username: String) async throws {
        guard let url = URL(string: "\(baseURL)/calendar/delete-event") else {
            throw CalendarError.invalidURL
        }
        
        let requestBody = DeleteEventRequest(username: username, eventId: eventID)
        let jsonData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CalendarError.serverError
        }
        
        let deleteResponse = try JSONDecoder().decode(DeleteEventResponse.self, from: data)
        if !deleteResponse.success {
            throw CalendarError.custom(deleteResponse.error ?? "Unknown error")
        }
    }
    
    static func respondToEventInvite(username: String, eventId: String, accept: Bool) async throws {
        guard let url = URL(string: "\(baseURL)/calendar/respond-event-invite") else {
            throw CalendarError.invalidURL
        }
        let body: [String: Any] = ["username": username, "eventId": eventId, "accept": accept]
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CalendarError.serverError
        }
    }

    // Sends all gcal events in one request; backend replaces gcal_ entries atomically
    static func batchSyncGcal(_ events: [Event], username: String) async throws -> [Event] {
        guard let url = URL(string: "\(baseURL)/calendar/batch-sync-gcal") else {
            throw CalendarError.invalidURL
        }

        struct BatchRequest: Encodable {
            let username: String
            let events: [CreateEventRequest]
        }
        let payload = BatchRequest(
            username: username,
            events: events.map {
                CreateEventRequest(username: username, id: $0.id, title: $0.title,
                                   description: $0.description, startDate: $0.startDate,
                                   endDate: $0.endDate, eventType: $0.eventType,
                                   recurrence: $0.recurrence, invitedFriends: [],
                                   friendsCanSee: true, addedBy: nil, status: "approved")
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(payload)

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CalendarError.serverError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let eventsResponse = try decoder.decode(EventsResponse.self, from: data)
        return eventsResponse.events ?? []
    }

    static func deleteEventByType(_ type: String, username: String) async throws {
        guard let url = URL(string: "\(baseURL)/calendar/delete-by-type?username=\(username)&type=\(type)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
            
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
            
        print("Successfully deleted events of type \(type) from backend")
    }

}


enum CalendarError: Error {
    case invalidURL
    case serverError
    case custom(String)
}

