//
//  CalendarViewModel.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import SwiftUI
import Combine
import UserNotifications
import GoogleSignIn

class CalendarViewModel: ObservableObject {

    var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }

    @Published var currentDate: Date = Date()
    @Published var displayMode: DisplayMode = .month
    @Published var events: [Event] = []

    @Published var selectedDay: Date? = nil
    @Published var navigateToDayView: Date? = nil

    // MARK: - Friend Calendar Overlay
    @Published var accessData: CalendarAccessData = CalendarAccessData()
    @Published var friendCalendars: [String: [Event]] = [:]
    @Published var friendColors: [String: Color] = [:]
    @Published var showFriendOverlays: Bool = true

    private let friendColorPalette: [Color] = [.purple, .orange, .pink, .teal, .indigo, .mint]

    var pendingEvents: [Event] {
        events.filter { $0.status == "pending" }
    }

    var pendingInviteEvents: [Event] {
        events.filter { $0.status == "invite-pending" }
    }

    enum DisplayMode {
        case month
        case week
    }

    init() {
        Task {
            await fetchEvents()
            fetchAccessData()
            fetchFriendCalendars()
            syncGoogleCalendarIfConnected()
        }
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
        
        let allEvents = events.filter { event in
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
    
    
    // fetch all for username; quiet for refreshes the person didn't ask for (e.g. reopening the app)
    @MainActor
    func fetchEvents(quiet: Bool = false) {
        Task { await reloadEvents(quiet: quiet) }
    }

    /// the same load, for callers that need the events before continuing
    @MainActor
    func reloadEvents(quiet: Bool = false) async {
        do {
            let fetched = try await CalendarAPI.getEvents(username: username)
            let expanded = expandRecurringEvents(fetched)
            
            self.events = expanded
            
            print("Fetched \(fetched.count) event(s) for user: \(username) and there are \(expanded.count) including recurrences")
        } catch {
            if quiet {
                print("Error fetching events: \(error)")
            } else {
                AppBanner.report("load your calendar", error, retry: { [weak self] in self?.fetchEvents() })
            }
        }
    }
    
    // create new and store in backend
    @MainActor
    func createEvent(id: String = UUID().uuidString, title: String, description: String,
                     startDate: Date, endDate: Date, eventType: String, recurrence: String,
                     invitedFriends: [String], friendsCanSee: Bool = true,
                     publishToCalendars: [String] = []) {
        Task {
            do {
                let newEvent = Event(
                    id: id,
                    title: title,
                    description: description,
                    startDate: startDate,
                    endDate: endDate,
                    eventType: eventType,
                    recurrence: recurrence,
                    invitedFriends: invitedFriends,
                    friendsCanSee: friendsCanSee
                )
                let saved = try await CalendarAPI.createEvent(newEvent, username: username)
                events.append(saved)
                print("Created new event: \(saved.title)")

                // Publish to selected friend calendars (they have given us "add" access)
                for friend in publishToCalendars {
                    let publishEvent = Event(
                        id: id,  // same ID so deduplication works in the overlay
                        title: title,
                        description: description,
                        startDate: startDate,
                        endDate: endDate,
                        eventType: eventType,
                        recurrence: recurrence,
                        invitedFriends: [],
                        friendsCanSee: friendsCanSee,
                        addedBy: username,
                        status: "pending"
                    )
                    do {
                        _ = try await CalendarAPI.createEvent(publishEvent, username: friend.lowercased())
                        print("Published event to \(friend)'s calendar")
                    } catch {
                        AppBanner.report("add the event to \(friend)'s calendar", error)
                    }
                }

                fetchEvents()
            } catch {
                // the sheet has closed; Try again sends exactly what was typed
                AppBanner.report("save your event", error, retry: { [weak self] in
                    self?.createEvent(id: id, title: title, description: description, startDate: startDate, endDate: endDate,
                                      eventType: eventType, recurrence: recurrence, invitedFriends: invitedFriends,
                                      friendsCanSee: friendsCanSee, publishToCalendars: publishToCalendars)
                })
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
                
                // Update reminders if user switches the date to invest
                if updated.eventType == "investment" {
                    scheduleInvestmentNotification(for: updated.startDate)
                }
            } catch {
                AppBanner.report("save your changes to the event", error, retry: { [weak self] in self?.updateEvent(event: event) })
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
                AppBanner.report("delete the event", error, retry: { [weak self] in self?.deleteEvent(eventID) })
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
                AppBanner.report("remove those calendar events", error, retry: { [weak self] in self?.deleteEventByType(type) })
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

    // MARK: - Calendar Access

    func fetchAccessData() {
        Task {
            do {
                let data = try await CalendarAccessAPI.getAccessData(username: username)
                await MainActor.run { self.accessData = data }
            } catch {
                AppBanner.report("load calendar sharing", error, retry: { [weak self] in self?.fetchAccessData() })
            }
        }
    }

    private var friendCalendarsTask: Task<Void, Never>?

    func fetchFriendCalendars() {
        // only the newest load counts (several can start at once, e.g. after accepting an invite)
        friendCalendarsTask?.cancel()
        let username = self.username
        friendCalendarsTask = Task {
            do {
                let friendList = try await FriendsAPI.fetchFriendList(username: username)
                // load every friend's shared events at once, then apply them in one step on the main actor
                let loaded = await withTaskGroup(of: (String, [Event]?).self) { group in
                    for friend in friendList.friends {
                        group.addTask {
                            (friend, try? await CalendarAccessAPI.getSharedEvents(owner: friend, requester: username))
                        }
                    }
                    var results: [String: [Event]] = [:]
                    for await (friend, events) in group {
                        if let events, !events.isEmpty { results[friend] = events }
                    }
                    return results
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { self.applyFriendCalendars(loaded) }
            } catch {
                if !Task.isCancelled {
                    AppBanner.report("load your friends' calendars", error, retry: { [weak self] in self?.fetchFriendCalendars() })
                }
            }
        }
    }

    // friends keep their color; new ones get the next unused palette color, in name order
    @MainActor
    private func applyFriendCalendars(_ calendars: [String: [Event]]) {
        var colors = friendColors.filter { calendars.keys.contains($0.key) }
        var next = colors.count
        for friend in calendars.keys.sorted() where colors[friend] == nil {
            colors[friend] = friendColorPalette[next % friendColorPalette.count]
            next += 1
        }
        friendCalendars = calendars
        friendColors = colors
    }

    func sendCalendarInvite(to friend: String, level: String, requireApproval: Bool) {
        Task {
            do {
                _ = try await CalendarAccessAPI.sendInvite(from: username, to: friend, level: level, requireApproval: requireApproval)
                fetchAccessData()
            } catch {
                AppBanner.report("send the calendar invite", error, retry: { [weak self] in
                    self?.sendCalendarInvite(to: friend, level: level, requireApproval: requireApproval)
                })
            }
        }
    }

    func respondToCalendarInvite(inviteId: String, accept: Bool) {
        Task {
            do {
                try await CalendarAccessAPI.respondToInvite(recipient: username, inviteId: inviteId, accept: accept)
                fetchAccessData()
                fetchFriendCalendars()
            } catch {
                AppBanner.report(accept ? "accept the calendar invite" : "decline the calendar invite", error, retry: { [weak self] in
                    self?.respondToCalendarInvite(inviteId: inviteId, accept: accept)
                })
            }
        }
    }

    @MainActor
    func approveCalendarEvent(eventId: String) {
        Task {
            do {
                try await CalendarAccessAPI.approveEvent(owner: username, eventId: eventId)
                fetchEvents()
            } catch {
                AppBanner.report("approve the event", error, retry: { [weak self] in self?.approveCalendarEvent(eventId: eventId) })
            }
        }
    }

    @MainActor
    func rejectCalendarEvent(eventId: String) {
        Task {
            do {
                try await CalendarAccessAPI.rejectEvent(owner: username, eventId: eventId)
                fetchEvents()
            } catch {
                AppBanner.report("decline the event", error, retry: { [weak self] in self?.rejectCalendarEvent(eventId: eventId) })
            }
        }
    }

    @MainActor
    func respondToEventInvite(eventId: String, accept: Bool) {
        Task {
            do {
                try await CalendarAPI.respondToEventInvite(username: username, eventId: eventId, accept: accept)
                fetchEvents()
            } catch {
                AppBanner.report(accept ? "accept the invite" : "decline the invite", error, retry: { [weak self] in
                    self?.respondToEventInvite(eventId: eventId, accept: accept)
                })
            }
        }
    }

    func revokeCalendarAccess(from friend: String, keepEvents: Bool) {
        Task {
            do {
                try await CalendarAccessAPI.revokeAccess(owner: username, friend: friend, keepEvents: keepEvents)
                fetchAccessData()
                fetchFriendCalendars()
            } catch {
                AppBanner.report("stop sharing your calendar", error, retry: { [weak self] in
                    self?.revokeCalendarAccess(from: friend, keepEvents: keepEvents)
                })
            }
        }
    }

    func friendEventsOnDay(_ date: Date) -> [(event: Event, friend: String, color: Color)] {
        guard showFriendOverlays else { return [] }
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let ownIds = Set(events.map { $0.id })
        return friendCalendars.flatMap { (friend, evts) in
            evts.filter { $0.startDate < dayEnd && $0.endDate >= dayStart && !ownIds.contains($0.id) }
                .map { (event: $0, friend: friend, color: friendColors[friend] ?? .purple) }
        }
    }

    func addMonthlyInvestmentReminder(dayOfMonth: Int = 1) {
        let calendar = Calendar.current
        let today = Date()

        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = dayOfMonth

        guard let investmentDate = calendar.date(from: components) else { return }

        Task {
            await createEvent(
                title: "Invest in Portfolio",
                description: "Time to invest in your stock portfolio!",
                startDate: investmentDate,
                endDate: investmentDate,
                eventType: "investment",
                recurrence: "monthly",
                invitedFriends: []
            )
        }

        scheduleInvestmentNotification(for: investmentDate)
    }
    
    func scheduleInvestmentNotification(for date: Date) {
        print("Inside notification for investing")
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["investment-reminder"])
        
        let content = UNMutableNotificationContent()
        content.title = "Time to Invest!"
        content.body = "Don't forget to contribute to your portfolio today!"
        content.sound = .default

        let now = Date()
        let calendar = Calendar.current
        let triggerDate = calendar.dateComponents([.year, .month, .day], from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            // If it's today, fire in 5 seconds
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: "investment-reminder", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Notification error: \(error.localizedDescription)")
                } else {
                    print("Investment notification scheduled for today (5s delay)")
                }
            }

        } else {
            // Future calendar-based notification
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            let request = UNNotificationRequest(identifier: "investment-reminder", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Notification error: \(error.localizedDescription)")
                } else {
                    print("Investment notification scheduled for future date")
                }
            }
        }
    }

    // MARK: - Google Calendar Sync

    // Called on app launch — silently restores session and syncs if connected
    func syncGoogleCalendarIfConnected() {
        Task {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in c.resume() }
            }
            guard GIDSignIn.sharedInstance.currentUser != nil else { return }
            await syncGoogleCalendar(quiet: true)
        }
    }

    // Fetches Google Calendar events and batch-syncs them in a single backend call
    @MainActor
    func syncGoogleCalendar(quiet: Bool = false) async {
        do {
            let token = try await GoogleCalendarAPI.requestCalendarAccess()
            let now = Date()
            let cal = Calendar.current
            let from = cal.date(byAdding: .month, value: -1, to: now)!
            let to   = cal.date(byAdding: .month, value: 6, to: now)!
            let googleEvents = try await GoogleCalendarAPI.fetchEvents(accessToken: token, from: from, to: to)

            let gcalPlotlineEvents = googleEvents.map { e in
                Event(id: "gcal_\(e.id)", title: e.title, description: e.description,
                      startDate: e.start, endDate: e.end,
                      eventType: "user", recurrence: "none", invitedFriends: [])
            }

            let allEvents = try await CalendarAPI.batchSyncGcal(gcalPlotlineEvents, username: username)
            self.events = expandRecurringEvents(allEvents)
        } catch {
            if quiet {
                print("Google Calendar sync skipped: \(error.localizedDescription)")
            } else {
                AppBanner.report("import your Google Calendar", error)
            }
        }
    }

    // Signs out and deletes all imported Google Calendar events
    @MainActor
    func disconnectGoogleCalendar() {
        GIDSignIn.sharedInstance.signOut()
        let gcalIds = events.filter { $0.id.hasPrefix("gcal_") }.map { $0.id }
        events.removeAll { $0.id.hasPrefix("gcal_") }
        Task {
            var failed = 0
            for id in gcalIds {
                do { try await CalendarAPI.deleteEvent(id, username: username) } catch { failed += 1 }
            }
            if failed > 0 {
                AppBanner.report("remove \(failed) imported Google event\(failed == 1 ? "" : "s")")
                fetchEvents()
            }
        }
    }

}
