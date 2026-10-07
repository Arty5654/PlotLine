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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PLSpacing.lg) {

                // month / week, and moving between them
                VStack(spacing: PLSpacing.md) {
                    Picker("View", selection: Binding(
                        get: { viewModel.displayMode == .month },
                        set: { $0 ? viewModel.showMonthView() : viewModel.showWeekView() }
                    )) {
                        Text("Month").tag(true)
                        Text("Week").tag(false)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Button {
                            viewModel.displayMode == .month ? viewModel.previousMonth() : viewModel.previousWeek()
                        } label: {
                            Image(systemName: "chevron.left").font(.headline)
                        }
                        .accessibilityLabel(viewModel.displayMode == .month ? "Previous month" : "Previous week")
                        Spacer()
                        Text(viewModel.displayMode == .month ? monthTitle(for: viewModel.currentDate) : weekTitle(for: viewModel.currentDate))
                            .font(.headline)
                            .foregroundColor(PLColor.textPrimary)
                        Spacer()
                        Button {
                            viewModel.displayMode == .month ? viewModel.nextMonth() : viewModel.nextWeek()
                        } label: {
                            Image(systemName: "chevron.right").font(.headline)
                        }
                        .accessibilityLabel(viewModel.displayMode == .month ? "Next month" : "Next week")
                    }
                    .foregroundColor(PLColor.tint)
                    .padding(.horizontal, 4)
                }

                if viewModel.displayMode == .month {
                    MonthContent(viewModel: viewModel, monthColumns: monthColumns)
                        .environmentObject(friendVM)
                        .plCard()
                } else {
                    WeekContent(viewModel: viewModel).environmentObject(friendVM)
                }

                VStack(spacing: PLSpacing.sm) {
                    Button { showingAddEventSheet = true } label: {
                        Label("Add Event", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButton())

                    Button { showingGoogleImport = true } label: {
                        Label("Import from Google Calendar", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(OutlineButton(tint: PLColor.tint))
                }

                // Pending event invites (current user was invited by someone)
                let invites = viewModel.pendingInviteEvents
                if !invites.isEmpty {
                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Event invites")
                        VStack(spacing: 0) {
                            ForEach(Array(invites.enumerated()), id: \.element.id) { index, event in
                                if index > 0 { Divider() }
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text([event.addedBy.map { "From \($0)" }, formatEventDate(event.startDate)]
                                                .compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundColor(PLColor.textSecondary)
                                    }
                                    Spacer()
                                    Button("Join") {
                                        viewModel.respondToEventInvite(eventId: event.id, accept: true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(PLColor.success)
                                    Button("Decline") {
                                        viewModel.respondToEventInvite(eventId: event.id, accept: false)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .controlSize(.small)
                                .padding(.vertical, 8)
                            }
                        }
                        .plCard()
                    }
                }

                // Pending event approvals (calendar-sharing add flow)
                let pending = viewModel.pendingEvents
                if !pending.isEmpty {
                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Waiting for your approval")
                        VStack(spacing: 0) {
                            ForEach(Array(pending.enumerated()), id: \.element.id) { index, event in
                                if index > 0 { Divider() }
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(.subheadline.weight(.semibold))
                                        if let addedBy = event.addedBy {
                                            Text("Added by \(addedBy)")
                                                .font(.caption)
                                                .foregroundColor(PLColor.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Button("Approve") {
                                        viewModel.approveCalendarEvent(eventId: event.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(PLColor.success)
                                    Button("Decline") {
                                        viewModel.rejectCalendarEvent(eventId: event.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .controlSize(.small)
                                .padding(.vertical, 8)
                            }
                        }
                        .plCard()
                    }
                }

                // Friend calendar overlays toggle
                if !viewModel.friendColors.isEmpty {
                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Friends' calendars")
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Show on my calendar", isOn: $viewModel.showFriendOverlays)
                                .tint(PLColor.accent)
                            HStack(spacing: 12) {
                                ForEach(Array(viewModel.friendColors.keys).sorted(), id: \.self) { friend in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(viewModel.friendColors[friend] ?? .purple)
                                            .frame(width: 8, height: 8)
                                        Text(friend)
                                            .font(.caption)
                                            .foregroundColor(PLColor.textSecondary)
                                    }
                                }
                            }
                        }
                        .plCard()
                    }
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.md)
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
            // Programmatic navigation to DayView
            .navigationDestination(isPresented: Binding(
                get: { viewModel.navigateToDayView != nil },
                set: { if !$0 { viewModel.navigateToDayView = nil } }
            )) {
                if let day = viewModel.navigateToDayView {
                    DayView(day: day, viewModel: viewModel)
                        .environmentObject(friendVM)
                }
            }
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

    var body: some View {
        VStack(alignment: .leading) {
            // Day names
            let dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            HStack {
                ForEach(dayNames, id: \.self) { dayName in
                    Text(dayName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(PLColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            
            // Month grid
            let daysInMonth = viewModel.daysInCurrentMonth()
            if let firstDayOfMonth = daysInMonth.first {
                let calendar = Calendar.current
                let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
                let offset = firstWeekday - 1
                
                LazyVGrid(columns: monthColumns, spacing: 12) {
                    ForEach(0..<offset, id: \.self) { _ in
                        Text("")
                    }
                    ForEach(daysInMonth, id: \.self) { day in
                        let friendDots: [String] = {
                            guard viewModel.showFriendOverlays else { return [] }
                            let friends = viewModel.friendEventsOnDay(day).map { $0.friend }
                            return Array(Set(friends)).sorted().prefix(3).map { $0 }
                        }()

                        NavigationLink(destination: DayView(day: day, viewModel: viewModel).environmentObject(friendVM)) {
                            let isToday = Calendar.current.isDateInToday(day)
                            VStack(spacing: 2) {
                                Text(dayNumber(day))
                                    .font(.body.weight(isToday ? .bold : .regular))
                                    .foregroundColor(isToday ? .white : PLColor.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(isToday ? PLColor.accent : colorForDay(day))
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

    var body: some View {
        let start = startOfWeek(for: viewModel.currentDate)

        VStack(spacing: PLSpacing.sm) {
            ForEach(0..<7, id: \.self) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
                let isToday = Calendar.current.isDateInToday(day)

                VStack(alignment: .leading, spacing: 8) {

                    HStack(spacing: 6) {
                        Text(shortWeekdayName(for: day))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(isToday ? PLColor.tint : PLColor.textSecondary)
                        Text(dayNumber(day))
                            .font(.headline)
                            .foregroundColor(isToday ? PLColor.tint : PLColor.textPrimary)
                        if isToday {
                            Text("Today")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(PLColor.tint)
                        }
                    }

                    let dayEvents = viewModel.eventsOnDay(day)
                    if dayEvents.isEmpty {
                        Text("No events")
                            .foregroundColor(PLColor.textSecondary)
                            .font(.subheadline)
                    } else {
                        ForEach(dayEvents) { event in
                            HStack(alignment: .center, spacing: 10) {
                                Circle()
                                    .fill(dotColor(for: event))
                                    .frame(width: 8, height: 8)
                                Button {
                                    selectedEvent = event
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.title)
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(PLColor.textPrimary)
                                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(PLColor.textSecondary)
                                    }
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
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(PLColor.textSecondary)
                                        .frame(width: 32, height: 32)
                                }
                                .accessibilityLabel("Event options")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .plCard()
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
            NavigationStack {
                Form {
                    Section(header: Text("New Date")) {
                        DatePicker("Date", selection: $moveTargetDate, displayedComponents: .date)
                            .tint(PLColor.accent)
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
            .tint(PLColor.accent)
        }
        .sheet(isPresented: $showDuplicateDatePicker) {
            NavigationStack {
                Form {
                    Section(header: Text("Duplicate To")) {
                        DatePicker("Date", selection: $duplicateTargetDate, displayedComponents: .date)
                            .tint(PLColor.accent)
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
            .tint(PLColor.accent)
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
    
    private func dotColor(for event: Event) -> Color {
        let type = event.eventType.lowercased()
        if type == "rent" { return .red }
        if type.hasPrefix("subscription") { return .yellow }
        if type.hasPrefix("weekly-goal") { return .green }
        return PLColor.accent
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

