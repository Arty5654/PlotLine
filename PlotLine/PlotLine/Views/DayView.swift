//
//  DayView.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import SwiftUI

struct DayView: View {
    let day: Date
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel

    @State private var showingAddEventSheet = false
    @State private var selectedEvent: Event? = nil

    var body: some View {
        VStack {
            Text("Events")
                .font(.custom("AvenirNext-Bold", size: 20))
                .padding(.top, 16)

            let eventsToday = viewModel.eventsOnDay(day)
            if eventsToday.isEmpty {
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddEventSheet = true
                }) {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
            }
        }
        .sheet(isPresented: $showingAddEventSheet) {
            AddEventSheet(defaultDate: day, existingEvents: viewModel.events) { title, description, start, end, recur, friends, eventType in
                viewModel.createEvent(
                    title: title,
                    description: description,
                    startDate: start,
                    endDate: end,
                    eventType: eventType,
                    recurrence: recur,
                    invitedFriends: friends
                )
            }.environmentObject(friendVM)
        }

        .sheet(item: $selectedEvent) { eventToEdit in
            AddEventSheet(existingEvent: eventToEdit, existingEvents: viewModel.events) { newTitle, newDesc, newStart, newEnd, newRecurrence, newFriends, newEventType in

                var updatedEvent = eventToEdit
                updatedEvent.title = newTitle
                updatedEvent.description = newDesc
                updatedEvent.startDate = newStart
                updatedEvent.endDate = newEnd
                updatedEvent.recurrence = newRecurrence
                updatedEvent.invitedFriends = newFriends
                updatedEvent.eventType = newEventType

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

    var body: some View {
        List {
            ForEach(events) { event in
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
            .onDelete(perform: delete)
        }
        .listStyle(InsetGroupedListStyle())
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
        }
    }

    private func delete(at offsets: IndexSet) {
        offsets.forEach { index in
            viewModel.deleteEvent(events[index].id)
        }
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
}


private struct EventRow: View {
    let event: Event
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
                .foregroundColor(
                    event.eventType == "rent" ? .red : //rent
                    event.eventType.hasPrefix("subscription") ? .orange : //subscription
                    event.eventType.hasPrefix("weekly-goal") ? .green : //goal
                    .primary // other
                )
            
            if !event.description.isEmpty {
                Text(event.description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            // Show multi-day info
            if !Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
                Text("\(format(event.startDate)) through \(format(event.endDate))")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            
            if event.recurrence != "none" {
                Text("Occurs \(event.recurrence)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            
            if !filteredInvitedFriends.isEmpty {
                Text("Invited: \(filteredInvitedFriends.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
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



#Preview {
    DayView(day: Date(), viewModel: CalendarViewModel())
}

