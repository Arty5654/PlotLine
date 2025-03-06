//
//  CalendarAPI.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import Foundation

struct CalendarAPI {
    
    static let baseURL = "http://localhost:8080"
    
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
            recurrence: event.recurrence
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(requestBody)
        
        var request = URLRequest(url: url)
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
            recurrence: event.recurrence
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(requestBody)
        
        var request = URLRequest(url: url)
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
    
    static func deleteEventByType(_ type: String, username: String) async throws {
        guard let url = URL(string: "\(baseURL)/calendar/delete-by-type?username=\(username)&type=\(type)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
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

