//
//  CalendarViewModel.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import SwiftUI
import Combine

class CalendarViewModel: ObservableObject {
    
    @Published var username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    
    @Published var currentDate: Date = Date()  // current date
    @Published var displayMode: DisplayMode = .month
    @Published var events: [Event] = []
    
    @Published var selectedDay: Date? = nil
    
    enum DisplayMode {
        case month
        case week
    }
    
    init() {
        // fetch events right away
         Task { await fetchEvents() }
    }
    
    // cal nav
    
    func previousMonth() {
        guard let newDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) else { return }
        currentDate = newDate
    }
    
    func nextMonth() {
        guard let newDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) else { return }
        currentDate = newDate
    }
    
    func previousWeek() {
        guard let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentDate) else { return }
        currentDate = newDate
    }
    
    func nextWeek() {
        guard let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentDate) else { return }
        currentDate = newDate
    }
    
    func showMonthView() {
        displayMode = .month
    }
    
    func showWeekView() {
        displayMode = .week
    }
    
    
    private func firstDayOfMonth(for date: Date) -> Date? {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components)
    }
    
    func daysInCurrentMonth() -> [Date] {
        guard let range = Calendar.current.range(of: .day, in: .month, for: currentDate),
              let monthStart = firstDayOfMonth(for: currentDate) else {
            return []
        }
        
        return range.compactMap { day -> Date? in
            Calendar.current.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }
    
    func eventsOnDay(_ date: Date) -> [Event] {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        
        // all events on a given day
        let allEvents =  events.filter { event in
            event.startDate < dayEnd && event.endDate >= dayStart
        }
        
        // sort to show:
        // 1. rent if it exists
        // 2. subscriptions
        // TODO: 3. goals
        // 4. all others
        let sortedEvents = allEvents.sorted { a, b in
            func priority(for event: Event) -> Int {
                if event.eventType == "rent" {
                    return 0
                } else if event.eventType.hasPrefix("subscription") {
                    return 1
                } else if event.eventType.hasPrefix("goal"){
                    return 2
                } else {
                    return 3
                }
            }

                return priority(for: a) < priority(for: b)
        }

        return sortedEvents
    }
    
    private func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
    
    func hasEvent(on day: Date) -> Bool {
        events.contains { event in
            day >= startOfDay(for: event.startDate) &&
            day <= startOfDay(for: event.endDate)
        }
    }
    
    
    // fetch all for username
    @MainActor
    func fetchEvents() {
        Task {
            do {
                let fetched = try await CalendarAPI.getEvents(username: username)
                let expanded = expandRecurringEvents(fetched)
                
                self.events = expanded
                
                print("Fetched \(fetched.count) event(s) for user: \(username) and there are \(expanded.count) including recurrences")
            } catch {
                print("Error fetching events: \(error)")
            }
        }
    }
    
    // create new and store in backend
    @MainActor
    func createEvent(title: String, description: String, startDate: Date, endDate: Date, eventType: String, recurrence: String) {
        Task {
            do {
                let newEvent = Event(
                    id: UUID().uuidString,
                    title: title,
                    description: description,
                    startDate: startDate,
                    endDate: endDate,
                    eventType: eventType,
                    recurrence: recurrence
                )
                // db append
                let saved = try await CalendarAPI.createEvent(newEvent, username: username)
                // local append
                events.append(saved)
                print("Created new event: \(saved.title)")
                fetchEvents()
            } catch {
                print("Error creating event: \(error)")
            }
        }
    }
    
    // overwrite on backend
    @MainActor
    func updateEvent(event: Event) {
        Task {
            do {
                let updated = try await CalendarAPI.updateEvent(event, username: username)
                if let index = events.firstIndex(where: { $0.id == event.id }) {
                    events[index] = updated
                }
                print("Updated event: \(updated.title)")
            } catch {
                print("Error updating event: \(error)")
            }
        }
        fetchEvents()
    }
    
    @MainActor
    func deleteEvent(_ eventID: String) {
        Task {
            do {
                try await CalendarAPI.deleteEvent(eventID, username: username)
                
                // remove the event locally
                events.removeAll { $0.id == eventID }
                print("Deleted event with ID: \(eventID)")
            } catch {
                print("Error deleting event: \(error)")
            }
        }
        fetchEvents()
    }
    
    @MainActor
    func deleteEventByType(_ type: String) {
        Task {
            do {
                try await CalendarAPI.deleteEventByType(type, username: username)
                
                // remove the event locally
                events.removeAll { $0.eventType == type }
                print("Deleted event with type: \(type)")
            } catch {
                print("Error deleting event: \(error)")
            }
        }
    }
    
    private func expandRecurringEvents(_ masterEvents: [Event]) -> [Event] {
        // expand for 6 months
        let sixMonthsFromNow = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        
        var allEvents: [Event] = []
        
        for event in masterEvents {
            
            if event.recurrence == "none" {
                allEvents.append(event)
            } else {
                
                allEvents.append(event)
                
                let expansions = generateRecurringInstances(for: event, until: sixMonthsFromNow)
                allEvents.append(contentsOf: expansions)
            }
        }
        
        return allEvents
    }

    

    private func generateRecurringInstances(for event: Event, until limitDate: Date) -> [Event] {
        var result: [Event] = []
        let cal = Calendar.current
        
        var cursor = event.startDate
        
        while cursor < limitDate {
            switch event.recurrence {
            case "weekly":
                guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
                cursor = next
                
            case "biweekly":
                guard let next = cal.date(byAdding: .weekOfYear, value: 2, to: cursor) else { break }
                cursor = next
                
            case "monthly":
                guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
                
            default:
                // can add new cases if relevant
                break
            }
            

            if cursor <= limitDate {
                // build copy of original event with new dates
                let dayDelta = event.endDate.timeIntervalSince(event.startDate)
                let nextEnd = cursor.addingTimeInterval(dayDelta)
                
                var newOccur = event
                newOccur.startDate = cursor
                newOccur.endDate = nextEnd
                
                result.append(newOccur)
            }
        }
        
        return result
    }


}
