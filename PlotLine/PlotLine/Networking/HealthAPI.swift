//
//  HealthAPI.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/2/25.
//

import SwiftUI

class HealthAPI {
    private let baseURL = "http://localhost:8080/api/health"
    
    // Helper to get Sunday date string for a given date
    private func getSundayKeyForDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let sunday = calendar.date(from: components) else { return "" }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMddyyyy"
        return formatter.string(from: sunday)
    }
    
    // Fetch health entries for a specific week
    func fetchEntriesForWeek(containing date: Date) async throws -> [HealthEntry] {
        // Get username from UserDefaults
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        let sundayKey = getSundayKeyForDate(date)
        guard let url = URL(string: "\(baseURL)/users/\(username)/health-entries/\(sundayKey)/entries.json") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Date decoder
                let decoder = JSONDecoder()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ" // Format with timezone
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                decoder.dateDecodingStrategy = .formatted(dateFormatter)
                
                return try decoder.decode([HealthEntry].self, from: data)
            } catch {
                throw error
            }
    }
    
    // Save a health entry
    func saveEntry(_ entry: HealthEntry) async throws {
        // Get username from UserDefaults
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        // Set the username in the entry
        var updatedEntry = entry
        
        // For saving, we'll need to fetch the whole week, add/update the entry, then save it back
        let sundayKey = getSundayKeyForDate(entry.date)
        
        do {
            // Fetch existing entries for this week
            var updatedEntries = try await fetchEntriesForWeek(containing: entry.date)
            
            // Remove any existing entry for the same date
            updatedEntries.removeAll { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
            
            // Add the new or updated entry
            updatedEntries.append(entry)
            
            // Save the updated entries array
            guard let url = URL(string: "\(baseURL)/users/\(username)/health-entries/\(sundayKey)/entries.json") else {
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let encoder = JSONEncoder()
            // Configure the encoder to properly format dates
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            encoder.dateEncodingStrategy = .formatted(dateFormatter)
            
            request.httpBody = try encoder.encode(updatedEntries)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
        } catch {
            throw error
        }
    }
    
    // Delete a health entry
    func deleteEntry(date: Date) async throws {
        // Get username from UserDefaults
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        let sundayKey = getSundayKeyForDate(date)
        
        do {
            // Fetch existing entries
            var updatedEntries = try await fetchEntriesForWeek(containing: date)
            
            // Find the entry with the matching date
            guard let entryToDelete = updatedEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else {
                throw URLError(.resourceUnavailable)
            }
            
            // Remove the entry
            updatedEntries.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
            
            // Save the updated entries array
            guard let url = URL(string: "\(baseURL)/users/\(username)/health-entries/\(sundayKey)/entries.json") else {
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let encoder = JSONEncoder()
            // Configure the encoder to properly format dates
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            encoder.dateEncodingStrategy = .formatted(dateFormatter)
            
            request.httpBody = try encoder.encode(updatedEntries)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
        } catch {
            throw error
        }
    }
    
    // Get health insights
    func getHealthInsights() async throws -> [String: Any] {
        // Get username from UserDefaults
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard let url = URL(string: "\(baseURL)/users/\(username)/health-insights") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        
        return jsonObject
    }
}
