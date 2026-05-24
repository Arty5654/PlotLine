//
//  CalendarView.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import SwiftUI

struct CalendarView: View {

    @EnvironmentObject var viewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var showingAddEventSheet = false
    @State private var showingGoogleImport = false
    private let monthColumns = Array(repeating: GridItem(.flexible()), count: 7)

    // Adaptive color: white in dark mode, blue in light mode
    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {

                // Friend calendar overlays toggle
                if !viewModel.friendColors.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Friends' Calendars")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            HStack(spacing: 8) {
                                ForEach(Array(viewModel.friendColors.keys), id: \.self) { friend in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(viewModel.friendColors[friend] ?? .purple)
                                            .frame(width: 8, height: 8)
                                        Text(friend)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.showFriendOverlays)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Pending event invites (current user was invited by someone)
                let invites = viewModel.pendingInviteEvents
                if !invites.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Event Invites")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        ForEach(invites) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.subheadline.bold())
                                    if let from = event.addedBy {
                                        Text("From \(from)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(formatEventDate(event.startDate))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    viewModel.respondToEventInvite(eventId: event.id, accept: true)
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title3)
                                }
                                Button {
                                    viewModel.respondToEventInvite(eventId: event.id, accept: false)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.title3)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 4)
                }

                // Pending event approvals (calendar-sharing add flow)
                let pending = viewModel.pendingEvents
                if !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pending Approvals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        ForEach(pending) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.subheadline.bold())
                                    if let addedBy = event.addedBy {
                                        Text("Added by \(addedBy)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    viewModel.approveCalendarEvent(eventId: event.id)
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                Button {
                                    viewModel.rejectCalendarEvent(eventId: event.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 4)
                }

                HStack {
                        if viewModel.displayMode == .month {
                            Button(action: { viewModel.previousMonth() }) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(adaptiveTextColor)
                            }

                            Text(monthTitle(for: viewModel.currentDate))
                                .font(.headline)
                                .foregroundColor(adaptiveTextColor)

                            Button(action: { viewModel.nextMonth() }) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(adaptiveTextColor)
                            }
                        } else {

                            Button(action: { viewModel.previousWeek() }) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(adaptiveTextColor)
                            }

                            Text(weekTitle(for: viewModel.currentDate))
                                .font(.headline)
                                .foregroundColor(adaptiveTextColor)

                            Button(action: { viewModel.nextWeek() }) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(adaptiveTextColor)
                            }
                        }

                        Spacer()

                        Button(action: {
                            if viewModel.displayMode == .month {
                                viewModel.showWeekView()
                            } else {
                                viewModel.showMonthView()
                            }
                        }) {
                            Text(viewModel.displayMode == .month ? "Week View" : "Month View")
                                .foregroundColor(adaptiveTextColor)
                        }
                    }
                    .padding()
                    
                    if viewModel.displayMode == .month {
                        MonthContent(viewModel: viewModel, monthColumns: monthColumns).environmentObject(friendVM)
                    } else {
                        // Weekly view
                        WeekContent(viewModel: viewModel).environmentObject(friendVM)
                    }
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            showingAddEventSheet = true
                        }) {
                            Text("Add Event")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }

                        Button(action: {
                            showingGoogleImport = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Google Cal")
                                    .font(.subheadline.bold())
                            }
                            .padding()
                            .foregroundColor(.white)
                            .background(Color(red: 0.26, green: 0.52, blue: 0.96))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                }
                .onAppear {
                    viewModel.showMonthView()
                    viewModel.fetchEvents()
                    viewModel.fetchAccessData()
                    viewModel.fetchFriendCalendars()
                }
            }
            .sheet(isPresented: $showingAddEventSheet) {
                let publishable = viewModel.accessData.receivedAccess.filter { $0.level == "add" }.map { $0.friendUsername }
                AddEventSheet(defaultDate: viewModel.selectedDay ?? viewModel.currentDate, existingEvents: viewModel.events, publishableFriendCalendars: publishable) { eventId, title, description, start, end, recurrence, friends, eventType, friendsCanSee, publishTo in
                    viewModel.createEvent(
                        id: eventId,
                        title: title,
                        description: description,
                        startDate: start,
                        endDate: end,
                        eventType: eventType,
                        recurrence: recurrence,
                        invitedFriends: friends,
                        friendsCanSee: friendsCanSee,
                        publishToCalendars: publishTo
                    )
                }.environmentObject(friendVM)
            }
            .sheet(isPresented: $showingGoogleImport) {
                GoogleCalendarImportView()
                    .environmentObject(viewModel)
            }
            .background(
                // Programmatic navigation to DayView
                NavigationLink(
                    destination: Group {
                        if let day = viewModel.navigateToDayView {
                            DayView(day: day, viewModel: viewModel)
                                .environmentObject(friendVM)
                        }
                    },
                    isActive: Binding(
                        get: { viewModel.navigateToDayView != nil },
                        set: { if !$0 { viewModel.navigateToDayView = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            )
    }

    private func formatEventDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }
    
    private func weekTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Week of' MMM d, yyyy"
        return formatter.string(from: startOfWeek(for: date))
    }
    
    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }
    
    private func shortWeekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
    
    private func startOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        // If you want Monday to be the very start of the week:
        // calendar.firstWeekday = 2
        calendar.firstWeekday = 1
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}


struct MonthContent: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel
    @Environment(\.colorScheme) var colorScheme
    let monthColumns: [GridItem]

    // Adaptive color: white in dark mode, blue in light mode
    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    var body: some View {
        VStack(alignment: .leading) {
            // Day names
            let dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            HStack {
                ForEach(dayNames, id: \.self) { dayName in
                    Text(dayName)
                        .font(.subheadline)
                        .foregroundColor(adaptiveTextColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Month grid
            let daysInMonth = viewModel.daysInCurrentMonth()
            if let firstDayOfMonth = daysInMonth.first {
                let calendar = Calendar.current
                let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
                let offset = firstWeekday - 1
                
                LazyVGrid(columns: monthColumns, spacing: 20) {
                    ForEach(0..<offset, id: \.self) { _ in
                        Text("")
                    }
                    ForEach(daysInMonth, id: \.self) { day in
                        let ownEvents = viewModel.eventsOnDay(day)
                        let friendDots: [String] = {
                            guard viewModel.showFriendOverlays else { return [] }
                            let friends = viewModel.friendEventsOnDay(day).map { $0.friend }
                            return Array(Set(friends)).sorted().prefix(3).map { $0 }
                        }()

                        NavigationLink(destination: DayView(day: day, viewModel: viewModel).environmentObject(friendVM)) {
                            VStack(spacing: 2) {
                                Text(dayNumber(day))
                                    .foregroundColor(adaptiveTextColor)
                                    .frame(width: 30, height: 30)
                                    .background(colorForDay(day))
                                    .clipShape(Circle())

                                HStack(spacing: 3) {
                                    ForEach(friendDots, id: \.self) { friend in
                                        Circle()
                                            .fill(viewModel.friendColors[friend] ?? .purple)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }.environmentObject(friendVM)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
    
    // helpers for month
    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }
    
    private func colorForDay(_ day: Date) -> Color {
        // Get all events for this day
        let dayEvents = viewModel.eventsOnDay(day)
        if dayEvents.isEmpty {
            return .clear
        }

        if dayEvents.contains(where: { $0.eventType == "rent" }) {
            // on rent due dates, color red
            return Color.red.opacity(0.2)
        } else if dayEvents.contains(where: { $0.eventType.lowercased().starts(with: "subscription") }) {
            // on subscription due dates, color yellow
            return Color.yellow.opacity(0.2)
        } else if dayEvents.contains(where: { $0.eventType.lowercased().starts(with: "weekly-goal")}) {
            // on goal dates, green
            return Color.green.opacity(0.2)
        } else {
            return Color.blue.opacity(0.2)
        }
    }
}

struct WeekContent: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedEvent: Event? = nil
    @State private var eventToMove: Event? = nil
    @State private var showMoveDatePicker = false
    @State private var moveTargetDate = Date()
    @State private var eventToDuplicate: Event? = nil
    @State private var showDuplicateDatePicker = false
    @State private var duplicateTargetDate = Date()

    // Adaptive color: white in dark mode, blue in light mode
    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    var body: some View {
        let start = startOfWeek(for: viewModel.currentDate)

        VStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!

                VStack(alignment: .leading, spacing: 4) {

                    HStack {
                        Text(shortWeekdayName(for: day))
                            .font(.subheadline)
                            .foregroundColor(adaptiveTextColor)
                        Text(dayNumber(day))
                            .font(.headline)
                            .foregroundColor(adaptiveTextColor)
                    }

                    let dayEvents = viewModel.eventsOnDay(day)
                    if dayEvents.isEmpty {
                        Text("No events")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(dayEvents) { event in
                            HStack(alignment: .center, spacing: 6) {
                                Text("•").font(.body)
                                Button {
                                    selectedEvent = event
                                } label: {
                                    Text(event.title)
                                        .fontWeight(.bold)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(PlainButtonStyle())
                                Menu {
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button {
                                        eventToMove = event
                                        moveTargetDate = event.startDate
                                        showMoveDatePicker = true
                                    } label: {
                                        Label("Move to Date", systemImage: "calendar.badge.plus")
                                    }
                                    Button {
                                        eventToDuplicate = event
                                        duplicateTargetDate = event.startDate
                                        showDuplicateDatePicker = true
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }
                                    Button(role: .destructive) {
                                        viewModel.deleteEvent(event.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundColor(adaptiveTextColor)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(
                    viewModel.hasEvent(on: day) ? colorForDay(day) : Color.clear
                )
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
        .sheet(item: $selectedEvent) { eventToEdit in
            AddEventSheet(existingEvent: eventToEdit, existingEvents: viewModel.events) { _, newTitle, newDesc, newStart, newEnd, newRecurrence, newFriends, newEventType, newFriendsCanSee, _ in
                var updatedEvent = eventToEdit
                updatedEvent.title = newTitle
                updatedEvent.description = newDesc
                updatedEvent.startDate = newStart
                updatedEvent.endDate = newEnd
                updatedEvent.recurrence = newRecurrence
                updatedEvent.invitedFriends = newFriends
                updatedEvent.eventType = newEventType
                updatedEvent.friendsCanSee = newFriendsCanSee
                viewModel.updateEvent(event: updatedEvent)
            }.environmentObject(friendVM)
        }
        .sheet(isPresented: $showMoveDatePicker) {
            NavigationView {
                Form {
                    Section(header: Text("New Date")) {
                        DatePicker("Date", selection: $moveTargetDate, displayedComponents: .date)
                            .accentColor(adaptiveTextColor)
                    }
                    if let event = eventToMove {
                        Section(header: Text("Event")) {
                            Text(event.title).font(.subheadline.bold())
                        }
                    }
                }
                .navigationBarTitle("Move Event", displayMode: .inline)
                .navigationBarItems(
                    leading: Button("Cancel") { showMoveDatePicker = false },
                    trailing: Button("Move") {
                        if let event = eventToMove { moveEvent(event, to: moveTargetDate) }
                        showMoveDatePicker = false
                    }.bold()
                )
            }
            .tint(adaptiveTextColor)
        }
        .sheet(isPresented: $showDuplicateDatePicker) {
            NavigationView {
                Form {
                    Section(header: Text("Duplicate To")) {
                        DatePicker("Date", selection: $duplicateTargetDate, displayedComponents: .date)
                            .accentColor(adaptiveTextColor)
                    }
                    if let event = eventToDuplicate {
                        Section(header: Text("Event")) {
                            Text(event.title).font(.subheadline.bold())
                        }
                    }
                }
                .navigationBarTitle("Duplicate Event", displayMode: .inline)
                .navigationBarItems(
                    leading: Button("Cancel") { showDuplicateDatePicker = false },
                    trailing: Button("Duplicate") {
                        if let event = eventToDuplicate { duplicateEvent(event, to: duplicateTargetDate) }
                        showDuplicateDatePicker = false
                    }.bold()
                )
            }
            .tint(adaptiveTextColor)
        }
    }

    private func duplicateEvent(_ event: Event, to newDate: Date) {
        let cal = Calendar.current
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let timeComps = cal.dateComponents([.hour, .minute], from: event.startDate)
        var dateComps = cal.dateComponents([.year, .month, .day], from: newDate)
        dateComps.hour = timeComps.hour
        dateComps.minute = timeComps.minute
        guard let newStart = cal.date(from: dateComps) else { return }
        viewModel.createEvent(
            title: event.title,
            description: event.description,
            startDate: newStart,
            endDate: newStart.addingTimeInterval(duration),
            eventType: event.eventType,
            recurrence: event.recurrence,
            invitedFriends: event.invitedFriends,
            friendsCanSee: event.friendsCanSee
        )
    }

    private func moveEvent(_ event: Event, to newDate: Date) {
        let cal = Calendar.current
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let timeComps = cal.dateComponents([.hour, .minute], from: event.startDate)
        var dateComps = cal.dateComponents([.year, .month, .day], from: newDate)
        dateComps.hour = timeComps.hour
        dateComps.minute = timeComps.minute
        guard let newStart = cal.date(from: dateComps) else { return }
        var updated = event
        updated.startDate = newStart
        updated.endDate = newStart.addingTimeInterval(duration)
        viewModel.updateEvent(event: updated)
    }

    // Helpers
    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }
    
    private func shortWeekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
    
    private func startOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private func colorForDay(_ day: Date) -> Color {
        // Get all events for this day
        let dayEvents = viewModel.eventsOnDay(day)
        if dayEvents.isEmpty {
            return .clear
        }

        if dayEvents.contains(where: { $0.eventType == "rent" }) {
            // on rent due dates, color red
            return Color.red.opacity(0.2)
        } else if dayEvents.contains(where: { $0.eventType.lowercased().starts(with: "subscription") }) {
            // on subscription due dates, color yellow
            return Color.yellow.opacity(0.2)
        } else if dayEvents.contains(where: { $0.eventType.lowercased().starts(with: "weekly-goal")}) {
            // on goal dates, green
            return Color.green.opacity(0.2)
        } else {
            return Color.blue.opacity(0.2)
        }
    }
    

}





#Preview {
    CalendarView().environmentObject(CalendarViewModel())
}

