//
//  DayView.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import SwiftUI
import UserNotifications

struct DayView: View {
    let day: Date
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var showingAddEventSheet = false
    @State private var selectedEvent: Event? = nil

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    var body: some View {
        VStack {
            Text("Events")
                .font(.custom("AvenirNext-Bold", size: 20))
                .padding(.top, 16)

            let eventsToday = viewModel.eventsOnDay(day)
            let friendEventsToday = viewModel.friendEventsOnDay(day)
            if eventsToday.isEmpty && friendEventsToday.isEmpty {
                Spacer()
                Text("No events")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer()
            } else {
                DayEventsList(
                    day: day,
                    events: eventsToday,
                    viewModel: viewModel,
                    selectedEvent: $selectedEvent
                )
            }
        }
        .navigationTitle(formattedDate(day))
        .tint(adaptiveTextColor)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddEventSheet = true
                }) {
                    Image(systemName: "plus")
                        .imageScale(.large)
                        .foregroundColor(adaptiveTextColor)
                }
            }
        }
        .sheet(isPresented: $showingAddEventSheet) {
            let publishable = viewModel.accessData.receivedAccess.filter { $0.level == "add" }.map { $0.friendUsername }
            AddEventSheet(defaultDate: day, existingEvents: viewModel.events, publishableFriendCalendars: publishable) { eventId, title, description, start, end, recur, friends, eventType, friendsCanSee, publishTo in
                viewModel.createEvent(
                    id: eventId,
                    title: title,
                    description: description,
                    startDate: start,
                    endDate: end,
                    eventType: eventType,
                    recurrence: recur,
                    invitedFriends: friends,
                    friendsCanSee: friendsCanSee,
                    publishToCalendars: publishTo
                )
            }.environmentObject(friendVM)
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
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
    
    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: date)
    }
    
    private func delete(at offsets: IndexSet) {
        let dayEvents = viewModel.eventsOnDay(day)
        
        offsets.forEach { index in
            let eventToDelete = dayEvents[index]
            if eventToDelete.eventType == "user" || eventToDelete.eventType.hasPrefix("subscription") {
                viewModel.deleteEvent(eventToDelete.id)
            }
        }
    }


}

private struct DayEventsList: View {
    let day: Date
    let events: [Event]
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var selectedEvent: Event?

    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    @State private var eventToMove: Event? = nil
    @State private var showMoveDatePicker = false
    @State private var moveTargetDate = Date()
    @State private var eventToDuplicate: Event? = nil
    @State private var showDuplicateDatePicker = false
    @State private var duplicateTargetDate = Date()
    @State private var selectedFriendEvent: IdentifiableFriendEvent? = nil

    var body: some View {
        List {
            ForEach(events) { event in
                eventRowContent(for: event)
            }
            .onDelete(perform: delete)

            // Friend events overlay
            let friendEvts = viewModel.friendEventsOnDay(day)
            if !friendEvts.isEmpty {
                Section(header: Text("Friends' Events").font(.caption).foregroundColor(.secondary)) {
                    ForEach(friendEvts, id: \.event.id) { item in
                        Button {
                            selectedFriendEvent = IdentifiableFriendEvent(event: item.event, friend: item.friend, color: item.color)
                        } label: {
                            HStack(spacing: 8) {
                                Rectangle()
                                    .fill(item.color)
                                    .frame(width: 4)
                                    .cornerRadius(2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.event.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(item.friend)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .sheet(item: $selectedFriendEvent) { item in
            FriendEventDetailSheet(event: item.event, friend: item.friend, color: item.color)
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

    private func delete(at offsets: IndexSet) {
        offsets.forEach { index in
            viewModel.deleteEvent(events[index].id)
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

    @ViewBuilder
    private func eventRowContent(for event: Event) -> some View {
        if event.status == "invite-pending" {
            HStack {
                EventRow(event: event)
                Spacer()
                Button {
                    viewModel.respondToEventInvite(eventId: event.id, accept: true)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
                Button {
                    viewModel.respondToEventInvite(eventId: event.id, accept: false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
            }
        } else if event.addedBy != nil {
            HStack {
                EventRow(event: event)
                Menu {
                    Button(role: .destructive) {
                        if event.status == "accepted" {
                            // Event invite: notify creator it was removed
                            viewModel.respondToEventInvite(eventId: event.id, accept: false)
                        } else {
                            // Calendar-sharing event ("pending"/"approved"): just delete
                            viewModel.deleteEvent(event.id)
                        }
                    } label: {
                        Label("Remove from My Calendar", systemImage: "calendar.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(adaptiveTextColor)
                        .font(.title3)
                }
            }
        } else {
            HStack {
                Button {
                    selectedEvent = event
                } label: {
                    EventRow(event: event)
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
                        .font(.title3)
                }
            }
        }
    }
}


private struct EventRow: View {
    let event: Event
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
                .foregroundColor(
                    event.eventType == "rent" ? .red :
                    event.eventType.hasPrefix("subscription") ? .orange :
                    event.eventType.hasPrefix("weekly-goal") ? .green :
                    .primary
                )

            if let addedBy = event.addedBy {
                Text("Added by \(addedBy)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !event.description.isEmpty {
                Text(event.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Show multi-day info
            if !Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
                Text("\(format(event.startDate)) through \(format(event.endDate))")
                    .font(.subheadline)
                    .foregroundColor(adaptiveTextColor)
            }

            if event.recurrence != "none" {
                Text("Occurs \(event.recurrence)")
                    .font(.subheadline)
                    .foregroundColor(adaptiveTextColor)
            }

            if !filteredInvitedFriends.isEmpty {
                if event.inviteStatuses.isEmpty {
                    Text("Invited: \(filteredInvitedFriends.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundColor(adaptiveTextColor)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredInvitedFriends, id: \.self) { friend in
                            let rsvpStatus = event.inviteStatuses[friend] ?? "pending"
                            HStack(spacing: 4) {
                                Image(systemName: rsvpIcon(rsvpStatus))
                                    .foregroundColor(rsvpColor(rsvpStatus))
                                    .font(.caption)
                                Text(friend)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func rsvpIcon(_ status: String) -> String {
        switch status {
        case "accepted": return "checkmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        default:         return "clock.fill"
        }
    }

    private func rsvpColor(_ status: String) -> Color {
        switch status {
        case "accepted": return .green
        case "declined": return .red
        default:         return .orange
        }
    }
    
    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: date)
    }
    
    private var filteredInvitedFriends: [String] {
        event.invitedFriends.filter { !$0.contains("-creator-user-") }
    }
}



private struct IdentifiableFriendEvent: Identifiable {
    let id: String
    let event: Event
    let friend: String
    let color: Color

    init(event: Event, friend: String, color: Color) {
        self.id = event.id
        self.event = event
        self.friend = friend
        self.color = color
    }
}

private struct FriendEventDetailSheet: View {
    let event: Event
    let friend: String
    let color: Color

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    struct ReminderOption: Identifiable {
        let id: TimeInterval
        let label: String
        var secondsBefore: TimeInterval { id }
    }
    private let reminderOptions: [ReminderOption] = [
        ReminderOption(id: 15 * 60,      label: "15 minutes before"),
        ReminderOption(id: 60 * 60,      label: "1 hour before"),
        ReminderOption(id: 24 * 60 * 60, label: "1 day before"),
        ReminderOption(id: 0,            label: "At start time")
    ]
    @State private var selectedReminders: Set<TimeInterval>

    init(event: Event, friend: String, color: Color) {
        self.event = event
        self.friend = friend
        self.color = color
        let saved = UserDefaults.standard.array(forKey: "event_reminders_\(event.id)") as? [Double] ?? []
        _selectedReminders = State(initialValue: Set(saved.map { TimeInterval($0) }))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(color)
                            .frame(width: 4)
                            .cornerRadius(2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.headline)
                            Text("From \(friend)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !event.description.isEmpty {
                    Section(header: Text("Description")) {
                        Text(event.description)
                            .foregroundColor(.primary)
                    }
                }

                Section(header: Text("Date & Time")) {
                    if Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
                        Label(formatDateTime(event.startDate), systemImage: "clock")
                    } else {
                        Label("Starts: \(formatDateTime(event.startDate))", systemImage: "clock")
                        Label("Ends: \(formatDateTime(event.endDate))", systemImage: "calendar")
                    }
                }

                Section(header: Text("Reminders")) {
                    ForEach(reminderOptions) { opt in
                        Toggle(opt.label, isOn: Binding<Bool>(
                            get: { selectedReminders.contains(opt.secondsBefore) },
                            set: { isOn in
                                if isOn { selectedReminders.insert(opt.secondsBefore) }
                                else { selectedReminders.remove(opt.secondsBefore) }
                                saveAndSchedule()
                            }
                        ))
                    }
                }
                .tint(.blue)
            }
            .navigationBarTitle("Event Details", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .tint(adaptiveTextColor)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func saveAndSchedule() {
        UserDefaults.standard.set(Array(selectedReminders), forKey: "event_reminders_\(event.id)")
        let center = UNUserNotificationCenter.current()
        let allIds = reminderOptions.map { "reminder_\(event.id)_\(Int($0.secondsBefore))" }
        center.removePendingNotificationRequests(withIdentifiers: allIds)

        for opt in reminderOptions where selectedReminders.contains(opt.secondsBefore) {
            let triggerDate = event.startDate.addingTimeInterval(-opt.secondsBefore)
            guard triggerDate > Date() else { continue }
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            comps.second = 0
            let content = UNMutableNotificationContent()
            content.title = "Upcoming Event"
            content.body = switch opt.secondsBefore {
                case 0:         "\(event.title) is starting now!"
                case 15 * 60:  "\(event.title) starts in 15 minutes"
                case 60 * 60:  "\(event.title) starts in 1 hour"
                default:        "\(event.title) starts in 24 hours"
            }
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "reminder_\(event.id)_\(Int(opt.secondsBefore))",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            center.add(request)
        }
    }
}

#Preview {
    DayView(day: Date(), viewModel: CalendarViewModel())
}

