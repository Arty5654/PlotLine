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
            AddEventSheet(defaultDate: day) { title, description, start, end, recur in
                viewModel.createEvent(
                    title: title,
                    description: description,
                    startDate: start,
                    endDate: end,
                    eventType: "user",
                    recurrence: recur
                )
            }
        }

        .sheet(item: $selectedEvent) { eventToEdit in
            AddEventSheet(existingEvent: eventToEdit) { newTitle, newDesc, newStart, newEnd, newRecurrence in
                
                var updatedEvent = eventToEdit
                updatedEvent.title = newTitle
                updatedEvent.description = newDesc
                updatedEvent.startDate = newStart
                updatedEvent.endDate = newEnd
                updatedEvent.recurrence = newRecurrence
                        
                viewModel.updateEvent(event: updatedEvent)
            }
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
            if (eventToDelete.eventType == "user") {
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

    var body: some View {
        List {
            ForEach(events) { event in
                Button {
                    selectedEvent = event
                } label: {
                    EventRow(event: event)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private func delete(at offsets: IndexSet) {
        offsets.forEach { index in
            let eventToDelete = events[index]
            viewModel.deleteEvent(eventToDelete.id)
        }
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
        }
        .padding(.vertical, 8)
    }
    
    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: date)
    }
}



#Preview {
    DayView(day: Date(), viewModel: CalendarViewModel())
}

