//
//  SleepAPI.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/2/25.
//

import Foundation

class SleepAPI {
    private let baseURL = "\(BackendConfig.baseURLString)/api/health"
    
    // Fetch sleep schedule for the user
    func fetchSleepSchedule() async throws -> SleepSchedule {
        // Get username from UserDefaults
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard let url = URL(string: "\(baseURL)/users/\(username)/health-entries/sleep_schedule.json") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode == 404 {
                // No schedule exists yet, return default schedule
                return createDefaultSleepSchedule()
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            
            // Try to decode the data with a more flexible date formatter
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                // Define multiple date formatters to handle different formats
                let formatters: [DateFormatter] = [
                    // Format with timezone offset: "2025-04-02T17:10:59.147+00:00"
                    DateFormatter().with {
                        $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
                        $0.locale = Locale(identifier: "en_US_POSIX")
                        $0.timeZone = TimeZone(secondsFromGMT: 0)
                    },
                    // Standard ISO format with Z: "2025-04-02T17:10:59.147Z"
                    DateFormatter().with {
                        $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                        $0.locale = Locale(identifier: "en_US_POSIX")
                        $0.timeZone = TimeZone(secondsFromGMT: 0)
                    },
                    // Without fractional seconds: "2025-04-02T17:10:59Z"
                    DateFormatter().with {
                        $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                        $0.locale = Locale(identifier: "en_US_POSIX")
                        $0.timeZone = TimeZone(secondsFromGMT: 0)
                    },
                    // Without time component: "2025-04-02"
                    DateFormatter().with {
                        $0.dateFormat = "yyyy-MM-dd"
                        $0.locale = Locale(identifier: "en_US_POSIX")
                        $0.timeZone = TimeZone(secondsFromGMT: 0)
                    }
                ]
                
                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
                
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot decode date string \(dateString)"
                )
            }
            
            do {
                return try decoder.decode(SleepSchedule.self, from: data)
            } catch {
                return createDefaultSleepSchedule()
            }
        } catch {
            // If it's a "not found" error, return a default schedule
            if let urlError = error as? URLError,
                urlError.code == .fileDoesNotExist || urlError.code == .resourceUnavailable {
                return createDefaultSleepSchedule()
            }
            throw error
        }
    }
    
    // Save sleep schedule
    func saveSleepSchedule(_ schedule: SleepSchedule) async throws {
        // Get username from UserDefaults
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard let url = URL(string: "\(baseURL)/users/\(username)/health-entries/sleep_schedule.json") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add timestamps
        var updatedSchedule = schedule
        let now = ISO8601DateFormatter().string(from: Date())
        
        if updatedSchedule.createdAt == nil {
            updatedSchedule.createdAt = now
        }
        updatedSchedule.updatedAt = now
        
        // Configure encoder with ISO8601 date encoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        request.httpBody = try encoder.encode(updatedSchedule)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    // Helper to create a default sleep schedule with 9am wake up and 12am sleep
    private func createDefaultSleepSchedule() -> SleepSchedule {
        let calendar = Calendar.current
        
        // Default wake up time (9:00 AM)
        var wakeComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        wakeComponents.hour = 9
        wakeComponents.minute = 0
        let wakeUpTime = calendar.date(from: wakeComponents) ?? Date()
        
        // Default sleep time (12:00 AM / Midnight)
        var sleepComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        sleepComponents.hour = 0
        sleepComponents.minute = 0
        let sleepTime = calendar.date(from: sleepComponents) ?? Date()
        
        return SleepSchedule(wakeUpTime: wakeUpTime, sleepTime: sleepTime)
    }
}

// Helper extension for initializer syntax
extension DateFormatter {
    func with(_ configuration: (inout DateFormatter) -> Void) -> DateFormatter {
        var formatter = self
        configuration(&formatter)
        return formatter
    }
}
